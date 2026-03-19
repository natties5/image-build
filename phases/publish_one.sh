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
STATE_DIR="${STATE_DIR:-$REPO_ROOT/runtime/state}"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"
MANIFEST_DIR="${MANIFEST_DIR:-$REPO_ROOT/manifests/openstack}"
LEGACY_OPENSTACK_MANIFEST_DIR="${LEGACY_OPENSTACK_MANIFEST_DIR:-$REPO_ROOT/manifest/openstack}"
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

CONFIG_FILE="$(resolve_input_arg "${1:-}")"
[[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]] || { echo "usage: $0 <ubuntu-version | path-to-.configure.env>" >&2; exit 1; }

imagectl_source_local_overrides "$REPO_ROOT"
[[ -f "$OPENRC_PATH_FILE" ]] || { echo "missing config: $OPENRC_PATH_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$OPENRC_PATH_FILE"
[[ -n "${OPENRC_FILE:-}" && -f "$OPENRC_FILE" ]] || { echo "OPENRC_FILE invalid" >&2; exit 1; }
# shellcheck disable=SC1090
source "$OPENRC_FILE"

[[ -f "$PUBLISH_CONFIG_FILE" ]] && source "$PUBLISH_CONFIG_FILE"

FINAL_IMAGE_VISIBILITY="${FINAL_IMAGE_VISIBILITY:-private}"
FINAL_IMAGE_TAGS="${FINAL_IMAGE_TAGS:-stage:complete,os:ubuntu}"
ON_FINAL_EXISTS="${ON_FINAL_EXISTS:-recover}"
WAIT_FOR_FINAL_ACTIVE="${WAIT_FOR_FINAL_ACTIVE:-yes}"
WAIT_FINAL_TIMEOUT_SECONDS="${WAIT_FINAL_TIMEOUT_SECONDS:-3600}"
WAIT_FINAL_INTERVAL_SECONDS="${WAIT_FINAL_INTERVAL_SECONDS:-10}"
PUBLISH_REQUIRE_APPROVAL="${PUBLISH_REQUIRE_APPROVAL:-no}"
PUBLISH_APPROVED="${PUBLISH_APPROVED:-}"
DELETE_SERVER_BEFORE_PUBLISH="${DELETE_SERVER_BEFORE_PUBLISH:-yes}"
DELETE_VOLUME_AFTER_PUBLISH="${DELETE_VOLUME_AFTER_PUBLISH:-yes}"
DELETE_BASE_IMAGE_AFTER_PUBLISH="${DELETE_BASE_IMAGE_AFTER_PUBLISH:-yes}"
SET_OS_DISTRO_PROPERTY="${SET_OS_DISTRO_PROPERTY:-yes}"
SET_OS_VERSION_PROPERTY="${SET_OS_VERSION_PROPERTY:-yes}"
FINAL_DISK_FORMAT="${FINAL_DISK_FORMAT:-qcow2}"
FINAL_CONTAINER_FORMAT="${FINAL_CONTAINER_FORMAT:-bare}"
CINDER_UPLOAD_FORCE="${CINDER_UPLOAD_FORCE:-True}"

RUN_ID="$(date +%Y%m%d%H%M%S)"
TODAY_YYYYMMDD="$(date +%Y%m%d)"
LOCAL_LOG="$LOG_DIR/10_publish_image_one_${RUN_ID}.log"
: > "$LOCAL_LOG"

log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOCAL_LOG" ; }
trap 'printf "[%s] ERROR: line=%s cmd=%s\n" "$(date "+%F %T")" "$LINENO" "$BASH_COMMAND" | tee -a "$LOCAL_LOG"; exit 1' ERR

for c in openstack cinder awk grep sed head; do command -v "$c" >/dev/null 2>&1 || { echo "missing command: $c" >&2; exit 1; }; done
openstack token issue >/dev/null

# shellcheck disable=SC1090
source "$CONFIG_FILE"
VERSION="${VERSION:-unknown}"
SERVER_ID="${SERVER_ID:-}"
VOLUME_ID="${VOLUME_ID:-}"
BASE_IMAGE_ID="${IMAGE_ID:-}"
[[ -n "$SERVER_ID" && -n "$VOLUME_ID" && -n "$BASE_IMAGE_ID" ]] || { log "skip: missing SERVER_ID/VOLUME_ID/IMAGE_ID in $CONFIG_FILE"; exit 0; }

if [[ "$PUBLISH_REQUIRE_APPROVAL" == "yes" && "$PUBLISH_APPROVED" != "yes" ]]; then
  log "ERROR: publish requires approval. Set PUBLISH_APPROVED=yes to proceed."
  exit 1
fi

server_exists(){ openstack server show "$SERVER_ID" >/dev/null 2>&1; }
server_status(){ openstack server show "$SERVER_ID" -f value -c status 2>/dev/null || true; }
volume_exists(){ openstack volume show "$VOLUME_ID" >/dev/null 2>&1; }
volume_status(){ openstack volume show "$VOLUME_ID" -f value -c status 2>/dev/null || true; }
image_exists(){ openstack image show "$1" >/dev/null 2>&1; }
image_status(){ openstack image show "$1" -f value -c status 2>/dev/null || true; }
find_final_image_id_by_name(){ openstack image list --name "$1" -f value -c ID | head -n1 || true; }

wait_for_volume_status() {
  local desired="$1" timeout_sec="$2" interval_sec="$3" st start now
  start="$(date +%s)"
  while true; do
    if ! volume_exists; then log "skip: volume disappeared while waiting id=$VOLUME_ID"; return 1; fi
    st="$(volume_status)"
    [[ "$st" == "$desired" ]] && return 0
    [[ "$st" == error* ]] && { log "skip: volume bad status=$st id=$VOLUME_ID"; return 1; }
    now="$(date +%s)"
    (( now - start >= timeout_sec )) && { log "skip: timeout waiting for volume status=$desired last_status=${st:-unknown}"; return 1; }
    sleep "$interval_sec"
  done
}

wait_for_image_status() {
  local image_id="$1" desired="$2" timeout_sec="$3" interval_sec="$4" st start now
  start="$(date +%s)"
  while true; do
    st="$(image_status "$image_id")"
    [[ "$st" == "$desired" ]] && return 0
    if [[ "$st" == "killed" || "$st" == "deleted" || "$st" == "deactivated" ]]; then
      log "skip: image bad status=$st id=$image_id"
      return 1
    fi
    now="$(date +%s)"
    (( now - start >= timeout_sec )) && { log "skip: timeout waiting for image id=$image_id status=$desired last_status=${st:-unknown}"; return 1; }
    sleep "$interval_sec"
  done
}

safe_set_visibility() {
  local image_id="$1"
  case "$FINAL_IMAGE_VISIBILITY" in
    private) openstack image set --private "$image_id" || true ;;
    public) openstack image set --public "$image_id" || true ;;
    community) openstack image set --community "$image_id" || true ;;
    shared) openstack image set --shared "$image_id" || true ;;
  esac
}

