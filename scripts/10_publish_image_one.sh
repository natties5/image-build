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

CONFIG_FILE="$(resolve_input_arg "${1:-}")"
[[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]] || { echo "usage: $0 <ubuntu-version | path-to-.configure.env>" >&2; exit 1; }

source "$OPENRC_PATH_FILE"
source "$OPENRC_FILE"
[[ -f "$PUBLISH_CONFIG_FILE" ]] && source "$PUBLISH_CONFIG_FILE"

FINAL_IMAGE_VISIBILITY="${FINAL_IMAGE_VISIBILITY:-private}"
FINAL_IMAGE_TAGS="${FINAL_IMAGE_TAGS:-stage:complete,os:ubuntu}"
ON_FINAL_EXISTS="${ON_FINAL_EXISTS:-recover}"
WAIT_FOR_FINAL_ACTIVE="${WAIT_FOR_FINAL_ACTIVE:-yes}"
WAIT_FINAL_TIMEOUT_SECONDS="${WAIT_FINAL_TIMEOUT_SECONDS:-3600}"
WAIT_FINAL_INTERVAL_SECONDS="${WAIT_FINAL_INTERVAL_SECONDS:-10}"
DELETE_SERVER_BEFORE_PUBLISH="${DELETE_SERVER_BEFORE_PUBLISH:-yes}"
DELETE_VOLUME_AFTER_PUBLISH="${DELETE_VOLUME_AFTER_PUBLISH:-yes}"
DELETE_BASE_IMAGE_AFTER_PUBLISH="${DELETE_BASE_IMAGE_AFTER_PUBLISH:-yes}"
SET_OS_DISTRO_PROPERTY="${SET_OS_DISTRO_PROPERTY:-yes}"
SET_OS_VERSION_PROPERTY="${SET_OS_VERSION_PROPERTY:-yes}"
FINAL_DISK_FORMAT="${FINAL_DISK_FORMAT:-qcow2}"
FINAL_CONTAINER_FORMAT="${FINAL_CONTAINER_FORMAT:-bare}"

RUN_ID="$(date +%Y%m%d%H%M%S)"
TODAY_YYYYMMDD="$(date +%Y%m%d)"
LOCAL_LOG="$LOG_DIR/10_publish_image_one_${RUN_ID}.log"
: > "$LOCAL_LOG"
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOCAL_LOG" ; }
die(){ log "ERROR: $*"; exit 1; }
trap 'die "line=$LINENO cmd=$BASH_COMMAND"' ERR

source "$CONFIG_FILE"
VERSION="${VERSION:-unknown}"
SERVER_ID="${SERVER_ID:-}"
VOLUME_ID="${VOLUME_ID:-}"
BASE_IMAGE_ID="${IMAGE_ID:-}"
[[ -n "$SERVER_ID" && -n "$VOLUME_ID" && -n "$BASE_IMAGE_ID" ]] || die "SERVER_ID/VOLUME_ID/IMAGE_ID missing in $CONFIG_FILE"

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
    volume_exists || die "volume disappeared while waiting for status=$desired id=$VOLUME_ID"
    st="$(volume_status)"
    [[ "$st" == "$desired" ]] && return 0
    [[ "$st" == error* ]] && die "volume entered bad status=$st"
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

safe_set_visibility() {
  local image_id="$1"
  case "$FINAL_IMAGE_VISIBILITY" in
    private) openstack image set --private "$image_id" || true ;;
    public) openstack image set --public "$image_id" || true ;;
    community) openstack image set --community "$image_id" || true ;;
    shared) openstack image set --shared "$image_id" || true ;;
    *) die "invalid FINAL_IMAGE_VISIBILITY=$FINAL_IMAGE_VISIBILITY" ;;
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
  local image_id="$1" image_name="$2" image_status_now="$3"
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
PUBLISHED_AT=$RUN_ID
EOF
  cp -f "$manifest_file" "$STATE_DIR/current.final-image-${VERSION}.env"
  cp -f "$manifest_file" "$STATE_DIR/current.final-image.env"
  printf '%s' "$manifest_file"
}

