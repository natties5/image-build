#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${STATE_DIR:-$REPO_ROOT/runtime/state}"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"
MANIFEST_DIR="${MANIFEST_DIR:-$REPO_ROOT/manifest/openstack}"
OPENRC_PATH_FILE="${OPENRC_PATH_FILE:-$REPO_ROOT/config/openrc.path}"
PUBLISH_CONFIG_FILE="${PUBLISH_CONFIG_FILE:-$REPO_ROOT/config/publish.env}"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$MANIFEST_DIR"

resolve_input_arg() {
  local arg="${1:-}"
  if [[ -n "$arg" && -f "$arg" ]]; then printf '%s' "$arg"; return 0; fi
  if [[ -n "$arg" && -f "$STATE_DIR/current.configure-${arg}.env" ]]; then printf '%s' "$STATE_DIR/current.configure-${arg}.env"; return 0; fi
  if [[ -n "$arg" && -f "$STATE_DIR/${arg}.configure.env" ]]; then printf '%s' "$STATE_DIR/${arg}.configure.env"; return 0; fi
  if [[ -f "$STATE_DIR/current.configure.env" ]]; then printf '%s' "$STATE_DIR/current.configure.env"; return 0; fi
  printf ''
}

CONFIG_ARG_RAW="${1:-}"
CONFIG_FILE="$(resolve_input_arg "$CONFIG_ARG_RAW")"
[[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]] || { echo "usage: $0 <ubuntu-version | path-to-.configure.env>" >&2; exit 1; }

