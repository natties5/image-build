#!/usr/bin/env bash
# phases/import_base.sh — Import a local base image into OpenStack Glance.
# Usage: bash phases/import_base.sh --os <name> --version <ver>
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="import"

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
util_log_info "=== import_base: $OS_FAMILY $VERSION ==="

# ─── Load active openrc from session ──────────────────────────────────────────
_load_active_openrc() {
  local _profile="${SESSION_DIR}/active-profile.env"
  if [[ ! -f "$_profile" ]]; then
    util_log_error "No active OpenRC profile found."
    util_log_error "→ Run: Settings → Load OpenRC & Validate Auth first"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$_profile"
  if [[ "${AUTH_STATUS:-}" != "ok" ]]; then
    util_log_error "OpenRC profile auth status is not 'ok' (status=${AUTH_STATUS:-unknown})"
    util_log_error "→ Re-run: Settings → Load OpenRC & Validate Auth"
    return 1
  fi
  local _openrc_path="${ACTIVE_OPENRC:-}"
  if [[ -z "$_openrc_path" || ! -f "$_openrc_path" ]]; then
    util_log_error "ACTIVE_OPENRC path invalid or missing: ${_openrc_path:-<empty>}"
    return 1
  fi
  unset OS_INSECURE OPENSTACK_INSECURE 2>/dev/null || true
  # shellcheck disable=SC1090
  source "$_openrc_path"
  [[ "${OS_INSECURE:-false}" == "true" ]] && export OS_INSECURE="true"
  util_log_info "Sourced openrc from active profile: $(basename "$_openrc_path")"
}

if ! _load_active_openrc; then
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

# ─── Source openstack settings (for image name template) ─────────────────────
if [[ -f "$OPENSTACK_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$OPENSTACK_ENV"
  util_log_info "Sourced openstack.env"
fi

# ─── Read sync state JSON ─────────────────────────────────────────────────────
SYNC_JSON="$(core_state_json "sync" "$OS_FAMILY" "$VERSION")"
if [[ ! -f "$SYNC_JSON" ]]; then
  util_log_error "Sync state JSON not found: $SYNC_JSON"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

FILENAME="$(state_read_json_field "sync" "$OS_FAMILY" "$VERSION" "filename")"
SYNC_FORMAT_SELECTED="$(state_read_json_field "sync" "$OS_FAMILY" "$VERSION" "format_selected" 2>/dev/null || echo '')"
if [[ -z "$FILENAME" ]]; then
  util_log_error "Cannot read filename from sync JSON: $SYNC_JSON"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

# Construct image path using Linux-native paths (IMAGES_DIR from core_paths.sh)
IMAGE_PATH="${IMAGES_DIR}/${OS_FAMILY}/${VERSION}/${FILENAME}"
util_log_info "Image file expected at: $IMAGE_PATH"

# ─── Check image file exists ──────────────────────────────────────────────────
if [[ ! -f "$IMAGE_PATH" ]]; then
  util_log_error "Image file not found: $IMAGE_PATH"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi
util_log_info "Image file found: $(du -h "$IMAGE_PATH" | cut -f1) — $IMAGE_PATH"

# ─── Detect actual source disk format ─────────────────────────────────────────
if ! DETECTED_DISK_FORMAT="$(os_detect_local_image_disk_format "$IMAGE_PATH")"; then
  util_log_error "Failed to detect source image disk format for: $IMAGE_PATH"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi
util_log_info "Detected source image disk format: $DETECTED_DISK_FORMAT"

# ─── Define base image name ───────────────────────────────────────────────────
BASE_IMAGE_NAME="base-${OS_FAMILY}-${VERSION}"
util_log_info "Base image name: $BASE_IMAGE_NAME"

# ─── Check if base image already exists in Glance ────────────────────────────
EXISTING_ID="$(os_find_image_id_by_name "$BASE_IMAGE_NAME" 2>/dev/null || echo '')"

if [[ -n "$EXISTING_ID" ]]; then
  EXISTING_STATUS="$(os_get_image_status "$EXISTING_ID" 2>/dev/null || echo '')"
  util_log_info "Found existing image: $EXISTING_ID status=$EXISTING_STATUS"

  if [[ "$EXISTING_STATUS" == "active" ]]; then
    util_log_info "Base image already exists and is active — skipping import"
    IMPORTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    STATE_JSON="$(cat <<EOF
{
  "phase": "import",
  "os_family": "${OS_FAMILY}",
  "version": "${VERSION}",
  "base_image_name": "${BASE_IMAGE_NAME}",
  "base_image_id": "${EXISTING_ID}",
  "status": "skipped-exists",
  "sync_format_selected": "${SYNC_FORMAT_SELECTED}",
  "detected_disk_format": "${DETECTED_DISK_FORMAT}",
  "workspace_path": "${IMAGE_PATH}",
  "imported_at": "${IMPORTED_AT}"
}
EOF
)"
    state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
    state_mark_ready "$PHASE" "$OS_FAMILY" "$VERSION"
    util_log_info "Phase import: skipped-exists — base image already active"
    exit 0
  else
    util_log_warn "Existing image $EXISTING_ID is not active (status=$EXISTING_STATUS) — deleting and re-importing"
    os_delete_image "$EXISTING_ID"
    sleep 5
  fi
fi

# ─── Import image ─────────────────────────────────────────────────────────────
util_log_info "Importing image: $BASE_IMAGE_NAME ..."
BASE_IMAGE_ID="$(os_create_base_image "$BASE_IMAGE_NAME" "$IMAGE_PATH" "$DETECTED_DISK_FORMAT" "$OS_FAMILY" "$VERSION" "private")"

if [[ -z "$BASE_IMAGE_ID" ]]; then
  util_log_error "image create returned empty ID — checking if image was created anyway..."
  BASE_IMAGE_ID="$(os_find_image_id_by_name "$BASE_IMAGE_NAME" 2>/dev/null || echo '')"
  if [[ -z "$BASE_IMAGE_ID" ]]; then
    util_log_error "Image creation failed: no ID found for $BASE_IMAGE_NAME"
    state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
    exit 1
  fi
  util_log_info "Found image after create: $BASE_IMAGE_ID"
fi

util_log_info "Image created with ID: $BASE_IMAGE_ID"

# ─── Wait for image status=active ─────────────────────────────────────────────
util_log_info "Waiting for image $BASE_IMAGE_ID to become active (timeout 1800s)..."
if ! os_wait_image_status "$BASE_IMAGE_ID" "active" 1800 10; then
  FINAL_STATUS="$(os_get_image_status "$BASE_IMAGE_ID" 2>/dev/null || echo 'unknown')"
  util_log_error "Image did not become active (last status: $FINAL_STATUS)"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

# ─── Write state JSON ─────────────────────────────────────────────────────────
IMPORTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATE_JSON="$(cat <<EOF
{
  "phase": "import",
  "os_family": "${OS_FAMILY}",
  "version": "${VERSION}",
  "base_image_name": "${BASE_IMAGE_NAME}",
  "base_image_id": "${BASE_IMAGE_ID}",
  "status": "active",
  "sync_format_selected": "${SYNC_FORMAT_SELECTED}",
  "detected_disk_format": "${DETECTED_DISK_FORMAT}",
  "workspace_path": "${IMAGE_PATH}",
  "imported_at": "${IMPORTED_AT}"
}
EOF
)"
state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
state_mark_ready "$PHASE" "$OS_FAMILY" "$VERSION"

util_log_info "=== import_base DONE: $OS_FAMILY $VERSION — image $BASE_IMAGE_ID ==="
