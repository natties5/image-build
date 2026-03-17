#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
STAGE_CONFIG_FILE="${STAGE_CONFIG_FILE:-$REPO_ROOT/config/clean.env}"
STATE_DIR="${STATE_DIR:-$REPO_ROOT/runtime/state}"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"

resolve_input_arg() {
  local arg="${1:-}"
  if [[ -n "$arg" && -f "$arg" ]]; then
    printf '%s' "$arg"
    return 0
  fi
  if [[ -n "$arg" && -f "$STATE_DIR/current.configure-${arg}.env" ]]; then
    printf '%s' "$STATE_DIR/current.configure-${arg}.env"
    return 0
  fi
  if [[ -n "$arg" && -f "$STATE_DIR/${arg}.configure.env" ]]; then
    printf '%s' "$STATE_DIR/${arg}.configure.env"
    return 0
  fi
  if [[ -f "$STATE_DIR/current.configure.env" ]]; then
    printf '%s' "$STATE_DIR/current.configure.env"
    return 0
  fi
  printf ''
}

CONFIG_ARG_RAW="${1:-}"
RESOLVED_CONFIG_FILE="$(resolve_input_arg "$CONFIG_ARG_RAW")"

# =========================================
# FINAL CLEAN REMOTE
# รันจาก jump host
# ใช้ได้ 2 แบบ:
# 1) แก้ค่าตรงนี้
# 2) ส่ง .configure.env เป็น arg:
#    ./final_clean_remote.sh ./vm.configure.env
# =========================================
VM_HOST=""
SSH_PORT="22"
SSH_USER="root"
SSH_PRIVATE_KEY=""
SSH_PASSWORD=""
BUILD_USER_HOME=""            # example: /home/ubuntu
POWEROFF_WHEN_DONE="yes"      # yes/no
# =========================================

