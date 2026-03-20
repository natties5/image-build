#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/layout.sh"
imagectl_init_layout "$REPO_ROOT"
imagectl_ensure_layout_dirs

CONFIG_FILE="${1:?usage: phases/download_multi_os.sh <config-file>}"

[[ -f "$CONFIG_FILE" ]] || { echo "missing config: $CONFIG_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

PIPELINE_ROOT="${PIPELINE_ROOT:-$REPO_ROOT}"
OS_FAMILY="${OS_FAMILY:?OS_FAMILY is required}"
MANIFESTS_DIR="$PIPELINE_ROOT/manifests"
LEGACY_MANIFEST_DIR="$PIPELINE_ROOT/manifest"
UBUNTU_MANIFEST_DIR="$MANIFESTS_DIR/ubuntu"
OPENSTACK_MANIFEST_DIR="$MANIFESTS_DIR/openstack"
LEGACY_UBUNTU_MANIFEST_DIR="$LEGACY_MANIFEST_DIR/ubuntu"
LEGACY_OPENSTACK_MANIFEST_DIR="$LEGACY_MANIFEST_DIR/openstack"
mkdir -p "$MANIFESTS_DIR" "$LEGACY_MANIFEST_DIR" "$UBUNTU_MANIFEST_DIR" "$OPENSTACK_MANIFEST_DIR" "$LEGACY_UBUNTU_MANIFEST_DIR" "$LEGACY_OPENSTACK_MANIFEST_DIR"
ARCH="${ARCH:-x86_64}"
CACHE_DIR="${CACHE_DIR:-$PIPELINE_ROOT/cache/$OS_FAMILY}"
LOG_DIR="${LOG_DIR:-$PIPELINE_ROOT/logs}"
MANIFEST_DIR="${MANIFEST_DIR:-$MANIFESTS_DIR/$OS_FAMILY}"
LEGACY_MANIFEST_SUBDIR="${LEGACY_MANIFEST_DIR}/${OS_FAMILY}"
SUMMARY_FILE="$MANIFEST_DIR/${OS_FAMILY}-auto-discover-summary.tsv"
LEGACY_SUMMARY_FILE="$LEGACY_MANIFEST_SUBDIR/${OS_FAMILY}-auto-discover-summary.tsv"
TMP_DIR="${TMP_DIR:-$PIPELINE_ROOT/tmp}"
CURL_RETRY="${CURL_RETRY:-3}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-20}"
CURL_MAX_TIME="${CURL_MAX_TIME:-0}"
VERIFY_SHA256="${VERIFY_SHA256:-1}"
MIN_VERSION="${MIN_VERSION:?MIN_VERSION is required in $CONFIG_FILE}"
MAX_VERSION="${MAX_VERSION:-}"
ALLOW_EOL="${ALLOW_EOL:-0}"
RUN_TS="$(date '+%Y%m%d%H%M%S')"
LOG_FILE="$LOG_DIR/download-${OS_FAMILY}-auto-discover.log"

mkdir -p "$CACHE_DIR" "$LOG_DIR" "$MANIFEST_DIR" "$LEGACY_MANIFEST_SUBDIR" "$TMP_DIR"
: > "$LOG_FILE"
printf 'version\tcodename\tstatus\tartifact_name\tsha256\tlocal_path\trelease_page\tartifact_url\tnote\n' > "$SUMMARY_FILE"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
trap 'die "line=$LINENO cmd=$BASH_COMMAND"' ERR

need_cmd curl
need_cmd awk
need_cmd grep
need_cmd sed
need_cmd sort
need_cmd sha256sum
need_cmd mktemp

curl_get() {
  local url="$1"
  local curl_args=(-fsSL --retry "$CURL_RETRY" --connect-timeout "$CURL_CONNECT_TIMEOUT")
  if [[ "$CURL_MAX_TIME" != "0" ]]; then curl_args+=(--max-time "$CURL_MAX_TIME"); fi
  curl "${curl_args[@]}" "$url"
}

curl_download() {
  local url="$1" output="$2"
  local curl_args=(-fL --retry "$CURL_RETRY" --connect-timeout "$CURL_CONNECT_TIMEOUT" -o "$output")
  if [[ "$CURL_MAX_TIME" != "0" ]]; then curl_args+=(--max-time "$CURL_MAX_TIME"); fi
  curl "${curl_args[@]}" "$url"
}

version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" == "$1" ]]; }
version_le() { [[ -z "$2" || "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$2" ]]; }
version_in_range() { version_ge "$1" "$MIN_VERSION" && version_le "$1" "$MAX_VERSION"; }
escape_json() { local s="${1:-}"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"; printf '%s' "$s"; }
sha_from_sums() { local sums_content="$1" artifact_name="$2"; awk -v f="$artifact_name" '$2 == f || $2 == "*"f {print $1; exit}' <<<"$sums_content"; }

write_manifest() {
  local manifest_file="$1" version="$2" codename="$3" status="$4" artifact_name="$5" sha256="$6" release_page="$7" artifact_url="$8" local_path="$9" note="${10}"
  cat > "$manifest_file" <<JSON
{
  "run_ts": "$(escape_json "$RUN_TS")",
  "os": "$(escape_json "$OS_FAMILY")",
  "version": "$(escape_json "$version")",
  "codename": "$(escape_json "$codename")",
  "status": "$(escape_json "$status")",
  "artifact_name": "$(escape_json "$artifact_name")",
  "sha256": "$(escape_json "$sha256")",
  "release_page": "$(escape_json "$release_page")",
  "artifact_url": "$(escape_json "$artifact_url")",
  "local_path": "$(escape_json "$local_path")",
  "note": "$(escape_json "$note")"
}
JSON
}

download_and_verify() {
  local url="$1" dest="$2" expected_sha="$3" tmp_file got_sha
  tmp_file="$(mktemp "$TMP_DIR/download.XXXXXX")"
  curl_download "$url" "$tmp_file"
  if [[ "$VERIFY_SHA256" == "1" && -n "$expected_sha" ]]; then
    got_sha="$(sha256sum "$tmp_file" | awk '{print $1}')"
    [[ "$got_sha" == "$expected_sha" ]] || die "sha256 mismatch for $url expected=$expected_sha got=$got_sha"
  fi
  mv -f "$tmp_file" "$dest"
}

match_first_in_html() {
  local html="$1"; shift
  local pat
  for pat in "$@"; do
    if grep -Eo "$pat" <<<"$html" | head -n1; then
      return 0
    fi
  done
  return 1
}

match_latest_in_html() {
  local html="$1"; shift
  local pat tmp
  for pat in "$@"; do
    tmp="$(grep -Eo "$pat" <<<"$html" | sort -V | tail -n1 || true)"
    if [[ -n "$tmp" ]]; then
      printf '%s' "$tmp"
      return 0
    fi
  done
  return 1
}

write_summary_row() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" >> "$SUMMARY_FILE"
}

process_version() {
  local version="$1" codename="$2" release_page="$3" artifact_name="$4" expected_sha="$5" note="$6"
  local version_cache_dir local_path artifact_url manifest_file status got_sha

  version_cache_dir="$CACHE_DIR/$version"
  mkdir -p "$version_cache_dir"
  local_path="$version_cache_dir/$artifact_name"
  artifact_url="${release_page}${artifact_name}"
  manifest_file="$MANIFEST_DIR/${OS_FAMILY}-${version}.json"
  status="downloaded"

  if [[ -f "$local_path" ]]; then
    if [[ "$VERIFY_SHA256" == "1" && -n "$expected_sha" ]]; then
      got_sha="$(sha256sum "$local_path" | awk '{print $1}')"
      if [[ "$got_sha" == "$expected_sha" ]]; then
        status="cached"
        note="${note:+$note; }cache hit with matching sha256"
      else
        download_and_verify "$artifact_url" "$local_path" "$expected_sha"
        note="${note:+$note; }cache replaced due to sha256 mismatch"
      fi
    else
      status="cached"
      note="${note:+$note; }cache hit without verification"
    fi
  else
    download_and_verify "$artifact_url" "$local_path" "$expected_sha"
    note="${note:+$note; }downloaded fresh"
  fi

  write_manifest "$manifest_file" "$version" "$codename" "$status" "$artifact_name" "$expected_sha" "$release_page" "$artifact_url" "$local_path" "$note"
  imagectl_sync_file_to_legacy "$manifest_file" "$LEGACY_MANIFEST_SUBDIR/${OS_FAMILY}-${version}.json"
  write_summary_row "$version" "$codename" "$status" "$artifact_name" "$expected_sha" "$local_path" "$release_page" "$artifact_url" "$note"
  log "done version=$version status=$status file=$artifact_name"
}

discover_debian() {
  local base="${DEBIAN_CLOUD_BASE_URL:-https://cloud.debian.org/images/cloud}" index_html version_dir version codename latest_html latest_dir artifact_name sums_url sums_content expected_sha note
  index_html="$(curl_get "$base/" || true)"
  [[ -n "$index_html" ]] || die "cannot fetch Debian index: $base/"
  while IFS= read -r version_dir; do
    version_dir="${version_dir%/}"
    codename="$version_dir"
    version="$(awk -v c="$codename" 'BEGIN{m["stretch"]="9";m["buster"]="10";m["bullseye"]="11";m["bookworm"]="12";m["trixie"]="13"; print m[c]}' /dev/null)"
    [[ -n "$version" ]] || continue
    version_in_range "$version" || continue
    latest_html="$(curl_get "$base/$codename/" || true)"
    [[ -n "$latest_html" ]] || die "cannot fetch Debian series page: $base/$codename/"
    latest_dir="$(match_latest_in_html "$latest_html" 'daily-[0-9]{8}-[0-9]+/' 'latest/' || true)"
    [[ -n "$latest_dir" ]] || die "cannot discover Debian release dir for $codename"
    release_page="$base/$codename/$latest_dir"
    latest_html="$(curl_get "$release_page" || true)"
    [[ -n "$latest_html" ]] || die "cannot fetch Debian release page: $release_page"
    artifact_name="$(match_first_in_html "$latest_html" "debian-${version}[-a-z0-9.]*-genericcloud-${ARCH}\\.qcow2" || true)"
    [[ -n "$artifact_name" ]] || die "cannot find Debian qcow2 artifact for version=$version"
    sums_url="${release_page}SHA256SUMS"
    sums_content="$(curl_get "$sums_url" || true)"
    [[ -n "$sums_content" ]] || die "cannot fetch Debian checksums: $sums_url"
    expected_sha="$(sha_from_sums "$sums_content" "$artifact_name" || true)"
    [[ -n "$expected_sha" ]] || die "sha256 entry not found for Debian artifact $artifact_name"
    process_version "$version" "$codename" "$release_page" "$artifact_name" "$expected_sha" "series=$codename; checksum=sha256"
  done < <(printf '%s\n' "$index_html" | grep -Eo 'href="(stretch|buster|bullseye|bookworm|trixie)/"' | sed -E 's/^href="([a-z]+)\/"$/\1/' | sort -Vu)
}

discover_fedora() {
  local releases="${FEDORA_RELEASES_URL:-https://download.fedoraproject.org/pub/fedora/linux/releases}" archives="${FEDORA_ARCHIVE_URL:-https://archives.fedoraproject.org/pub/archive/fedora/linux/releases}" index_html version release_page release_html artifact_name sums_content sums_url expected_sha note source_base
  index_html="$(curl_get "$releases/" || true)"
  [[ -n "$index_html" ]] || die "cannot fetch Fedora releases index: $releases/"
  while IFS= read -r version; do
    [[ -n "$version" ]] || continue
    version_in_range "$version" || continue
    release_page="$releases/$version/Cloud/${ARCH}/images/"
    source_base="releases"
    release_html="$(curl_get "$release_page" || true)"
    if [[ -z "$release_html" ]]; then
      if [[ "$ALLOW_EOL" != "1" ]]; then
        die "Fedora version $version requires archive fallback; set ALLOW_EOL=1 to permit EOL discovery"
      fi
      release_page="$archives/$version/Cloud/${ARCH}/images/"
      source_base="archive"
      release_html="$(curl_get "$release_page" || true)"
    fi
    [[ -n "$release_html" ]] || die "cannot fetch Fedora release page for version=$version"
    artifact_name="$(match_latest_in_html "$release_html" "Fedora-Cloud-Base-Generic-${ARCH}-[0-9.-]+\\.n\\.[0-9]+\\.qcow2" "Fedora-Cloud-Base-UEFI-UKI-[A-Za-z-]+-${ARCH}-[0-9.-]+\\.n\\.[0-9]+\\.qcow2" || true)"
    [[ -n "$artifact_name" ]] || die "cannot find Fedora qcow2 artifact for version=$version"
    sums_url="${release_page}CHECKSUM"
    sums_content="$(curl_get "$sums_url" || true)"
    [[ -n "$sums_content" ]] || die "cannot fetch Fedora CHECKSUM: $sums_url"
    expected_sha="$(awk -v f="$artifact_name" '($0 ~ f) && ($0 ~ /SHA256/) {for(i=1;i<=NF;i++) if($i ~ /^[0-9a-f]{64}$/){print $i; exit}}' <<<"$sums_content")"
    [[ -n "$expected_sha" ]] || die "sha256 entry not found for Fedora artifact $artifact_name"
    note="source=$source_base; checksum=sha256"
    process_version "$version" "$version" "$release_page" "$artifact_name" "$expected_sha" "$note"
  done < <(printf '%s\n' "$index_html" | grep -Eo 'href="[0-9]{2}/"' | sed -E 's/^href="([0-9]{2})\/"$/\1/' | sort -Vu)
}

discover_almalinux() {
  local base="${ALMALINUX_BASE_URL:-https://repo.almalinux.org/almalinux}" index_html version release_page release_html artifact_name sums_url sums_content expected_sha
  index_html="$(curl_get "$base/" || true)"
  [[ -n "$index_html" ]] || die "cannot fetch AlmaLinux index: $base/"
  while IFS= read -r version; do
    version_in_range "$version" || continue
    release_page="$base/$version/cloud/${ARCH}/images/"
    release_html="$(curl_get "$release_page" || true)"
    [[ -n "$release_html" ]] || die "cannot fetch AlmaLinux release page: $release_page"
    artifact_name="$(match_latest_in_html "$release_html" "AlmaLinux-${version}-GenericCloud-latest-[0-9]+\\.${ARCH}\\.qcow2" "AlmaLinux-${version}-GenericCloud(-Base)?-latest\\.${ARCH}\\.qcow2" || true)"
    [[ -n "$artifact_name" ]] || die "cannot find AlmaLinux qcow2 artifact for version=$version"
    sums_url="${release_page}CHECKSUM"
    sums_content="$(curl_get "$sums_url" || true)"
    [[ -n "$sums_content" ]] || die "cannot fetch AlmaLinux CHECKSUM: $sums_url"
    expected_sha="$(awk -v f="$artifact_name" '($0 ~ f) && ($0 ~ /SHA256|sha256/) {for(i=1;i<=NF;i++) if($i ~ /^[0-9a-f]{64}$/){print $i; exit}}' <<<"$sums_content")"
    [[ -n "$expected_sha" ]] || die "sha256 entry not found for AlmaLinux artifact $artifact_name"
    process_version "$version" "$version" "$release_page" "$artifact_name" "$expected_sha" "checksum=sha256"
  done < <(printf '%s\n' "$index_html" | grep -Eo 'href="(8|9|10)/"' | sed -E 's/^href="([0-9]+)\/"$/\1/' | sort -Vu)
}

discover_rocky() {
  local base="${ROCKY_BASE_URL:-https://download.rockylinux.org/pub/rocky}" index_html version release_page release_html artifact_name sums_url sums_content expected_sha
  index_html="$(curl_get "$base/" || true)"
  [[ -n "$index_html" ]] || die "cannot fetch Rocky index: $base/"
  while IFS= read -r version; do
    version_in_range "$version" || continue
    release_page="$base/$version/images/${ARCH}/"
    release_html="$(curl_get "$release_page" || true)"
    [[ -n "$release_html" ]] || die "cannot fetch Rocky release page: $release_page"
    artifact_name="$(match_latest_in_html "$release_html" "Rocky-${version}(\.[0-9]+)?-GenericCloud-Base(-latest)?\\.${ARCH}\\.qcow2" "Rocky-${version}(\.[0-9]+)?-GenericCloud(-latest)?\\.${ARCH}\\.qcow2" || true)"
    [[ -n "$artifact_name" ]] || die "cannot find Rocky qcow2 artifact for version=$version"
    sums_url="${release_page}CHECKSUM"
    sums_content="$(curl_get "$sums_url" || true)"
    [[ -n "$sums_content" ]] || die "cannot fetch Rocky CHECKSUM: $sums_url"
    expected_sha="$(awk -v f="$artifact_name" '($0 ~ f) && ($0 ~ /SHA256|sha256/) {for(i=1;i<=NF;i++) if($i ~ /^[0-9a-f]{64}$/){print $i; exit}}' <<<"$sums_content")"
    [[ -n "$expected_sha" ]] || die "sha256 entry not found for Rocky artifact $artifact_name"
    process_version "$version" "$version" "$release_page" "$artifact_name" "$expected_sha" "checksum=sha256"
  done < <(printf '%s\n' "$index_html" | grep -Eo 'href="(8|9|10)/"' | sed -E 's/^href="([0-9]+)\/"$/\1/' | sort -Vu)
}

discover_centos() {
  local base="${CENTOS_CLOUD_BASE_URL:-https://cloud.centos.org/centos}" index_html series version release_page release_html artifact_name sums_url sums_content expected_sha note
  index_html="$(curl_get "$base/" || true)"
  [[ -n "$index_html" ]] || die "cannot fetch CentOS index: $base/"
  while IFS= read -r series; do
    case "$series" in
      6|7|8) version="$series"; note="source=cloud-archive" ;;
      9-stream) version="9"; note="source=stream" ;;
      10-stream) version="10"; note="source=stream" ;;
      *) continue ;;
    esac
    version_in_range "$version" || continue
    if [[ "$version" =~ ^(6|7|8)$ && "$ALLOW_EOL" != "1" ]]; then
      die "CentOS version $version is EOL; set ALLOW_EOL=1 to permit discovery"
    fi
    release_page="$base/$series/${ARCH}/images/"
    release_html="$(curl_get "$release_page" || true)"
    [[ -n "$release_html" ]] || die "cannot fetch CentOS release page: $release_page"
    artifact_name="$(match_latest_in_html "$release_html" "CentOS-(Stream-)?GenericCloud(-[0-9.]+)?(-latest)?\\.${ARCH}\\.qcow2(\\.xz)?" "CentOS-${version}(-Stream)?-[A-Za-z]+Cloud(-[0-9.]+)?(-latest)?\\.${ARCH}\\.qcow2(\\.xz)?" "CentOS-${version}-x86_64-GenericCloud[^\" ]*\\.qcow2(\\.xz)?" || true)"
    [[ -n "$artifact_name" ]] || die "cannot find CentOS cloud image for version=$version"
    sums_url="${release_page}CHECKSUM"
    sums_content="$(curl_get "$sums_url" || true)"
    if [[ -z "$sums_content" ]]; then
      sums_url="${release_page}SHA256SUMS"
      sums_content="$(curl_get "$sums_url" || true)"
    fi
    [[ -n "$sums_content" ]] || die "cannot fetch CentOS checksums for $release_page"
    expected_sha="$(awk -v f="$artifact_name" '($0 ~ f) {for(i=1;i<=NF;i++) if($i ~ /^[0-9a-f]{64}$/){print $i; exit}}' <<<"$sums_content")"
    [[ -n "$expected_sha" ]] || die "sha256 entry not found for CentOS artifact $artifact_name"
    process_version "$version" "$series" "$release_page" "$artifact_name" "$expected_sha" "$note; checksum=sha256"
  done < <(printf '%s\n' "$index_html" | grep -Eo 'href="(6|7|8|9-stream|10-stream)/"' | sed -E 's/^href="([^"]+)\/"$/\1/' | sort -Vu)
}

log "starting ${OS_FAMILY} official image auto-discover download"
log "CONFIG_FILE=$CONFIG_FILE MIN_VERSION=$MIN_VERSION MAX_VERSION=${MAX_VERSION:-<none>} ALLOW_EOL=$ALLOW_EOL ARCH=$ARCH"

case "$OS_FAMILY" in
  debian) discover_debian ;;
  fedora) discover_fedora ;;
  centos) discover_centos ;;
  almalinux) discover_almalinux ;;
  rocky) discover_rocky ;;
  *) die "unsupported multi-os family: $OS_FAMILY" ;;
esac

imagectl_sync_file_to_legacy "$SUMMARY_FILE" "$LEGACY_SUMMARY_FILE"
log "summary file: $SUMMARY_FILE"
log "done"
