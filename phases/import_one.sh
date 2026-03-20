#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/layout.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/local_overrides.sh"
imagectl_init_layout "$REPO_ROOT"
imagectl_ensure_layout_dirs

OPENSTACK_ENV_FILE="${OPENSTACK_ENV_FILE:-$REPO_ROOT/config/runtime/openstack.env}"
OPENRC_PATH_FILE="${OPENRC_PATH_FILE:-$REPO_ROOT/config/runtime/openrc.path}"

[[ -f "$OPENSTACK_ENV_FILE" ]] || { echo "missing config: $OPENSTACK_ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$OPENSTACK_ENV_FILE"
imagectl_source_local_overrides "$REPO_ROOT"
imagectl_init_layout "$REPO_ROOT"

[[ -f "$OPENRC_PATH_FILE" ]] || { echo "missing config: $OPENRC_PATH_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$OPENRC_PATH_FILE"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <ubuntu-version>" >&2
  echo "example: $0 24.04" >&2
  exit 1
fi

PIPELINE_ROOT="${PIPELINE_ROOT:-}"
if [[ -z "$PIPELINE_ROOT" ]]; then
  PIPELINE_ROOT="$REPO_ROOT"
fi

SUMMARY_FILE="$(imagectl_resolve_summary_for_read)"
UBUNTU_MANIFEST_DIR="${UBUNTU_MANIFEST_DIR:-$PIPELINE_ROOT/manifests/ubuntu}"
OPENSTACK_MANIFEST_DIR="${OPENSTACK_MANIFEST_DIR:-$PIPELINE_ROOT/manifests/openstack}"
LEGACY_OPENSTACK_MANIFEST_DIR="${LEGACY_OPENSTACK_MANIFEST_DIR:-$PIPELINE_ROOT/manifest/openstack}"
STATE_DIR="${STATE_DIR:-$PIPELINE_ROOT/runtime/state}"
LOG_DIR="${LOG_DIR:-$PIPELINE_ROOT/logs}"

DEFAULT_BASE_IMAGE_NAME_TEMPLATE="ubuntu-{version}-base-official"
BASE_IMAGE_NAME_TEMPLATE="${BASE_IMAGE_NAME_TEMPLATE:-$DEFAULT_BASE_IMAGE_NAME_TEMPLATE}"
IMAGE_VISIBILITY="${IMAGE_VISIBILITY:-private}"
IMAGE_TAGS="${IMAGE_TAGS:-source:official,stage:base,os:ubuntu}"
SET_OS_DISTRO_PROPERTY="${SET_OS_DISTRO_PROPERTY:-yes}"
SET_OS_VERSION_PROPERTY="${SET_OS_VERSION_PROPERTY:-yes}"
ON_EXISTS="${ON_EXISTS:-error}"
WAIT_FOR_ACTIVE="${WAIT_FOR_ACTIVE:-yes}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-1800}"
WAIT_INTERVAL_SECONDS="${WAIT_INTERVAL_SECONDS:-10}"

mkdir -p "$OPENSTACK_MANIFEST_DIR" "$STATE_DIR" "$LOG_DIR"

LOG_FILE="$LOG_DIR/02_glance_import_one.log"

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

need_cmd awk
need_cmd grep
need_cmd sed
need_cmd qemu-img
need_cmd openstack
need_cmd head

[[ -n "${OPENRC_FILE:-}" ]] || die "OPENRC_FILE is empty in $OPENRC_PATH_FILE"
[[ -f "$OPENRC_FILE" ]] || die "openrc file not found: $OPENRC_FILE"

# shellcheck disable=SC1090
source "$OPENRC_FILE"
openstack token issue >/dev/null

[[ -f "$SUMMARY_FILE" ]] || die "summary file not found: $SUMMARY_FILE"

if [[ "$BASE_IMAGE_NAME_TEMPLATE" != *"{version}"* ]]; then
  log "WARN: BASE_IMAGE_NAME_TEMPLATE malformed: '$BASE_IMAGE_NAME_TEMPLATE' -> using default '$DEFAULT_BASE_IMAGE_NAME_TEMPLATE'"
  BASE_IMAGE_NAME_TEMPLATE="$DEFAULT_BASE_IMAGE_NAME_TEMPLATE"
fi

row="$(awk -F '\t' -v ver="$VERSION" 'NR>1 && $1==ver {print; exit}' "$SUMMARY_FILE")"
[[ -n "$row" ]] || die "version $VERSION not found in summary file: $SUMMARY_FILE"

codename="$(awk -F '\t' -v ver="$VERSION" 'NR>1 && $1==ver {print $2; exit}' "$SUMMARY_FILE")"
artifact_name="$(awk -F '\t' -v ver="$VERSION" 'NR>1 && $1==ver {print $4; exit}' "$SUMMARY_FILE")"
expected_sha="$(awk -F '\t' -v ver="$VERSION" 'NR>1 && $1==ver {print $5; exit}' "$SUMMARY_FILE")"
local_path="$(awk -F '\t' -v ver="$VERSION" 'NR>1 && $1==ver {print $6; exit}' "$SUMMARY_FILE")"
release_page="$(awk -F '\t' -v ver="$VERSION" 'NR>1 && $1==ver {print $7; exit}' "$SUMMARY_FILE")"
artifact_url="$(awk -F '\t' -v ver="$VERSION" 'NR>1 && $1==ver {print $8; exit}' "$SUMMARY_FILE")"

[[ -n "$local_path" ]] || die "local_path missing for version $VERSION"
[[ -f "$local_path" ]] || die "image file not found: $local_path"

detected_format="$(qemu-img info "$local_path" | awk -F': ' '/file format/ {print $2; exit}')"
[[ -n "$detected_format" ]] || die "cannot detect disk format from qemu-img info: $local_path"

case "$detected_format" in
  qcow2|raw) ;;
  *)
    die "unsupported disk format: $detected_format for $local_path"
    ;;