apply_metadata() {
  local image_id="$1"
  [[ "$SET_OS_DISTRO_PROPERTY" == "yes" ]] && openstack image set --property os_distro=ubuntu "$image_id" || true
  [[ "$SET_OS_VERSION_PROPERTY" == "yes" ]] && openstack image set --property os_version="$VERSION" "$image_id" || true
  openstack image set --property pipeline_stage=complete "$image_id" || true
  openstack image set --property source_server_id="$SERVER_ID" "$image_id" || true
  openstack image set --property source_volume_id="$VOLUME_ID" "$image_id" || true
  openstack image set --property source_base_image_id="$BASE_IMAGE_ID" "$image_id" || true
  IFS=',' read -r -a tags_array <<< "$FINAL_IMAGE_TAGS"
  for tag in "${tags_array[@]}"; do
    tag="$(printf '%s' "$tag" | xargs)"
    [[ -n "$tag" ]] && openstack image set --tag "$tag" "$image_id" || true
  done
  safe_set_visibility "$image_id"
}

write_manifest() {
  local image_id="$1" image_name="$2" image_status_now="$3" mode="$4"
  local manifest_file="$MANIFEST_DIR/final-image-${VERSION}.env"
  cat > "$manifest_file" <<EOF
VERSION=$VERSION
FINAL_IMAGE_NAME=$image_name
FINAL_IMAGE_ID=$image_id
FINAL_IMAGE_STATUS=$image_status_now
FINAL_DISK_FORMAT=$FINAL_DISK_FORMAT
FINAL_CONTAINER_FORMAT=$FINAL_CONTAINER_FORMAT
SOURCE_SERVER_ID=$SERVER_ID
SOURCE_VOLUME_ID=$VOLUME_ID
SOURCE_BASE_IMAGE_ID=$BASE_IMAGE_ID
PUBLISH_MODE=$mode
PUBLISHED_AT=$RUN_ID
EOF
  cp -f "$manifest_file" "$STATE_DIR/current.final-image-${VERSION}.env"
  cp -f "$manifest_file" "$STATE_DIR/current.final-image.env"
  imagectl_sync_file_to_legacy "$manifest_file" "$LEGACY_OPENSTACK_MANIFEST_DIR/final-image-${VERSION}.env"
  printf '%s' "$manifest_file"
}