[[ -f "$OPENRC_PATH_FILE" ]] || { echo "missing config: $OPENRC_PATH_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$OPENRC_PATH_FILE"
[[ -n "${OPENRC_FILE:-}" && -f "$OPENRC_FILE" ]] || { echo "OPENRC_FILE invalid" >&2; exit 1; }
# shellcheck disable=SC1090
source "$OPENRC_FILE"

if [[ -f "$PUBLISH_CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PUBLISH_CONFIG_FILE"
fi

PIPELINE_ROOT="${PIPELINE_ROOT:-$REPO_ROOT}"
FINAL_IMAGE_NAME_TEMPLATE="${FINAL_IMAGE_NAME_TEMPLATE:-ubuntu-{version}-complete-{date}}"
FINAL_IMAGE_VISIBILITY="${FINAL_IMAGE_VISIBILITY:-private}"
FINAL_IMAGE_TAGS="${FINAL_IMAGE_TAGS:-stage:complete,os:ubuntu}"
ON_FINAL_EXISTS="${ON_FINAL_EXISTS:-error}"
WAIT_FOR_FINAL_ACTIVE="${WAIT_FOR_FINAL_ACTIVE:-yes}"
WAIT_FINAL_TIMEOUT_SECONDS="${WAIT_FINAL_TIMEOUT_SECONDS:-3600}"
WAIT_FINAL_INTERVAL_SECONDS="${WAIT_FINAL_INTERVAL_SECONDS:-10}"
DELETE_SERVER_BEFORE_PUBLISH="${DELETE_SERVER_BEFORE_PUBLISH:-yes}"
DELETE_VOLUME_AFTER_PUBLISH="${DELETE_VOLUME_AFTER_PUBLISH:-yes}"
DELETE_BASE_IMAGE_AFTER_PUBLISH="${DELETE_BASE_IMAGE_AFTER_PUBLISH:-yes}"
SET_OS_DISTRO_PROPERTY="${SET_OS_DISTRO_PROPERTY:-yes}"
SET_OS_VERSION_PROPERTY="${SET_OS_VERSION_PROPERTY:-yes}"

RUN_ID="$(date +%Y%m%d%H%M%S)"
TODAY_YYYYMMDD="$(date +%Y%m%d)"
LOCAL_LOG="$LOG_DIR/10_publish_image_one_${RUN_ID}.log"
: > "$LOCAL_LOG"

log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOCAL_LOG" ; }
die(){ log "ERROR: $*"; exit 1; }
trap 'die "line=$LINENO cmd=$BASH_COMMAND"' ERR

need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
for c in openstack awk grep sed head; do need_cmd "$c"; done

openstack token issue >/dev/null

# shellcheck disable=SC1090
source "$CONFIG_FILE"

VERSION="${VERSION:-unknown}"
SERVER_ID="${SERVER_ID:-}"
VOLUME_ID="${VOLUME_ID:-}"
BASE_IMAGE_ID="${IMAGE_ID:-}"
VM_NAME="${VM_NAME:-}"
[[ -n "$SERVER_ID" && -n "$VOLUME_ID" && -n "$BASE_IMAGE_ID" ]] || die "SERVER_ID/VOLUME_ID/IMAGE_ID missing in $CONFIG_FILE"

server_exists() { openstack server show "$SERVER_ID" >/dev/null 2>&1; }
server_status() { openstack server show "$SERVER_ID" -f value -c status 2>/dev/null || true; }
volume_status() { openstack volume show "$VOLUME_ID" -f value -c status 2>/dev/null || true; }
image_status() { openstack image show "$1" -f value -c status 2>/dev/null || true; }

wait_for_volume_status() {
  local desired="$1" timeout_sec="$2" interval_sec="$3" st start now
  start="$(date +%s)"
  while true; do
    st="$(volume_status)"
    [[ "$st" == "$desired" ]] && return 0
    [[ "$st" == "error" || "$st" == "error_restoring" || "$st" == "error_extending" || "$st" == "error_managing" ]] && die "volume entered bad status=$st"
    now="$(date +%s)"
    (( now - start >= timeout_sec )) && die "timeout waiting for volume status=$desired last_status=${st:-unknown}"
    sleep "$interval_sec"
  done
}

wait_for_image_status() {
  local image_id="$1" desired="$2" timeout_sec="$3" interval_sec="$4" st start now
  start="$(date +%s)"
  while true; do
    st="$(image_status "$image_id")"
    [[ "$st" == "$desired" ]] && return 0
    [[ "$st" == "killed" || "$st" == "deleted" || "$st" == "deactivated" ]] && die "image entered bad status=$st id=$image_id"
    now="$(date +%s)"
    (( now - start >= timeout_sec )) && die "timeout waiting for image id=$image_id status=$desired last_status=${st:-unknown}"
    sleep "$interval_sec"
  done
}

final_image_name="${FINAL_IMAGE_NAME_TEMPLATE//\{version\}/$VERSION}"
final_image_name="${final_image_name//\{date\}/$TODAY_YYYYMMDD}"

existing_final_id="$(openstack image list --name "$final_image_name" -f value -c ID | head -n1 || true)"
if [[ -n "$existing_final_id" ]]; then
  case "$ON_FINAL_EXISTS" in
    error) die "final image already exists: $final_image_name id=$existing_final_id" ;;
    skip)
      log "final image already exists, skip create: $final_image_name id=$existing_final_id"
      final_image_id="$existing_final_id"
      ;;
    replace)
      log "deleting existing final image first: $final_image_name id=$existing_final_id"
      openstack image delete "$existing_final_id"
      ;;
    *) die "invalid ON_FINAL_EXISTS=$ON_FINAL_EXISTS" ;;
  esac
fi

if [[ -z "${final_image_id:-}" ]]; then
  if [[ "$DELETE_SERVER_BEFORE_PUBLISH" == "yes" ]]; then
    if server_exists; then
      pre_server_status="$(server_status)"
      log "deleting server before publish id=$SERVER_ID status=$pre_server_status"
      openstack server delete "$SERVER_ID"
      log "waiting for boot volume to become available"
      wait_for_volume_status "available" 600 5
    else
      log "server already absent id=$SERVER_ID"
      log "waiting for boot volume to become available"
      wait_for_volume_status "available" 600 5
    fi
  else
    pre_server_status="$(server_status)"
    log "server status before publish=$pre_server_status"
    [[ "$pre_server_status" == "SHUTOFF" ]] || die "server must be SHUTOFF before publish when DELETE_SERVER_BEFORE_PUBLISH=no"
  fi

  log "creating final image from volume_id=$VOLUME_ID name=$final_image_name"
  final_image_id="$(openstack image create "$final_image_name" --volume "$VOLUME_ID" -f value -c id)"
  [[ -n "$final_image_id" ]] || die "failed to create final image"
fi

if [[ "$WAIT_FOR_FINAL_ACTIVE" == "yes" ]]; then
  log "waiting for final image to become active id=$final_image_id"
  wait_for_image_status "$final_image_id" active "$WAIT_FINAL_TIMEOUT_SECONDS" "$WAIT_FINAL_INTERVAL_SECONDS"
