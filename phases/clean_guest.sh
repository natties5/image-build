#!/usr/bin/env bash
# phases/clean_guest.sh — Poweroff guest VM, wait for SHUTOFF.
# Usage: bash phases/clean_guest.sh --os <name> --version <ver>
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="clean"

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
util_log_info "=== clean_guest: $OS_FAMILY $VERSION ==="

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
fi

GUEST_USER="${GUEST_USER:-root}"
GUEST_PASSWORD="${GUEST_PASSWORD:-mis@Pass01}"
GUEST_SSH_PORT="${GUEST_SSH_PORT:-22}"

# ─── Read create state JSON ───────────────────────────────────────────────────
if ! state_is_ready "create" "$OS_FAMILY" "$VERSION"; then
  util_log_error "Create phase is not ready — run create_vm.sh first"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

GUEST_IP="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "guest_ip")"
SERVER_ID="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "server_id")"

if [[ -z "$GUEST_IP" || -z "$SERVER_ID" ]]; then
  util_log_error "Cannot read guest_ip/server_id from create state JSON"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi
util_log_info "Guest IP: $GUEST_IP  Server: $SERVER_ID"

# ─── Ensure sshpass is installed ─────────────────────────────────────────────
if ! command -v sshpass >/dev/null 2>&1; then
  util_log_info "sshpass not found — installing..."
  apt-get install -y sshpass >/dev/null 2>&1 || true
fi

# ─── SSH: poweroff ────────────────────────────────────────────────────────────
util_log_info "Sending poweroff to guest ${GUEST_IP}..."
sshpass -p "$GUEST_PASSWORD" ssh \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=30 \
  -o PasswordAuthentication=yes \
  -p "$GUEST_SSH_PORT" \
  "${GUEST_USER}@${GUEST_IP}" \
  "shutdown -h now" 2>/dev/null || true

util_log_info "Poweroff command sent (ignoring SSH disconnect error)"

# ─── Wait for server SHUTOFF ─────────────────────────────────────────────────
util_log_info "Waiting for server $SERVER_ID to become SHUTOFF (timeout 300s)..."
if ! os_wait_server_status "$SERVER_ID" "SHUTOFF" 300 10; then
  LAST_STATUS="$(os_get_server_status "$SERVER_ID" 2>/dev/null || echo 'unknown')"
  util_log_warn "Server did not reach SHUTOFF status (last: $LAST_STATUS) — trying OpenStack stop..."
  os_stop_server "$SERVER_ID" || true
  sleep 15
  if ! os_wait_server_status "$SERVER_ID" "SHUTOFF" 120 10; then
    util_log_error "Server still not SHUTOFF after force-stop"
    state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
    exit 1
  fi
fi

util_log_info "Server $SERVER_ID is SHUTOFF"

# ─── Write state JSON ─────────────────────────────────────────────────────────
CLEANED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATE_JSON="$(cat <<EOF
{
  "phase": "clean",
  "os_family": "${OS_FAMILY}",
  "version": "${VERSION}",
  "server_id": "${SERVER_ID}",
  "status": "shutoff",
  "cleaned_at": "${CLEANED_AT}"
}
EOF
)"
state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
state_mark_ready "$PHASE" "$OS_FAMILY" "$VERSION"

util_log_info "=== clean_guest DONE: $OS_FAMILY $VERSION — server SHUTOFF ==="
