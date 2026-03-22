#!/usr/bin/env bash
# phases/publish_final.sh — Delete server, upload volume as final image, cleanup.
# Usage: bash phases/publish_final.sh --os <name> --version <ver>
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="publish"

# ─── Argument parsing ─────────────────────────────────────────────────────────
OS_FAMILY=""
VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --os)      OS_FAMILY="$2"; shift 2 ;;
    --version) VERSION="$2";   shift 2 ;;
    *) echo "Usage: $0 --os <name> --version <ver>" >&2; exit 2 ;;
  esac
done
[[ -n "$OS_FAMILY" && -n "$VERSION" ]] || { echo "Usage: $0 --os <name> --version <ver>" >&2; exit 2; }

# ─── Init log ─────────────────────────────────────────────────────────────────
core_ensure_runtime_dirs
LOG_FILE="$(core_log_path "$PHASE" "$OS_FAMILY" "$VERSION")"
util_init_log_file "$LOG_FILE"
util_log_info "=== publish_final: $OS_FAMILY $VERSION ==="

# ─── Source openrc ────────────────────────────────────────────────────────────
OPENRC_FILE="${ROOT_DIR}/settings/openrc-file/openrc-nutpri.sh"
if [[ -f "$OPENRC_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$OPENRC_FILE"
  util_log_info "Sourced openrc: $OPENRC_FILE"
else
  util_log_warn "openrc not found: $OPENRC_FILE"
fi

# ─── Read create state JSON ───────────────────────────────────────────────────
if ! state_is_ready "create" "$OS_FAMILY" "$VERSION"; then
  util_log_error "Create phase is not ready — run create_vm.sh first"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

SERVER_ID="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "server_id")"
VOLUME_ID="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "volume_id")"
BASE_IMAGE_ID="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "base_image_id")"

if [[ -z "$SERVER_ID" || -z "$VOLUME_ID" ]]; then
  util_log_error "Cannot read server_id/volume_id from create state JSON"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi
util_log_info "Server: $SERVER_ID  Volume: $VOLUME_ID  Base image: $BASE_IMAGE_ID"

# ─── Delete server ────────────────────────────────────────────────────────────
util_log_info "Deleting server: $SERVER_ID ..."
SERVER_DELETED=false

# Check if server still exists
if openstack_cmd server show "$SERVER_ID" >/dev/null 2>&1; then
  openstack_cmd server delete "$SERVER_ID" 2>/dev/null || true
  util_log_info "Waiting for server to be deleted (timeout 300s)..."
  if os_wait_server_deleted "$SERVER_ID" 300 10; then
    SERVER_DELETED=true
    util_log_info "Server $SERVER_ID deleted"
  else
    util_log_warn "Server delete timed out — continuing (volume may still be in-use)"
  fi
else
  util_log_info "Server $SERVER_ID not found — already deleted"
  SERVER_DELETED=true
fi

# ─── Wait for volume available ────────────────────────────────────────────────
util_log_info "Waiting for volume $VOLUME_ID to become available (timeout 600s)..."
if ! os_wait_volume_status "$VOLUME_ID" "available" 600 10; then
  LAST_VOL_STATUS="$(os_get_volume_status "$VOLUME_ID" 2>/dev/null || echo 'unknown')"
  util_log_error "Volume $VOLUME_ID did not become available (last: $LAST_VOL_STATUS)"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi
util_log_info "Volume $VOLUME_ID is available"

# ─── Generate final image name ────────────────────────────────────────────────
FINAL_IMAGE_NAME="${OS_FAMILY}-${VERSION}-$(date +%Y%m%d)"
util_log_info "Final image name: $FINAL_IMAGE_NAME"

# ─── Check if final image already exists ──────────────────────────────────────
FINAL_IMAGE_ID=""
EXISTING_FINAL_ID="$(os_find_image_id_by_name "$FINAL_IMAGE_NAME" 2>/dev/null || echo '')"

if [[ -n "$EXISTING_FINAL_ID" ]]; then
  EXISTING_STATUS="$(os_get_image_status "$EXISTING_FINAL_ID" 2>/dev/null || echo '')"
  util_log_info "Found existing final image: $EXISTING_FINAL_ID status=$EXISTING_STATUS"
  if [[ "$EXISTING_STATUS" == "active" ]]; then
    util_log_info "Final image already exists and is active — recovering"
    FINAL_IMAGE_ID="$EXISTING_FINAL_ID"
  else
    util_log_warn "Existing final image not active ($EXISTING_STATUS) — proceeding with upload"
  fi
fi

# ─── Upload volume to image ───────────────────────────────────────────────────
if [[ -z "$FINAL_IMAGE_ID" ]]; then
  util_log_info "Uploading volume $VOLUME_ID as final image: $FINAL_IMAGE_NAME ..."
  UPLOAD_ID="$(os_upload_volume_to_image "$VOLUME_ID" "$FINAL_IMAGE_NAME" "$OS_FAMILY" "$VERSION")"

  if [[ -z "$UPLOAD_ID" ]]; then
    util_log_info "Upload command returned empty ID — polling Glance for image..."
    UPLOAD_ID="$(os_find_or_wait_image_id_by_name "$FINAL_IMAGE_NAME" 300 10)"
    if [[ -z "$UPLOAD_ID" ]]; then
      util_log_error "Could not find final image '$FINAL_IMAGE_NAME' in Glance after upload"
      state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
      exit 1
    fi
  fi
  util_log_info "Final image ID: $UPLOAD_ID — waiting for active (timeout 3600s)..."

  ELAPSED=0
  while (( ELAPSED < 3600 )); do
    FSTATUS="$(os_get_image_status "$UPLOAD_ID" 2>/dev/null || echo '')"
    if [[ "$FSTATUS" == "active" ]]; then
      util_log_info "Final image $UPLOAD_ID is active"
      break
    fi
    if [[ "$FSTATUS" == "killed" || "$FSTATUS" == "deleted" ]]; then
      util_log_error "Final image $UPLOAD_ID entered bad status: $FSTATUS"
      state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
      exit 1
    fi
    if (( ELAPSED % 60 == 0 && ELAPSED > 0 )); then
      util_log_info "  waiting... status=${FSTATUS} elapsed=${ELAPSED}s"
    fi
    sleep 10
    ELAPSED=$(( ELAPSED + 10 ))
  done

  FSTATUS="$(os_get_image_status "$UPLOAD_ID" 2>/dev/null || echo 'unknown')"
  if [[ "$FSTATUS" != "active" ]]; then
    util_log_error "Final image did not become active after 3600s (last: $FSTATUS)"
    state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
    exit 1
  fi
  FINAL_IMAGE_ID="$UPLOAD_ID"
fi

util_log_info "Final image ready: $FINAL_IMAGE_ID ($FINAL_IMAGE_NAME)"

# ─── Cleanup ──────────────────────────────────────────────────────────────────
VOLUME_DELETED=false
BASE_IMAGE_DELETED=false

util_log_info "Deleting volume: $VOLUME_ID ..."
if openstack_cmd volume delete "$VOLUME_ID" 2>/dev/null; then
  VOLUME_DELETED=true
  util_log_info "Volume $VOLUME_ID deleted"
else
  util_log_warn "Volume delete failed or already gone: $VOLUME_ID"
  if ! openstack_cmd volume show "$VOLUME_ID" >/dev/null 2>&1; then
    VOLUME_DELETED=true
  fi
fi

if [[ -n "$BASE_IMAGE_ID" ]]; then
  util_log_info "Deleting base image: $BASE_IMAGE_ID ..."
  if openstack_cmd image delete "$BASE_IMAGE_ID" 2>/dev/null; then
    BASE_IMAGE_DELETED=true
    util_log_info "Base image $BASE_IMAGE_ID deleted"
  else
    util_log_warn "Base image delete failed or already gone: $BASE_IMAGE_ID"
    if ! openstack_cmd image show "$BASE_IMAGE_ID" >/dev/null 2>&1; then
      BASE_IMAGE_DELETED=true
    fi
  fi
fi

# ─── Write state JSON ─────────────────────────────────────────────────────────
PUBLISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATE_JSON="$(cat <<EOF
{
  "phase": "publish",
  "os_family": "${OS_FAMILY}",
  "version": "${VERSION}",
  "final_image_name": "${FINAL_IMAGE_NAME}",
  "final_image_id": "${FINAL_IMAGE_ID}",
  "final_image_status": "active",
  "server_deleted": ${SERVER_DELETED},
  "volume_deleted": ${VOLUME_DELETED},
  "base_image_deleted": ${BASE_IMAGE_DELETED},
  "published_at": "${PUBLISHED_AT}"
}
EOF
)"
state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
state_mark_ready "$PHASE" "$OS_FAMILY" "$VERSION"

util_log_info "=== publish_final DONE: $OS_FAMILY $VERSION — image=$FINAL_IMAGE_ID ($FINAL_IMAGE_NAME) ==="