fi

final_image_status="$(image_status "$final_image_id")"
[[ "$final_image_status" == "active" ]] || die "final image not active: id=$final_image_id status=$final_image_status"

# apply metadata after image becomes active
if [[ "$SET_OS_DISTRO_PROPERTY" == "yes" ]]; then
  openstack image set --property os_distro=ubuntu "$final_image_id"
fi
if [[ "$SET_OS_VERSION_PROPERTY" == "yes" ]]; then
  openstack image set --property os_version="$VERSION" "$final_image_id"
fi
openstack image set --property pipeline_stage=complete "$final_image_id"
openstack image set --property source_server_id="$SERVER_ID" "$final_image_id"
openstack image set --property source_volume_id="$VOLUME_ID" "$final_image_id"
openstack image set --property source_base_image_id="$BASE_IMAGE_ID" "$final_image_id"

IFS=',' read -r -a tags_array <<< "$FINAL_IMAGE_TAGS"
for tag in "${tags_array[@]}"; do
  tag="$(printf '%s' "$tag" | xargs)"
  [[ -n "$tag" ]] || continue
  openstack image set --tag "$tag" "$final_image_id"
done

case "$FINAL_IMAGE_VISIBILITY" in
  private) openstack image set --private "$final_image_id" || true ;;
  public) openstack image set --public "$final_image_id" || true ;;
  community) openstack image set --community "$final_image_id" || true ;;
  shared) openstack image set --shared "$final_image_id" || true ;;
  *) die "invalid FINAL_IMAGE_VISIBILITY=$FINAL_IMAGE_VISIBILITY" ;;
esac

manifest_file="$MANIFEST_DIR/final-image-${VERSION}.env"
cat > "$manifest_file" <<EOF
VERSION=$VERSION
FINAL_IMAGE_NAME=$final_image_name
FINAL_IMAGE_ID=$final_image_id
FINAL_IMAGE_STATUS=$final_image_status
SOURCE_SERVER_ID=$SERVER_ID
SOURCE_VOLUME_ID=$VOLUME_ID
SOURCE_BASE_IMAGE_ID=$BASE_IMAGE_ID
DELETE_SERVER_BEFORE_PUBLISH=$DELETE_SERVER_BEFORE_PUBLISH
DELETE_VOLUME_AFTER_PUBLISH=$DELETE_VOLUME_AFTER_PUBLISH
DELETE_BASE_IMAGE_AFTER_PUBLISH=$DELETE_BASE_IMAGE_AFTER_PUBLISH
PUBLISHED_AT=$RUN_ID
EOF

cp -f "$manifest_file" "$STATE_DIR/current.final-image-${VERSION}.env"
cp -f "$manifest_file" "$STATE_DIR/current.final-image.env"

log "final image created successfully name=$final_image_name id=$final_image_id"

if [[ "$DELETE_VOLUME_AFTER_PUBLISH" == "yes" ]]; then
  log "deleting volume id=$VOLUME_ID"
  openstack volume delete "$VOLUME_ID"
fi

if [[ "$DELETE_BASE_IMAGE_AFTER_PUBLISH" == "yes" ]]; then
  log "deleting base image id=$BASE_IMAGE_ID"
  openstack image delete "$BASE_IMAGE_ID"
fi

summary_file="$LOG_DIR/10_publish_image_one_${VERSION}_${RUN_ID}.summary.txt"
cat > "$summary_file" <<EOF
STATUS=SUCCESS
VERSION=$VERSION
FINAL_IMAGE_NAME=$final_image_name
FINAL_IMAGE_ID=$final_image_id
FINAL_IMAGE_STATUS=$final_image_status
SOURCE_SERVER_ID=$SERVER_ID
SOURCE_VOLUME_ID=$VOLUME_ID
SOURCE_BASE_IMAGE_ID=$BASE_IMAGE_ID
MANIFEST_FILE=$manifest_file
LOCAL_LOG=$LOCAL_LOG
EOF

log "DONE"
log "VERSION=$VERSION"
log "FINAL_IMAGE_NAME=$final_image_name"
log "FINAL_IMAGE_ID=$final_image_id"
log "MANIFEST_FILE=$manifest_file"
