#!/usr/bin/env bash
# phases/configure_guest.sh — SSH into guest VM and apply OS configuration (apt update only).
# Usage: bash phases/configure_guest.sh --os <name> --version <ver>
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="configure"

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
util_log_info "=== configure_guest: $OS_FAMILY $VERSION ==="

# ─── Source openrc ────────────────────────────────────────────────────────────
OPENRC_FILE="${ROOT_DIR}/settings/openrc-file/openrc-nutpri.sh"
if [[ -f "$OPENRC_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$OPENRC_FILE"
  util_log_info "Sourced openrc: $OPENRC_FILE"
else
  util_log_warn "openrc not found: $OPENRC_FILE"
fi

# ─── Source guest access settings ────────────────────────────────────────────
if [[ -f "$GUEST_ACCESS_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$GUEST_ACCESS_ENV"
  util_log_info "Sourced guest-access.env"
else
  util_log_warn "guest-access.env not found: $GUEST_ACCESS_ENV — using defaults"
fi

GUEST_USER="${GUEST_USER:-root}"
GUEST_PASSWORD="${GUEST_PASSWORD:-mis@Pass01}"
GUEST_SSH_PORT="${GUEST_SSH_PORT:-22}"
GUEST_SSH_TIMEOUT="${GUEST_SSH_TIMEOUT:-60}"

# ─── Read create state JSON ───────────────────────────────────────────────────
if ! state_is_ready "create" "$OS_FAMILY" "$VERSION"; then
  util_log_error "Create phase is not ready — run create_vm.sh first"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

GUEST_IP="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "guest_ip")"
SERVER_ID="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "server_id")"
VOLUME_ID="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "volume_id")"

if [[ -z "$GUEST_IP" ]]; then
  util_log_error "Cannot read guest_ip from create state JSON"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi
util_log_info "Guest IP: $GUEST_IP  Server: $SERVER_ID  Volume: $VOLUME_ID"

# ─── Ensure sshpass is installed ─────────────────────────────────────────────
if ! command -v sshpass >/dev/null 2>&1; then
  util_log_info "sshpass not found — installing..."
  apt-get install -y sshpass >/dev/null 2>&1 || true
fi
util_require_cmd sshpass

# ─── SSH: apt-get update ──────────────────────────────────────────────────────
util_log_info "Running apt-get update on guest ${GUEST_IP}..."
APT_OUTPUT=""
APT_EXIT=0

APT_OUTPUT="$(sshpass -p "$GUEST_PASSWORD" ssh \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout="$GUEST_SSH_TIMEOUT" \
  -o PasswordAuthentication=yes \
  -p "$GUEST_SSH_PORT" \
  "${GUEST_USER}@${GUEST_IP}" \
  "DEBIAN_FRONTEND=noninteractive apt-get update -y 2>&1" 2>&1)" || APT_EXIT=$?

# Log all output
while IFS= read -r line; do
  util_log_info "  [apt] $line"
done <<< "$APT_OUTPUT"

if [[ "$APT_EXIT" -ne 0 ]]; then
  util_log_error "apt-get update failed with exit code: $APT_EXIT"
  # Write failed state
  CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  STATE_JSON="$(cat <<EOF
{
  "phase": "configure",
  "os_family": "${OS_FAMILY}",
  "version": "${VERSION}",
  "guest_ip": "${GUEST_IP}",
  "steps_completed": [],
  "status": "failed",
  "failure_reason": "apt-get update exit=${APT_EXIT}",
  "configured_at": "${CONFIGURED_AT}"
}
EOF
)"
  state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

util_log_info "apt-get update completed successfully"

# ─── Write state JSON ─────────────────────────────────────────────────────────
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATE_JSON="$(cat <<EOF
{
  "phase": "configure",
  "os_family": "${OS_FAMILY}",
  "version": "${VERSION}",
  "guest_ip": "${GUEST_IP}",
  "steps_completed": ["apt-update"],
  "status": "ok",
  "configured_at": "${CONFIGURED_AT}"
}
EOF
)"
state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
state_mark_ready "$PHASE" "$OS_FAMILY" "$VERSION"

util_log_info "=== configure_guest DONE: $OS_FAMILY $VERSION ==="
