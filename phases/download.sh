#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/layout.sh"
imagectl_init_layout "$REPO_ROOT"
imagectl_ensure_layout_dirs

CONFIG_FILE="${1:-$REPO_ROOT/config/os/ubuntu.env}"
LEGACY_CONFIG_FILE="${REPO_ROOT}/config/source.env"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi
if [[ -f "$LEGACY_CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$LEGACY_CONFIG_FILE"
fi

if [[ "${OS_FAMILY:-ubuntu}" != "ubuntu" ]]; then
  exec bash "$REPO_ROOT/phases/download_multi_os.sh" "$CONFIG_FILE" "$@"
fi

PIPELINE_ROOT="${PIPELINE_ROOT:-}"
if [[ -z "$PIPELINE_ROOT" ]]; then
  PIPELINE_ROOT="$REPO_ROOT"
fi

CACHE_DIR="${CACHE_DIR:-$PIPELINE_ROOT/cache/ubuntu}"
LOG_DIR="${LOG_DIR:-$PIPELINE_ROOT/logs}"
MANIFEST_DIR="${MANIFEST_DIR:-$UBUNTU_MANIFEST_DIR}"
TMP_DIR="${TMP_DIR:-$PIPELINE_ROOT/tmp}"

UBUNTU_RELEASES_BASE_URL="${UBUNTU_RELEASES_BASE_URL:-https://cloud-images.ubuntu.com/releases}"
MIN_VERSION="${MIN_VERSION:-18.04}"
LTS_ONLY="${LTS_ONLY:-1}"
ARCH="${ARCH:-amd64}"
EXCLUDE_END_OF_REGULAR_SUPPORT="${EXCLUDE_END_OF_REGULAR_SUPPORT:-0}"
FALLBACK_SERIES="${FALLBACK_SERIES:-18.04:bionic 20.04:focal 22.04:jammy 24.04:noble}"
IMAGE_PATTERNS="${IMAGE_PATTERNS:-ubuntu-{version}-server-cloudimg-{arch}.img ubuntu-{version}-server-cloudimg-{arch}-disk-kvm.img}"
CURL_RETRY="${CURL_RETRY:-3}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-20}"
CURL_MAX_TIME="${CURL_MAX_TIME:-0}"
VERIFY_SHA256="${VERIFY_SHA256:-1}"

mkdir -p "$CACHE_DIR" "$LOG_DIR" "$MANIFEST_DIR" "$TMP_DIR"

LOG_FILE="$LOG_DIR/download-ubuntu-auto-discover.log"
SUMMARY_FILE="${SUMMARY_FILE:-$UBUNTU_MANIFEST_DIR/ubuntu-auto-discover-summary.tsv}"
LEGACY_SUMMARY_FILE="${LEGACY_SUMMARY_FILE:-$LEGACY_UBUNTU_MANIFEST_DIR/ubuntu-auto-discover-summary.tsv}"
RUN_TS="$(date '+%Y%m%d%H%M%S')"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

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
  if [[ "$CURL_MAX_TIME" != "0" ]]; then
    curl_args+=(--max-time "$CURL_MAX_TIME")
  fi
  curl "${curl_args[@]}" "$url"
}

curl_download() {
  local url="$1"
  local output="$2"
  local curl_args=(-fL --retry "$CURL_RETRY" --connect-timeout "$CURL_CONNECT_TIMEOUT" -o "$output")
  if [[ "$CURL_MAX_TIME" != "0" ]]; then
    curl_args+=(--max-time "$CURL_MAX_TIME")
  fi
  curl "${curl_args[@]}" "$url"
}

version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" == "$1" ]]
}

escape_json() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

series_codename_from_fallback() {
  local version="$1"
  local pair
  for pair in $FALLBACK_SERIES; do
    if [[ "${pair%%:*}" == "$version" ]]; then
      printf '%s' "${pair##*:}"
      return 0
    fi
  done
  return 1
}

