#!/usr/bin/env bash
# phases/clean_guest.sh — Full guest OS clean phase driven by GUEST_* config vars.
# Usage: bash phases/clean_guest.sh --os <name> --version <ver>
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="clean"

# --- Argument parsing ---------------------------------------------------------
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

# --- Init log -----------------------------------------------------------------
core_ensure_runtime_dirs
LOG_FILE="$(core_log_path "$PHASE" "$OS_FAMILY" "$VERSION")"
util_init_log_file "$LOG_FILE"
util_log_info "=== clean_guest: $OS_FAMILY $VERSION ==="

# --- Source openrc ------------------------------------------------------------
OPENRC_FILE="${ROOT_DIR}/settings/openrc-file/openrc-nutpri.sh"
if [[ -f "$OPENRC_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$OPENRC_FILE"
  util_log_info "  Sourced openrc: $OPENRC_FILE"
else
  util_log_warn "  openrc not found: $OPENRC_FILE"
fi

# --- Source guest-access.env --------------------------------------------------
if [[ -f "$GUEST_ACCESS_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$GUEST_ACCESS_ENV"
  util_log_info "  Sourced guest-access.env"
fi

# --- Load guest config --------------------------------------------------------
_GUEST_CFG_DEFAULT="${GUEST_CONFIG_DIR}/${OS_FAMILY}/default.env"
_GUEST_CFG_VERSION="${GUEST_CONFIG_DIR}/${OS_FAMILY}/${VERSION}.env"
[[ -f "$_GUEST_CFG_DEFAULT" ]] && { source "$_GUEST_CFG_DEFAULT"; util_log_info "  Loaded default config"; } # shellcheck disable=SC1090
[[ -f "$_GUEST_CFG_VERSION" ]] && { source "$_GUEST_CFG_VERSION"; util_log_info "  Loaded version config"; } # shellcheck disable=SC1090

_G_PORT="${SSH_PORT:-22}"
_G_USER="${SSH_USER:-root}"
_G_AUTH_MODE="${SSH_AUTH_MODE:-password}"
_G_AUTH_VAL="${ROOT_PASSWORD:-}"

# --- Read create state --------------------------------------------------------
if ! state_is_ready "create" "$OS_FAMILY" "$VERSION"; then
  util_log_error "Create phase is not ready -- run create_vm.sh first"
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
util_log_info "  Guest IP: $GUEST_IP  Server: $SERVER_ID"

if ! command -v sshpass >/dev/null 2>&1; then
  util_log_info "  sshpass not found -- installing..."
  apt-get install -y sshpass >/dev/null 2>&1 || true
fi

_gssh() {
  ssh_run "$GUEST_IP" "$_G_PORT" "$_G_USER" "$_G_AUTH_MODE" "$_G_AUTH_VAL" "$@" 2>&1
}

# --- Clean steps --------------------------------------------------------------
if [[ "${GUEST_CLEAN_PACKAGE_CACHE:-0}" == "1" ]]; then
  util_log_info "Cleaning package cache..."
  _CC_CMD="${GUEST_CLEAN_CACHE_COMMAND:-apt-get clean}"
  _CC_OUT="$(_gssh "$_CC_CMD" 2>&1)" || true
  while IFS= read -r _line; do util_log_info "  [clean-cache] $_line"; done <<< "$_CC_OUT"
fi

if [[ -n "${GUEST_AUTOREMOVE_COMMAND:-}" ]]; then
  util_log_info "Running autoremove..."
  _AR_OUT="$(_gssh "DEBIAN_FRONTEND=noninteractive $GUEST_AUTOREMOVE_COMMAND" 2>&1)" || true
  while IFS= read -r _line; do util_log_info "  [autoremove] $_line"; done <<< "$_AR_OUT"
fi

if [[ "${GUEST_CLEAN_HISTORY:-0}" == "1" ]]; then
  util_log_info "Clearing shell history..."
  for _hf in ${GUEST_HISTORY_FILES:-/root/.bash_history}; do
    _gssh "cat /dev/null > $_hf 2>/dev/null || true" >/dev/null 2>&1 || true
  done
  _gssh "history -c 2>/dev/null || true" >/dev/null 2>&1 || true
fi

if [[ "${GUEST_CLEAN_TMP:-0}" == "1" ]]; then
  util_log_info "Clearing tmp..."
  for _tp in ${GUEST_TMP_PATHS:-/tmp/* /var/tmp/*}; do
    _gssh "rm -rf $_tp 2>/dev/null || true" >/dev/null 2>&1 || true
  done
fi

if [[ "${GUEST_CLEAN_LOGS:-0}" == "1" ]]; then
  util_log_info "Truncating logs..."
  for _lp in ${GUEST_LOG_PATHS:-/var/log/*.log}; do
    _gssh "truncate -s 0 $_lp 2>/dev/null || true" >/dev/null 2>&1 || true
  done
fi

if [[ "${GUEST_TRUNCATE_MACHINE_ID:-0}" == "1" ]]; then
  util_log_info "Truncating machine-id..."
  for _mf in ${GUEST_MACHINE_ID_FILES:-/etc/machine-id}; do
    _gssh "truncate -s 0 $_mf 2>/dev/null || true" >/dev/null 2>&1 || true
  done
fi

if [[ "${GUEST_REMOVE_SSH_HOST_KEYS:-0}" == "1" ]]; then
  util_log_info "Removing SSH host keys..."
  _gssh "rm -f /etc/ssh/ssh_host_* 2>/dev/null || true" >/dev/null 2>&1 || true
fi

if [[ "${GUEST_CLOUD_INIT_CLEAN_BEFORE_CAPTURE:-0}" == "1" ]]; then
  util_log_info "Running cloud-init clean..."
  _CI_CLEAN_CMD="${GUEST_CLOUD_INIT_CLEAN_COMMAND:-cloud-init clean --logs --seed || true}"
  _CI_OUT="$(_gssh "$_CI_CLEAN_CMD" 2>&1)" || true
  while IFS= read -r _line; do util_log_info "  [cloud-init-clean] $_line"; done <<< "$_CI_OUT"
fi

if [[ "${GUEST_FSTRIM_BEFORE_SHUTDOWN:-0}" == "1" ]]; then
  util_log_info "Running fstrim..."
  _FT_OUT="$(_gssh "fstrim -av 2>/dev/null || true" 2>&1)" || true
  while IFS= read -r _line; do util_log_info "  [fstrim] $_line"; done <<< "$_FT_OUT"
fi

# --- Final shutdown -----------------------------------------------------------
util_log_info "Sending shutdown to guest..."
_gssh "shutdown -h now || true" 2>/dev/null || true
util_log_info "  Poweroff command sent"

# --- Wait for SHUTOFF ---------------------------------------------------------
util_log_info "Waiting for server $SERVER_ID to become SHUTOFF (timeout 300s)..."
if ! os_wait_server_status "$SERVER_ID" "SHUTOFF" 300 10; then
  LAST_STATUS="$(os_get_server_status "$SERVER_ID" 2>/dev/null || echo 'unknown')"
  util_log_warn "  Server did not reach SHUTOFF (last: $LAST_STATUS) -- trying OS stop..."
  os_stop_server "$SERVER_ID" || true
  sleep 15
  if ! os_wait_server_status "$SERVER_ID" "SHUTOFF" 120 10; then
    util_log_error "Server still not SHUTOFF after force-stop"
    state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
    exit 1
  fi
fi
util_log_info "  Server $SERVER_ID is SHUTOFF"

# --- Write state JSON ---------------------------------------------------------
CLEANED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATE_JSON="{
  \"phase\": \"clean\",
  \"os_family\": \"${OS_FAMILY}\",
  \"version\": \"${VERSION}\",
  \"server_id\": \"${SERVER_ID}\",
  \"guest_ip\": \"${GUEST_IP}\",
  \"steps_completed\": [\"cache\",\"autoremove\",\"history\",\"tmp\",\"logs\",\"machine-id\",\"ssh-host-keys\",\"cloud-init-clean\",\"fstrim\",\"shutdown\"],
  \"status\": \"shutoff\",
  \"cleaned_at\": \"${CLEANED_AT}\"
}"

state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
state_mark_ready "$PHASE" "$OS_FAMILY" "$VERSION"
util_log_info "=== clean_guest DONE: $OS_FAMILY $VERSION ==="
