#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/local_overrides.sh"
STATE_DIR="${STATE_DIR:-$REPO_ROOT/runtime/state}"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"
CLEAN_STATE_DIR="${CLEAN_STATE_DIR:-$STATE_DIR/clean}"
OPENRC_PATH_FILE="${OPENRC_PATH_FILE:-$REPO_ROOT/config/runtime/openrc.path}"
CLEAN_CONFIG_FILE="${CLEAN_CONFIG_FILE:-$REPO_ROOT/config/control/clean.env}"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$CLEAN_STATE_DIR"

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
RUN_ID="$(date +%Y%m%d%H%M%S)"
LOCAL_LOG=""
SUMMARY_FILE=""
REMOTE_LOG=""
REMOTE_RUN_LOG=""

LOG(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOCAL_LOG" ; }
DIE(){ LOG "ERROR: $*"; exit 1; }
on_err(){ local ec=$?; LOG "ERROR exit_code=$ec line=${BASH_LINENO[0]} cmd=${BASH_COMMAND}"; exit "$ec"; }
trap on_err ERR

need_cmd(){ command -v "$1" >/dev/null 2>&1 || DIE "missing command: $1"; }
for c in ssh sshpass openstack awk sed grep timeout; do need_cmd "$c"; done

[[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]] || { echo "usage: $0 <ubuntu-version | path-to-.configure.env>" >&2; exit 1; }
imagectl_source_local_overrides "$REPO_ROOT"
[[ -f "$OPENRC_PATH_FILE" ]] || DIE "missing config: $OPENRC_PATH_FILE"
source "$OPENRC_PATH_FILE"
[[ -n "${OPENRC_FILE:-}" && -f "$OPENRC_FILE" ]] || DIE "OPENRC_FILE invalid"
source "$OPENRC_FILE"

if [[ -f "$CLEAN_CONFIG_FILE" ]]; then
  set -a
  source "$CLEAN_CONFIG_FILE"
  set +a
fi
POWEROFF_WHEN_DONE="${POWEROFF_WHEN_DONE:-yes}"
BUILD_USER_HOME="${BUILD_USER_HOME:-}"

extract_first_ipv4() {
  local s="${1:-}"
  grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' <<<"$s" | head -n1 || true
}

load_config_file() {
  source "$1"
  VM_HOST="${VM_HOST:-${LOGIN_IP:-}}"
  VM_HOST="$(extract_first_ipv4 "$VM_HOST")"
  LOGIN_IP="$VM_HOST"
  SSH_USER="${SSH_USER:-${LOGIN_USER:-root}}"
  SSH_PORT="${SSH_PORT:-22}"
  SSH_PASSWORD="${SSH_PASSWORD:-${LOGIN_PASSWORD:-${ROOT_PASSWORD:-}}}"
  VERSION="${VERSION:-unknown}"
  SERVER_ID="${SERVER_ID:-}"
  VM_NAME="${VM_NAME:-}"
  [[ -n "$VM_HOST" ]] || DIE "VM_HOST / LOGIN_IP missing or unparsable in $1"
  [[ -n "$SSH_USER" && -n "$SSH_PASSWORD" && -n "$SERVER_ID" ]] || DIE "SSH_USER/SSH_PASSWORD/SERVER_ID missing in $1"
}
load_config_file "$CONFIG_FILE"

# self-heal state file if older stage wrote dict-ish host
sed -i "s|^VM_HOST=.*|VM_HOST=$VM_HOST|" "$CONFIG_FILE" 2>/dev/null || true
if grep -q '^LOGIN_IP=' "$CONFIG_FILE" 2>/dev/null; then
  sed -i "s|^LOGIN_IP=.*|LOGIN_IP=$VM_HOST|" "$CONFIG_FILE" 2>/dev/null || true
else
  printf '\nLOGIN_IP=%s\n' "$VM_HOST" >> "$CONFIG_FILE" 2>/dev/null || true
fi

CLEAN_STATE_FILE="$CLEAN_STATE_DIR/clean-${VERSION}.env"
LOCAL_LOG="$LOG_DIR/final_clean_${VM_HOST}_${RUN_ID}.log"
SUMMARY_FILE="$LOG_DIR/final_clean_${VM_HOST}_${RUN_ID}.summary.txt"
REMOTE_LOG="/var/log/final-clean-${RUN_ID}.log"
REMOTE_RUN_LOG="$LOG_DIR/final_clean_remote_stdout_${VM_HOST}_${RUN_ID}.log"
: > "$LOCAL_LOG"
: > "$REMOTE_RUN_LOG"

LOG "LOCAL_LOG=$LOCAL_LOG"
LOG "SUMMARY_FILE=$SUMMARY_FILE"
LOG "REMOTE_LOG=$REMOTE_LOG"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT")
ssh_run(){ sshpass -p "$SSH_PASSWORD" ssh "${SSH_OPTS[@]}" "$SSH_USER@$VM_HOST" "$@"; }
server_status(){ openstack server show "$SERVER_ID" -f value -c status 2>/dev/null || true; }

wait_for_server_status() {
  local desired="$1" timeout_sec="${2:-300}" start now st
  start="$(date +%s)"
  while true; do
    st="$(server_status)"
    [[ "$st" == "$desired" ]] && return 0
    [[ "$st" == "ERROR" ]] && DIE "server entered ERROR state"
    now="$(date +%s)"
    (( now - start >= timeout_sec )) && DIE "timeout waiting for server status=$desired last_status=${st:-unknown}"
    sleep 3
  done
}

wait_for_ssh() {
  local host="$1" port="$2" timeout_sec="${3:-300}" start now
  start="$(date +%s)"
  LOG "waiting for SSH on $host:$port"
  while true; do
    if timeout 5 bash -c ">/dev/tcp/$host/$port" 2>/dev/null; then
      LOG "SSH is ready"
      return 0
    fi
    now="$(date +%s)"
    (( now - start >= timeout_sec )) && return 1
    sleep 2
  done
}

mark_clean_done() {
  cat > "$CLEAN_STATE_FILE" <<EOF
CLEAN_DONE=yes
CLEAN_TS=$(date '+%F %T')
VERSION=$VERSION
SERVER_ID=$SERVER_ID
VM_NAME=$VM_NAME
VM_HOST=$VM_HOST
EXPECTED_FINAL_STATUS=SHUTOFF
REMOTE_LOG=$REMOTE_LOG
EOF
}

write_summary() {
  cat > "$SUMMARY_FILE" <<EOF
STATUS=SUCCESS
VERSION=$VERSION
SERVER_ID=$SERVER_ID
VM_NAME=$VM_NAME
VM_HOST=$VM_HOST
SSH_USER=$SSH_USER
SSH_PORT=$SSH_PORT
LOCAL_LOG=$LOCAL_LOG
REMOTE_LOG=$REMOTE_LOG
REMOTE_RUN_LOG=$REMOTE_RUN_LOG
CLEAN_STATE_FILE=$CLEAN_STATE_FILE
EOF
}

pre_status="$(server_status)"
LOG "server pre-clean status=$pre_status"

if [[ "$pre_status" == "SHUTOFF" ]]; then
  if [[ -f "$CLEAN_STATE_FILE" ]] && grep -q '^CLEAN_DONE=yes$' "$CLEAN_STATE_FILE"; then
    LOG "server already SHUTOFF and clean marker exists -> skip as success"
    write_summary
    LOG "DONE (already cleaned)"
    exit 0
  fi
  LOG "server is SHUTOFF but clean marker not found -> powering on first"
  openstack server start "$SERVER_ID" >/dev/null
  wait_for_server_status "ACTIVE" 300
fi

current_status="$(server_status)"
[[ "$current_status" == "ACTIVE" ]] || DIE "server must be ACTIVE before clean, got status=$current_status"
wait_for_ssh "$VM_HOST" "$SSH_PORT" 300 || DIE "SSH did not become ready on $VM_HOST:$SSH_PORT"

LOG "run final clean"
set +e
ssh_run "REMOTE_LOG_PATH='$REMOTE_LOG' BUILD_USER_HOME='$BUILD_USER_HOME' POWEROFF_WHEN_DONE='$POWEROFF_WHEN_DONE' bash -s" <<'REMOTE_EOF' | tee -a "$LOCAL_LOG" | tee "$REMOTE_RUN_LOG"
#!/usr/bin/env bash
set -Eeuo pipefail
LOG_FILE="${REMOTE_LOG_PATH:-/var/log/final-clean.log}"
BUILD_USER_HOME="${BUILD_USER_HOME:-}"
POWEROFF_WHEN_DONE="${POWEROFF_WHEN_DONE:-yes}"
log(){ printf '[remote %s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE" ; }
mkdir -p /var/log
: > "$LOG_FILE"
log "starting final clean"
log "cloud-init clean"
cloud-init clean --logs || true
rm -rf /var/lib/cloud/instances/* /var/lib/cloud/instance /var/lib/cloud/sem/* || true
log "remove cloud-init netplan"
rm -f /etc/netplan/50-cloud-init.yaml || true
log "clean machine-id"
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/dbus/machine-id || true
ln -sf /etc/machine-id /var/lib/dbus/machine-id || true
log "remove ssh host keys"
rm -f /etc/ssh/ssh_host_* || true
log "remove build-time authorized_keys"
rm -f /root/.ssh/authorized_keys || true
rm -f /var/lib/cloud/scripts/per-instance/10-root-authorized-keys.sh || true
if [[ -n "$BUILD_USER_HOME" ]]; then rm -f "$BUILD_USER_HOME/.ssh/authorized_keys" || true; fi
log "clean apt cache"
apt clean || true
rm -rf /var/lib/apt/lists/* || true
log "remove script artifacts"
rm -f /root/.bash_history || true
rm -f /home/*/.bash_history || true
rm -rf /tmp/* /var/tmp/* || true
log "clean temp and history"
history -c || true
log "validate keep file"
ls -l /var/lib/cloud/scripts/per-instance/ || true
log "sync"
sync
log "final clean done"
if [[ "$POWEROFF_WHEN_DONE" == "yes" ]]; then
  log "poweroff"
  nohup bash -c 'sleep 2; poweroff' >/dev/null 2>&1 &
fi
REMOTE_EOF
remote_ec=$?
set -e

if [[ "$remote_ec" -ne 0 ]]; then
  if [[ "$POWEROFF_WHEN_DONE" == "yes" && "$remote_ec" == "255" ]]; then
    if grep -q 'final clean done' "$REMOTE_RUN_LOG" && grep -q 'poweroff' "$REMOTE_RUN_LOG"; then
      LOG "remote SSH closed after poweroff; treating exit_code=255 as success"
    else
      DIE "remote session ended with exit_code=$remote_ec but completion markers were not both found"
    fi
  else
    DIE "remote clean failed with exit_code=$remote_ec"
  fi
fi

if [[ "$POWEROFF_WHEN_DONE" == "yes" ]]; then
  LOG "waiting for final OpenStack status SHUTOFF"
  wait_for_server_status "SHUTOFF" 300
else
  wait_for_ssh "$VM_HOST" "$SSH_PORT" 120 || DIE "SSH not available after non-poweroff clean"
fi

mark_clean_done
write_summary
LOG "DONE"
LOG "VM_HOST=$VM_HOST"
LOG "SSH_USER=$SSH_USER"
LOG "SSH_PORT=$SSH_PORT"
LOG "ROOT_LOGIN=ssh -o StrictHostKeyChecking=no -p $SSH_PORT root@$VM_HOST"
