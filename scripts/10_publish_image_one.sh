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
source "$OPENRC_PATH_FILE"
[[ -n "${OPENRC_FILE:-}" && -f "$OPENRC_FILE" ]] || { echo "OPENRC_FILE invalid" >&2; exit 1; }
source "$OPENRC_FILE"

if [[ -f "$PUBLISH_CONFIG_FILE" ]]; then
  source "$PUBLISH_CONFIG_FILE"
fi

PIPELINE_ROOT="${PIPELINE_ROOT:-$REPO_ROOT}"
FINAL_IMAGE_NAME_TEMPLATE="${FINAL_IMAGE_NAME_TEMPLATE:-ubuntu-{version}-golden}"
FINAL_IMAGE_VISIBILITY="${FINAL_IMAGE_VISIBILITY:-private}"
FINAL_IMAGE_TAGS="${FINAL_IMAGE_TAGS:-stage:final,os:ubuntu}"
ON_FINAL_EXISTS="${ON_FINAL_EXISTS:-error}"
WAIT_FOR_FINAL_ACTIVE="${WAIT_FOR_FINAL_ACTIVE:-yes}"
WAIT_FINAL_TIMEOUT_SECONDS="${WAIT_FINAL_TIMEOUT_SECONDS:-3600}"
WAIT_FINAL_INTERVAL_SECONDS="${WAIT_FINAL_INTERVAL_SECONDS:-10}"
DELETE_SERVER_AFTER_PUBLISH="${DELETE_SERVER_AFTER_PUBLISH:-yes}"
DELETE_VOLUME_AFTER_PUBLISH="${DELETE_VOLUME_AFTER_PUBLISH:-yes}"
DELETE_BASE_IMAGE_AFTER_PUBLISH="${DELETE_BASE_IMAGE_AFTER_PUBLISH:-yes}"
SET_OS_DISTRO_PROPERTY="${SET_OS_DISTRO_PROPERTY:-yes}"
SET_OS_VERSION_PROPERTY="${SET_OS_VERSION_PROPERTY:-yes}"

RUN_ID="$(date +%Y%m%d%H%M%S)"
LOCAL_LOG="$LOG_DIR/10_publish_image_one_${RUN_ID}.log"
: > "$LOCAL_LOG"

log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOCAL_LOG" ; }
die(){ log "ERROR: $*"; exit 1; }
trap 'die "line=$LINENO cmd=$BASH_COMMAND"' ERR

need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
for c in openstack awk grep sed head; do need_cmd "$c"; done

openstack token issue >/dev/null

source "$CONFIG_FILE"

VERSION="${VERSION:-unknown}"
SERVER_ID="${SERVER_ID:-}"
VOLUME_ID="${VOLUME_ID:-}"
BASE_IMAGE_ID="${IMAGE_ID:-}"
VM_NAME="${VM_NAME:-}"
[[ -n "$SERVER_ID" && -n "$VOLUME_ID" && -n "$BASE_IMAGE_ID" ]] || die "SERVER_ID/VOLUME_ID/IMAGE_ID missing in $CONFIG_FILE"

server_status() { openstack server show "$SERVER_ID" -f value -c status 2>/dev/null || true; }
wait_for_status() {
  local kind="$1" id="$2" desired="$3" timeout_sec="$4" interval_sec="$5" st start now
  start="$(date +%s)"
  while true; do
    if [[ "$kind" == "image" ]]; then
      st="$(openstack image show "$id" -f value -c status 2>/dev/null || true)"
    elif [[ "$kind" == "server" ]]; then
      st="$(openstack server show "$id" -f value -c status 2>/dev/null || true)"
    elif [[ "$kind" == "volume" ]]; then
      st="$(openstack volume show "$id" -f value -c status 2>/dev/null || true)"
    else
      die "unknown kind=$kind"
    fi
    [[ "$st" == "$desired" ]] && return 0
    if [[ "$kind" == "image" && ( "$st" == "killed" || "$st" == "deleted" || "$st" == "deactivated" ) ]]; then
      die "image entered bad status=$st id=$id"
    fi
    if [[ "$kind" == "server" && "$st" == "ERROR" ]]; then
      die "server entered ERROR id=$id"
    fi
    now="$(date +%s)"
    (( now - start >= timeout_sec )) && die "timeout waiting for $kind id=$id status=$desired last_status=${st:-unknown}"
    sleep "$interval_sec"
  done
}