discover_versions_from_index() {
  local index_html
  index_html="$(curl_get "$UBUNTU_RELEASES_BASE_URL/" || true)"
  [[ -n "$index_html" ]] || return 0

  printf '%s\n' "$index_html" \
    | grep -Eo 'href="([0-9]{2}\.[0-9]{2})/' \
    | sed -E 's/^href="([0-9]{2}\.[0-9]{2})\/$/\1/' \
    | sort -Vu
}

build_series_list() {
  local discovered=()
  local versions_txt version codename pair

  versions_txt="$(discover_versions_from_index || true)"

  while IFS= read -r version; do
    [[ -n "$version" ]] || continue
    if ! version_ge "$version" "$MIN_VERSION"; then
      continue
    fi
    codename="$(series_codename_from_fallback "$version" || true)"
    if [[ -n "$codename" ]]; then
      discovered+=("$version:$codename")
    fi
  done <<< "$versions_txt"

  if [[ ${#discovered[@]} -eq 0 ]]; then
    for pair in $FALLBACK_SERIES; do
      version="${pair%%:*}"
      if version_ge "$version" "$MIN_VERSION"; then
        discovered+=("$pair")
      fi
    done
  fi

  printf '%s\n' "${discovered[@]}" | sort -Vu
}

find_series_dir() {
  local version="$1"
  local codename="$2"
  local candidates=(
    "$UBUNTU_RELEASES_BASE_URL/$version/"
    "$UBUNTU_RELEASES_BASE_URL/$codename/"
    "$UBUNTU_RELEASES_BASE_URL/server/$version/"
    "$UBUNTU_RELEASES_BASE_URL/server/$codename/"
  )
  local url html
  for url in "${candidates[@]}"; do
    html="$(curl_get "$url" || true)"
    if [[ -n "$html" ]]; then
      printf '%s' "$url"
      return 0
    fi
  done
  return 1
}

find_latest_release_page() {
  local version="$1"
  local codename="$2"
  local series_dir html latest

  series_dir="$(find_series_dir "$version" "$codename")" || return 1
  html="$(curl_get "$series_dir")" || return 1

  latest="$(printf '%s\n' "$html" \
    | grep -Eo 'release-[0-9]{8}(\.[0-9]+)?/' \
    | sed 's:/$::' \
    | sort -V \
    | tail -n1)"

  [[ -n "$latest" ]] || return 1
  printf '%s%s/' "$series_dir" "$latest"
}

find_artifact_name() {
  local release_html="$1"
  local version="$2"
  local pattern name
  for pattern in $IMAGE_PATTERNS; do
    name="${pattern//\{version\}/$version}"
    name="${name//\{arch\}/$ARCH}"
    if grep -q "$name" <<<"$release_html"; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

sha_from_sums() {
  local sums_content="$1"
  local artifact_name="$2"
  awk -v f="$artifact_name" '$2 == f || $2 == "*"f {print $1; exit}' <<<"$sums_content"
}

write_manifest() {
  local manifest_file="$1"
  local version="$2"
  local codename="$3"
  local status="$4"
  local artifact_name="$5"
  local sha256="$6"
  local release_page="$7"
  local artifact_url="$8"
  local local_path="$9"
  local note="${10:-}"

  cat > "$manifest_file" <<JSON
{
  "run_ts": "$(escape_json "$RUN_TS")",
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
  local url="$1"
  local dest="$2"
  local expected_sha="$3"
  local tmp_file got_sha

  tmp_file="$(mktemp "$TMP_DIR/download.XXXXXX")"
  curl_download "$url" "$tmp_file"

  if [[ "$VERIFY_SHA256" == "1" ]]; then
    got_sha="$(sha256sum "$tmp_file" | awk '{print $1}')"
    [[ "$got_sha" == "$expected_sha" ]] || die "sha256 mismatch for $url expected=$expected_sha got=$got_sha"
  fi

  mv -f "$tmp_file" "$dest"
}

: > "$LOG_FILE"
printf 'version\tcodename\tstatus\tartifact_name\tsha256\tlocal_path\trelease_page\tartifact_url\n' > "$SUMMARY_FILE"

downloaded_count=0
cached_count=0

log "starting Ubuntu official image auto-discover download"
log "REPO_ROOT=$REPO_ROOT"
log "PIPELINE_ROOT=$PIPELINE_ROOT"
log "CONFIG_FILE=$CONFIG_FILE"
log "MIN_VERSION=$MIN_VERSION LTS_ONLY=$LTS_ONLY ARCH=$ARCH EXCLUDE_END_OF_REGULAR_SUPPORT=$EXCLUDE_END_OF_REGULAR_SUPPORT"

mapfile -t SERIES_LIST < <(build_series_list)
[[ ${#SERIES_LIST[@]} -gt 0 ]] || die "no Ubuntu series discovered"

log "series selected: ${SERIES_LIST[*]}"

for pair in "${SERIES_LIST[@]}"; do
  version="${pair%%:*}"
  codename="${pair##*:}"

  log "processing version=$version codename=$codename"

  release_page="$(find_latest_release_page "$version" "$codename" || true)"
  [[ -n "$release_page" ]] || die "cannot resolve release page for version=$version codename=$codename"

  release_html="$(curl_get "$release_page" || true)"
  [[ -n "$release_html" ]] || die "cannot fetch release page: $release_page"

  if [[ "$LTS_ONLY" == "1" ]]; then
    if ! grep -Eq 'LTS|Long Term Support' <<<"$release_html"; then
      log "skip non-LTS series: $version"
      continue
    fi
  fi

  if [[ "$EXCLUDE_END_OF_REGULAR_SUPPORT" == "1" ]]; then
    if grep -q 'END OF REGULAR SUPPORT' <<<"$release_html"; then
      log "skip end-of-regular-support series: $version"
      continue
    fi
  fi

  artifact_name="$(find_artifact_name "$release_html" "$version" || true)"
  [[ -n "$artifact_name" ]] || die "artifact not found on release page for version=$version"

  sums_url="${release_page}SHA256SUMS"
  sums_content="$(curl_get "$sums_url" || true)"
  [[ -n "$sums_content" ]] || die "cannot fetch SHA256SUMS: $sums_url"

  expected_sha="$(sha_from_sums "$sums_content" "$artifact_name" || true)"
  [[ -n "$expected_sha" ]] || die "sha256 entry not found for $artifact_name"

  version_cache_dir="$CACHE_DIR/$version"
  mkdir -p "$version_cache_dir"
  local_path="$version_cache_dir/$artifact_name"
  artifact_url="${release_page}${artifact_name}"
  manifest_file="$MANIFEST_DIR/ubuntu-${version}.json"

  status="downloaded"
  note=""

  if [[ -f "$local_path" ]]; then
    if [[ "$VERIFY_SHA256" == "1" ]]; then
      got_sha="$(sha256sum "$local_path" | awk '{print $1}')"
      if [[ "$got_sha" == "$expected_sha" ]]; then
        status="cached"
        cached_count=$((cached_count + 1))
        note="cache hit with matching sha256"
      else
        log "cache sha mismatch, re-downloading version=$version file=$artifact_name"
        download_and_verify "$artifact_url" "$local_path" "$expected_sha"
        downloaded_count=$((downloaded_count + 1))
        note="cache replaced due to sha256 mismatch"
      fi
    else
      status="cached"
      cached_count=$((cached_count + 1))
      note="cache hit without verification"
    fi
  else
    download_and_verify "$artifact_url" "$local_path" "$expected_sha"
    downloaded_count=$((downloaded_count + 1))
    note="downloaded fresh"
  fi

  write_manifest "$manifest_file" "$version" "$codename" "$status" "$artifact_name" "$expected_sha" "$release_page" "$artifact_url" "$local_path" "$note"
  imagectl_sync_file_to_legacy "$manifest_file" "$LEGACY_UBUNTU_MANIFEST_DIR/ubuntu-${version}.json"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$version" "$codename" "$status" "$artifact_name" "$expected_sha" "$local_path" "$release_page" "$artifact_url" \
    >> "$SUMMARY_FILE"

  log "done version=$version status=$status file=$artifact_name"
done

imagectl_sync_file_to_legacy "$SUMMARY_FILE" "$LEGACY_SUMMARY_FILE"

log "summary downloaded_count=$downloaded_count cached_count=$cached_count"
log "summary file: $SUMMARY_FILE"
log "done"