cleanup_sources() {
  if [[ "$DELETE_VOLUME_AFTER_PUBLISH" == "yes" ]] && volume_exists; then
    log "deleting volume id=$VOLUME_ID"
    openstack volume delete "$VOLUME_ID" || true
  fi
  if [[ "$DELETE_BASE_IMAGE_AFTER_PUBLISH" == "yes" ]] && image_exists "$BASE_IMAGE_ID"; then
    log "deleting base image id=$BASE_IMAGE_ID"
    openstack image delete "$BASE_IMAGE_ID" || true
  fi
}

final_image_name="ubuntu-${VERSION}-complete-${TODAY_YYYYMMDD}"
final_image_id_existing="$(find_final_image_id_by_name "$final_image_name")"
server_present=no; volume_present=no; base_present=no
server_exists && server_present=yes
volume_exists && volume_present=yes
image_exists "$BASE_IMAGE_ID" && base_present=yes
log "source state: final_image=${final_image_id_existing:-none} server=$server_present volume=$volume_present base=$base_present"

if [[ -n "$final_image_id_existing" ]]; then
  final_status_existing="$(image_status "$final_image_id_existing")"
  if [[ "$ON_FINAL_EXISTS" == "recover" && "$final_status_existing" == "active" ]]; then
    log "final image already exists and is active -> recover success: $final_image_name id=$final_image_id_existing"
    apply_metadata "$final_image_id_existing"
    manifest_file="$(write_manifest "$final_image_id_existing" "$final_image_name" "$final_status_existing" "recover")"
    cleanup_sources
    log "DONE"; log "VERSION=$VERSION"; log "FINAL_IMAGE_NAME=$final_image_name"; log "FINAL_IMAGE_ID=$final_image_id_existing"; log "MANIFEST_FILE=$manifest_file"
    exit 0
  fi
  if [[ "$ON_FINAL_EXISTS" == "recover" && ( "$final_status_existing" == "queued" || "$final_status_existing" == "saving" || "$final_status_existing" == "importing" ) ]]; then
    log "final image already exists and is still progressing -> waiting id=$final_image_id_existing status=$final_status_existing"
    if wait_for_image_status "$final_image_id_existing" active "$WAIT_FINAL_TIMEOUT_SECONDS" "$WAIT_FINAL_INTERVAL_SECONDS"; then
      final_status_existing="$(image_status "$final_image_id_existing")"
      apply_metadata "$final_image_id_existing"
      manifest_file="$(write_manifest "$final_image_id_existing" "$final_image_name" "$final_status_existing" "recover-wait")"
      cleanup_sources
      log "DONE"; log "VERSION=$VERSION"; log "FINAL_IMAGE_NAME=$final_image_name"; log "FINAL_IMAGE_ID=$final_image_id_existing"; log "MANIFEST_FILE=$manifest_file"
      exit 0
    fi
    log "skip: existing final image did not become active for version $VERSION"
    exit 0
  fi
  if [[ "$ON_FINAL_EXISTS" == "replace" ]]; then
    log "deleting existing final image first: $final_image_name id=$final_image_id_existing"
    openstack image delete "$final_image_id_existing" || true
  else
    log "skip: final image exists in status=$final_status_existing name=$final_image_name"
    exit 0
  fi