cleanup_sources() {
  if [[ "$DELETE_VOLUME_AFTER_PUBLISH" == "yes" ]] && volume_exists; then
    log "deleting volume id=$VOLUME_ID"
    openstack volume delete "$VOLUME_ID"
  fi
  if [[ "$DELETE_BASE_IMAGE_AFTER_PUBLISH" == "yes" ]] && image_exists "$BASE_IMAGE_ID"; then
    log "deleting base image id=$BASE_IMAGE_ID"
    openstack image delete "$BASE_IMAGE_ID"
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
  case "$ON_FINAL_EXISTS" in
    error) die "final image already exists: $final_image_name id=$final_image_id_existing status=$final_status_existing" ;;
    recover)
      if [[ "$final_status_existing" == "active" ]]; then
        log "final image already exists and is active -> recover success: $final_image_name id=$final_image_id_existing"
        apply_metadata "$final_image_id_existing"
        manifest_file="$(write_manifest "$final_image_id_existing" "$final_image_name" "$final_status_existing")"
        cleanup_sources
        log "DONE"; log "VERSION=$VERSION"; log "FINAL_IMAGE_NAME=$final_image_name"; log "FINAL_IMAGE_ID=$final_image_id_existing"; log "MANIFEST_FILE=$manifest_file"
        exit 0
      elif [[ "$final_status_existing" == "queued" || "$final_status_existing" == "saving" || "$final_status_existing" == "importing" ]]; then
        log "final image already exists and is still progressing -> waiting id=$final_image_id_existing status=$final_status_existing"
        wait_for_image_status "$final_image_id_existing" active "$WAIT_FINAL_TIMEOUT_SECONDS" "$WAIT_FINAL_INTERVAL_SECONDS"
        final_status_existing="$(image_status "$final_image_id_existing")"
        apply_metadata "$final_image_id_existing"
        manifest_file="$(write_manifest "$final_image_id_existing" "$final_image_name" "$final_status_existing")"
        cleanup_sources
        log "DONE"; log "VERSION=$VERSION"; log "FINAL_IMAGE_NAME=$final_image_name"; log "FINAL_IMAGE_ID=$final_image_id_existing"; log "MANIFEST_FILE=$manifest_file"
        exit 0
      else
        die "final image exists in non-recoverable status: $final_image_name id=$final_image_id_existing status=$final_status_existing"
      fi
      ;;
    replace)
      log "deleting existing final image first: $final_image_name id=$final_image_id_existing"
      openstack image delete "$final_image_id_existing"
      ;;
    *)
      die "invalid ON_FINAL_EXISTS=$ON_FINAL_EXISTS"
      ;;
  esac
fi

if [[ "$server_present" == no && "$volume_present" == no ]]; then
  die "no publish source left for version $VERSION: server missing, volume missing, final image missing"
fi

if [[ "$server_present" == yes && "$DELETE_SERVER_BEFORE_PUBLISH" == yes ]]; then
  pre_server_status="$(server_status)"
  log "deleting server before publish id=$SERVER_ID status=$pre_server_status"
  openstack server delete "$SERVER_ID"
  log "waiting for boot volume to become available"
  wait_for_volume_status available 600 5
elif [[ "$server_present" == no && "$volume_present" == yes ]]; then
  log "server already absent, volume still present -> continue publish from volume"
  wait_for_volume_status available 600 5
elif [[ "$server_present" == yes && "$DELETE_SERVER_BEFORE_PUBLISH" != yes ]]; then
  pre_server_status="$(server_status)"
  log "server status before publish=$pre_server_status"
  [[ "$pre_server_status" == SHUTOFF ]] || die "server must be SHUTOFF before publish when DELETE_SERVER_BEFORE_PUBLISH=no"
fi

volume_exists || die "volume missing before upload-to-image"

log "uploading volume to image as $FINAL_DISK_FORMAT from volume_id=$VOLUME_ID name=$final_image_name"
openstack volume upload-to-image --disk-format "$FINAL_DISK_FORMAT" --container-format "$FINAL_CONTAINER_FORMAT" --image-name "$final_image_name" "$VOLUME_ID" >/dev/null

start_ts="$(date +%s)"
final_image_id=""
while true; do
  final_image_id="$(find_final_image_id_by_name "$final_image_name")"
  [[ -n "$final_image_id" ]] && break
  now_ts="$(date +%s)"
  (( now_ts - start_ts >= 600 )) && die "timeout waiting for image id by final name=$final_image_name"
  sleep 5
done

if [[ "$WAIT_FOR_FINAL_ACTIVE" == "yes" ]]; then
  log "waiting for final image to become active id=$final_image_id"
  wait_for_image_status "$final_image_id" active "$WAIT_FINAL_TIMEOUT_SECONDS" "$WAIT_FINAL_INTERVAL_SECONDS"
fi

final_image_status="$(image_status "$final_image_id")"
[[ "$final_image_status" == active ]] || die "final image not active: id=$final_image_id status=$final_image_status"
apply_metadata "$final_image_id"
manifest_file="$(write_manifest "$final_image_id" "$final_image_name" "$final_image_status")"
cleanup_sources
log "DONE"; log "VERSION=$VERSION"; log "FINAL_IMAGE_NAME=$final_image_name"; log "FINAL_IMAGE_ID=$final_image_id"; log "MANIFEST_FILE=$manifest_file"