esac

image_name="${BASE_IMAGE_NAME_TEMPLATE//\{version\}/$VERSION}"

existing_id="$(openstack image list --name "$image_name" -f value -c ID | head -n1 || true)"
if [[ -n "$existing_id" ]]; then
  case "$ON_EXISTS" in
    error)
      die "image already exists: $image_name id=$existing_id"
      ;;
    skip)
      log "image already exists, skip: $image_name id=$existing_id"
      image_id="$existing_id"
      image_status="$(openstack image show "$image_id" -f value -c status)"
      ;;
    replace)
      log "image already exists, deleting: $image_name id=$existing_id"
      openstack image delete "$existing_id"
      ;;
    *)
      die "invalid ON_EXISTS value: $ON_EXISTS"
      ;;
  esac
fi

if [[ -z "${image_id:-}" ]]; then
  create_args=(image create "$image_name" --file "$local_path" --disk-format "$detected_format" --container-format bare)

  case "$IMAGE_VISIBILITY" in
    private) create_args+=(--private) ;;
    public) create_args+=(--public) ;;
    community) create_args+=(--community) ;;
    shared) create_args+=(--shared) ;;
    *) die "invalid IMAGE_VISIBILITY=$IMAGE_VISIBILITY" ;;
  esac

  if [[ "$SET_OS_DISTRO_PROPERTY" == "yes" ]]; then
    create_args+=(--property os_distro=ubuntu)
  fi
  if [[ "$SET_OS_VERSION_PROPERTY" == "yes" ]]; then
    create_args+=(--property os_version="$VERSION")
  fi
  create_args+=(--property source_release_page="$release_page")
  create_args+=(--property source_artifact_url="$artifact_url")
  create_args+=(--property source_sha256="$expected_sha")

  log "creating image name=$image_name format=$detected_format local_path=$local_path visibility=$IMAGE_VISIBILITY"
  image_id="$(openstack "${create_args[@]}" -f value -c id)"
  [[ -n "$image_id" ]] || die "failed to get image_id after create: $image_name"

  IFS=',' read -r -a tags_array <<< "$IMAGE_TAGS"
  for tag in "${tags_array[@]}"; do
    tag="$(printf '%s' "$tag" | xargs)"
    [[ -n "$tag" ]] || continue
    openstack image set --tag "$tag" "$image_id"
  done

  if [[ "$WAIT_FOR_ACTIVE" == "yes" ]]; then
    log "waiting for image to become active id=$image_id"
    start_ts="$(date +%s)"
    while true; do
      image_status="$(openstack image show "$image_id" -f value -c status)"
      if [[ "$image_status" == "active" ]]; then
        break
      fi
      if [[ "$image_status" == "killed" || "$image_status" == "deleted" || "$image_status" == "deactivated" ]]; then
        die "image entered bad status: $image_status id=$image_id"
      fi
      now_ts="$(date +%s)"
      if (( now_ts - start_ts > WAIT_TIMEOUT_SECONDS )); then
        die "timeout waiting for image active id=$image_id last_status=$image_status"
      fi
      sleep "$WAIT_INTERVAL_SECONDS"
    done
  else
    image_status="$(openstack image show "$image_id" -f value -c status)"
  fi
fi

manifest_file="$OPENSTACK_MANIFEST_DIR/base-image-${VERSION}.env"
cat > "$manifest_file" <<EOF
VERSION=$VERSION
CODENAME=$codename
ARTIFACT_NAME=$artifact_name
EXPECTED_SHA256=$expected_sha
LOCAL_PATH=$local_path
DISK_FORMAT=$detected_format
BASE_IMAGE_NAME=$image_name
BASE_IMAGE_ID=$image_id
IMAGE_STATUS=$image_status
IMAGE_VISIBILITY=$IMAGE_VISIBILITY
RELEASE_PAGE=$release_page
ARTIFACT_URL=$artifact_url
EOF

state_file="$STATE_DIR/current.base-image-${VERSION}.env"
cp -f "$manifest_file" "$state_file"
cp -f "$manifest_file" "$STATE_DIR/current.base-image.env"
imagectl_sync_file_to_legacy "$manifest_file" "$LEGACY_OPENSTACK_MANIFEST_DIR/base-image-${VERSION}.env"

log "done version=$VERSION image_name=$image_name image_id=$image_id status=$image_status"
log "manifest_file=$manifest_file"