fi

if [[ "$server_present" == no && "$volume_present" == no ]]; then
  log "skip: no publish source left for version $VERSION (server missing, volume missing, final image missing)"
  exit 0
fi

if [[ "$server_present" == yes && "$DELETE_SERVER_BEFORE_PUBLISH" == yes ]]; then
  pre_server_status="$(server_status)"
  log "deleting server before publish id=$SERVER_ID status=$pre_server_status"
  openstack server delete "$SERVER_ID" || true
  log "waiting for boot volume to become available"
  wait_for_volume_status available 600 5 || { log "skip: volume not ready after server delete for version $VERSION"; exit 0; }
elif [[ "$server_present" == no && "$volume_present" == yes ]]; then
  log "server already absent, volume still present -> continue publish from volume"
  wait_for_volume_status available 600 5 || { log "skip: volume not available for version $VERSION"; exit 0; }
elif [[ "$server_present" == yes && "$DELETE_SERVER_BEFORE_PUBLISH" != yes ]]; then
  pre_server_status="$(server_status)"
  log "server status before publish=$pre_server_status"
  [[ "$pre_server_status" == SHUTOFF ]] || { log "skip: server not SHUTOFF for version $VERSION"; exit 0; }
fi

if ! volume_exists; then
  log "skip: volume missing before cinder upload-to-image for version $VERSION"
  exit 0
fi

log "uploading volume to image via cinder as $FINAL_DISK_FORMAT from volume_id=$VOLUME_ID name=$final_image_name"
upload_output="$(cinder upload-to-image --disk-format "$FINAL_DISK_FORMAT" --container-format "$FINAL_CONTAINER_FORMAT" --force "$CINDER_UPLOAD_FORCE" "$VOLUME_ID" "$final_image_name" 2>&1)" || {
  log "skip: cinder upload-to-image failed for version $VERSION"
  printf '%s\n' "$upload_output" | tee -a "$LOCAL_LOG"
  exit 0
}
printf '%s\n' "$upload_output" | tee -a "$LOCAL_LOG"

final_image_id="$(awk -F'|' '/image_id/ {gsub(/ /,"",$3); print $3}' <<<"$upload_output" | head -n1 || true)"
if [[ -z "$final_image_id" ]]; then
  start_ts="$(date +%s)"
  while true; do
    final_image_id="$(find_final_image_id_by_name "$final_image_name")"
    [[ -n "$final_image_id" ]] && break
    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= 600 )); then
      log "skip: timeout waiting for image id by final name=$final_image_name"
      exit 0
    fi
    sleep 5
  done
fi

if [[ "$WAIT_FOR_FINAL_ACTIVE" == "yes" ]]; then
  log "waiting for final image to become active id=$final_image_id"
  wait_for_image_status "$final_image_id" active "$WAIT_FINAL_TIMEOUT_SECONDS" "$WAIT_FINAL_INTERVAL_SECONDS" || { log "skip: final image did not become active for version $VERSION"; exit 0; }
fi

final_image_status="$(image_status "$final_image_id")"
if [[ "$final_image_status" != active ]]; then
  log "skip: final image not active for version $VERSION id=$final_image_id status=$final_image_status"
  exit 0
fi

apply_metadata "$final_image_id"
manifest_file="$(write_manifest "$final_image_id" "$final_image_name" "$final_image_status" "publish")"
cleanup_sources
log "DONE"; log "VERSION=$VERSION"; log "FINAL_IMAGE_NAME=$final_image_name"; log "FINAL_IMAGE_ID=$final_image_id"; log "MANIFEST_FILE=$manifest_file"