RUN_ID="$(date +%Y%m%d%H%M%S)"
CONFIG_FILE="$RESOLVED_CONFIG_FILE"
mkdir -p "$LOG_DIR"
if [[ -f "$STAGE_CONFIG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$STAGE_CONFIG_FILE"
  set +a
fi

load_config_file() {
  local cfg="${1:-}"
  if [[ -n "$cfg" && -f "$cfg" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$cfg"
    set +a
    return 0
  fi

  if [[ -z "$cfg" ]]; then
    local matches=()
    shopt -s nullglob
    matches=(./*.configure.env)
    shopt -u nullglob
    if [[ ${#matches[@]} -eq 1 ]]; then
      set -a
      # shellcheck disable=SC1090
      source "${matches[0]}"
      set +a
    fi
  fi
}

extract_first_ipv4() {
  local s="${1:-}"
  if [[ "$s" =~ ([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' <<<"$s" | head -n1
  else
    printf '%s' "$s"
  fi
}

if [[ -z "$CONFIG_FILE" ]]; then
  echo "usage: $0 <ubuntu-version | path-to-.configure.env>" >&2
  echo "example: $0 24.04" >&2
  exit 1
fi

load_config_file "$CONFIG_FILE"

if [[ -n "${LOGIN_IP:-}" && -z "${VM_HOST:-}" ]]; then
  VM_HOST="$LOGIN_IP"
fi
VM_HOST="$(extract_first_ipv4 "${VM_HOST:-}")"

[[ -n "$VM_HOST" ]] || { echo "VM_HOST is empty" >&2; exit 1; }
[[ -n "$SSH_USER" ]] || { echo "SSH_USER is empty" >&2; exit 1; }
[[ -n "$SSH_PRIVATE_KEY" || -n "$SSH_PASSWORD" ]] || { echo "set SSH_PRIVATE_KEY or SSH_PASSWORD" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }
}

need_cmd ssh
if [[ -n "$SSH_PASSWORD" ]]; then
  need_cmd sshpass
fi

if [[ -n "$SSH_PRIVATE_KEY" && ! -f "$SSH_PRIVATE_KEY" ]]; then
  echo "SSH_PRIVATE_KEY not found: $SSH_PRIVATE_KEY" >&2
  exit 1
fi

LOCAL_LOG="$LOG_DIR/final_clean_${VM_HOST}_${RUN_ID}.log"
SUMMARY_FILE="$LOG_DIR/final_clean_${VM_HOST}_${RUN_ID}.summary.txt"
REMOTE_LOG="/var/log/final-clean-${RUN_ID}.log"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOCAL_LOG"
}

write_summary() {
  cat > "$SUMMARY_FILE" <<EOS
VM_HOST=$VM_HOST
SSH_USER=$SSH_USER
SSH_PORT=$SSH_PORT
LOCAL_LOG=$LOCAL_LOG
SUMMARY_FILE=$SUMMARY_FILE
REMOTE_LOG=$REMOTE_LOG
POWEROFF_WHEN_DONE=$POWEROFF_WHEN_DONE
EOS
}

on_error() {
  local ec="$1" line_no="$2" cmd="$3"
  log "ERROR exit_code=$ec line=$line_no cmd=$cmd"
  write_summary || true
  exit "$ec"
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
  -p "$SSH_PORT"
)
if [[ -n "$SSH_PRIVATE_KEY" ]]; then
  SSH_OPTS+=( -i "$SSH_PRIVATE_KEY" )
fi

ssh_run() {
  if [[ -n "$SSH_PASSWORD" ]]; then
    sshpass -p "$SSH_PASSWORD" ssh "${SSH_OPTS[@]}" "$SSH_USER@$VM_HOST" "$@"
  else
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$VM_HOST" "$@"
  fi
}

wait_ssh() {
  log "waiting for SSH on $VM_HOST:$SSH_PORT"
  for _ in $(seq 1 120); do
    if ssh_run 'echo ssh-ok' >/dev/null 2>&1; then
      log "SSH is ready"
      return 0
    fi
    sleep 5
  done
  return 1
}

log "LOCAL_LOG=$LOCAL_LOG"
log "SUMMARY_FILE=$SUMMARY_FILE"
log "REMOTE_LOG=$REMOTE_LOG"

wait_ssh

log "run final clean"
ssh_run \
  "REMOTE_LOG_PATH='$REMOTE_LOG' BUILD_USER_HOME='$BUILD_USER_HOME' POWEROFF_WHEN_DONE='$POWEROFF_WHEN_DONE' bash -s" <<'REMOTE_EOF' | tee -a "$LOCAL_LOG"
#!/usr/bin/env bash
set -Eeuo pipefail

PER_INSTANCE_DIR="/var/lib/cloud/scripts/per-instance"
REMOTE_LOG_PATH="${REMOTE_LOG_PATH:-/var/log/final-clean.log}"
BUILD_USER_HOME="${BUILD_USER_HOME:-}"
POWEROFF_WHEN_DONE="${POWEROFF_WHEN_DONE:-yes}"

mkdir -p "$(dirname "$REMOTE_LOG_PATH")"
exec > >(tee -a "$REMOTE_LOG_PATH") 2>&1

log() {
  printf '[remote %s] %s\n' "$(date '+%F %T')" "$*"
}

need_root() {
  if [[ $(id -u) -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "$0" "$@"
    else
      echo "run as root or with sudo" >&2
      exit 1
    fi
  fi
}
need_root "$@"

remote_error() {
  local ec="$1" line_no="$2" cmd="$3"
  log "ERROR exit_code=$ec line=$line_no cmd=$cmd"
  exit "$ec"
}
trap 'remote_error $? $LINENO "$BASH_COMMAND"' ERR

log "starting final clean"

# 1) cloud-init state
if command -v cloud-init >/dev/null 2>&1; then
  log "cloud-init clean"
  cloud-init clean --logs || true
fi
rm -rf /var/lib/cloud/instance || true
rm -rf /var/lib/cloud/instances || true
mkdir -p "$PER_INSTANCE_DIR"

# 2) network instance state
log "remove cloud-init netplan"
rm -f /etc/netplan/50-cloud-init.yaml || true

# 3) machine identity
log "clean machine-id"
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/dbus/machine-id || true

# 4) ssh host keys
log "remove ssh host keys"
rm -f /etc/ssh/ssh_host_* || true

# 5) build-time authorized_keys
log "remove build-time authorized_keys"
rm -f /root/.ssh/authorized_keys || true
if [[ -n "$BUILD_USER_HOME" && -d "$BUILD_USER_HOME" ]]; then
  rm -f "$BUILD_USER_HOME/.ssh/authorized_keys" || true
fi

# 6) package cache
log "clean apt cache"
apt clean || true
rm -rf /var/cache/apt/archives/* || true
DEBIAN_FRONTEND=noninteractive apt autoremove -y || true

# 7) script artifacts / backups
log "remove script artifacts"
rm -rf /root/apt-backup-* || true
rm -f /var/log/phase2-config-*.log || true
rm -f /tmp/phase2_config_remote_*.sh || true
rm -f /var/tmp/phase2_config_remote_*.sh || true
rm -rf /var/tmp/phase2-backup-* || true

# 8) temp / history
log "clean temp and history"
rm -f /root/.bash_history || true
find /tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
find /var/tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

# 9) validate
log "validate keep file"
test -d "$PER_INSTANCE_DIR"
ls -l "$PER_INSTANCE_DIR" || true

log "sync"
sync

log "final clean done"

if [[ "$POWEROFF_WHEN_DONE" == "yes" ]]; then
  log "poweroff"
  poweroff
fi
REMOTE_EOF

write_summary
log "DONE"
log "VM_HOST=$VM_HOST"
log "ROOT_LOGIN=ssh -o StrictHostKeyChecking=no -p $SSH_PORT root@$VM_HOST"