pre_status="$(server_status)"
log "server status before publish=$pre_status"
[[ "$pre_status" == "SHUTOFF" ]] || die "server must be SHUTOFF before publish"

final_image_name="${FINAL_IMAGE_NAME_TEMPLATE//\{version\}/$VERSION}"
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
  log "creating final image from volume_id=$VOLUME_ID name=$final_image_name"
  create_args=(image create "$final_image_name" --volume "$VOLUME_ID")
  case "$FINAL_IMAGE_VISIBILITY" in
    private) create_args+=(--private) ;;
    public) create_args+=(--public) ;;
    community) create_args+=(--community) ;;
    shared) create_args+=(--shared) ;;
    *) die "invalid FINAL_IMAGE_VISIBILITY=$FINAL_IMAGE_VISIBILITY" ;;
  esac
  if [[ "$SET_OS_DISTRO_PROPERTY" == "yes" ]]; then create_args+=(--property os_distro=ubuntu); fi
  if [[ "$SET_OS_VERSION_PROPERTY" == "yes" ]]; then create_args+=(--property os_version="$VERSION"); fi
  create_args+=(--property pipeline_stage=final)
  create_args+=(--property source_server_id="$SERVER_ID")
  create_args+=(--property source_volume_id="$VOLUME_ID")
  create_args+=(--property source_base_image_id="$BASE_IMAGE_ID")
  final_image_id="$(openstack "${create_args[@]}" -f value -c id)"
  [[ -n "$final_image_id" ]] || die "failed to create final image"
fi

IFS=',' read -r -a tags_array <<< "$FINAL_IMAGE_TAGS"
for tag in "${tags_array[@]}"; do
  tag="$(printf '%s' "$tag" | xargs)"
  [[ -n "$tag" ]] || continue
  openstack image set --tag "$tag" "$final_image_id"
done

if [[ "$WAIT_FOR_FINAL_ACTIVE" == "yes" ]]; then
  log "waiting for final image to become active id=$final_image_id"
  wait_for_status image "$final_image_id" active "$WAIT_FINAL_TIMEOUT_SECONDS" "$WAIT_FINAL_INTERVAL_SECONDS"
fi

final_image_status="$(openstack image show "$final_image_id" -f value -c status)"
[[ "$final_image_status" == "active" ]] || die "final image not active: id=$final_image_id status=$final_image_status"

manifest_file="$MANIFEST_DIR/final-image-${VERSION}.env"
cat > "$manifest_file" <<EOF
VERSION=$VERSION
FINAL_IMAGE_NAME=$final_image_name
FINAL_IMAGE_ID=$final_image_id
FINAL_IMAGE_STATUS=$final_image_status
SOURCE_SERVER_ID=$SERVER_ID
SOURCE_VOLUME_ID=$VOLUME_ID
SOURCE_BASE_IMAGE_ID=$BASE_IMAGE_ID
DELETE_SERVER_AFTER_PUBLISH=$DELETE_SERVER_AFTER_PUBLISH
DELETE_VOLUME_AFTER_PUBLISH=$DELETE_VOLUME_AFTER_PUBLISH
DELETE_BASE_IMAGE_AFTER_PUBLISH=$DELETE_BASE_IMAGE_AFTER_PUBLISH
EOF

cp -f "$manifest_file" "$STATE_DIR/current.final-image-${VERSION}.env"
cp -f "$manifest_file" "$STATE_DIR/current.final-image.env"

log "final image created successfully name=$final_image_name id=$final_image_id"

if [[ "$DELETE_SERVER_AFTER_PUBLISH" == "yes" ]]; then
  log "deleting server id=$SERVER_ID"
  openstack server delete "$SERVER_ID"
fi

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
