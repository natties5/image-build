#!/usr/bin/env bash
# phases/create_vm.sh — Create boot volume and VM from imported base image.
# Usage: bash phases/create_vm.sh --os <name> --version <ver>
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="create"

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
util_log_info "=== create_vm: $OS_FAMILY $VERSION ==="

# ─── Source openrc + openstack settings ───────────────────────────────────────
OPENRC_FILE="${ROOT_DIR}/settings/openrc-file/openrc-nutpri.sh"
if [[ -f "$OPENRC_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$OPENRC_FILE"
  util_log_info "Sourced openrc: $OPENRC_FILE"
else
  util_log_warn "openrc not found: $OPENRC_FILE (assuming environment is pre-sourced)"
fi

# Load OpenStack settings (network, flavor, etc.)
if [[ -f "$OPENSTACK_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$OPENSTACK_ENV"
  util_log_info "Sourced openstack.env"
fi

# ─── Read import state JSON ───────────────────────────────────────────────────
if ! state_is_ready "import" "$OS_FAMILY" "$VERSION"; then
  util_log_error "Import phase is not ready — run import_base.sh first"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

BASE_IMAGE_ID="$(state_read_json_field "import" "$OS_FAMILY" "$VERSION" "base_image_id")"
if [[ -z "$BASE_IMAGE_ID" ]]; then
  util_log_error "Cannot read base_image_id from import state JSON"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi
util_log_info "Base image ID: $BASE_IMAGE_ID"

# ─── Generate unique run ID / names ──────────────────────────────────────────
RUN_ID="$(date +%Y%m%d%H%M%S)"
VM_NAME="build-${OS_FAMILY}-${VERSION}-${RUN_ID}"
VOLUME_NAME="vol-${OS_FAMILY}-${VERSION}-${RUN_ID}"
util_log_info "Run ID: $RUN_ID"
util_log_info "VM name: $VM_NAME"
util_log_info "Volume name: $VOLUME_NAME"

# ─── Resolve flavor and network ───────────────────────────────────────────────
FLAVOR="${FLAVOR_NAME:-2-2-0}"
NETWORK="${NETWORK_NAME:-PUBLIC2956}"
SECGROUP="${SECURITY_GROUP:-allow-any}"
VOLUME_SIZE="${VOLUME_SIZE_GB:-10}"
VTYPE="${VOLUME_TYPE:-cinder}"
util_log_info "Flavor: $FLAVOR  Network: $NETWORK  SecGroup: $SECGROUP"
util_log_info "Volume size: ${VOLUME_SIZE}GB  Volume type: $VTYPE"

# ─── Create boot volume from base image ───────────────────────────────────────
util_log_info "Creating boot volume: $VOLUME_NAME ..."
VOLUME_ID="$(os_create_volume_from_image "$VOLUME_NAME" "$BASE_IMAGE_ID" "$VOLUME_SIZE" "$VTYPE")"

if [[ -z "$VOLUME_ID" ]]; then
  util_log_error "Volume create returned empty ID — checking if volume was created anyway..."
  VOLUME_ID="$(os_find_volume_id_by_name "$VOLUME_NAME" 2>/dev/null || echo '')"
  if [[ -z "$VOLUME_ID" ]]; then
    util_log_error "Volume creation failed: no ID found for $VOLUME_NAME"
    state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
    exit 1
  fi
  util_log_info "Found volume after create: $VOLUME_ID"
fi
util_log_info "Volume ID: $VOLUME_ID"

# Wait for volume available
util_log_info "Waiting for volume $VOLUME_ID to become available (timeout 600s)..."
if ! os_wait_volume_status "$VOLUME_ID" "available" 600 10; then
  util_log_error "Volume did not become available"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

# ─── Generate cloud-init user_data ───────────────────────────────────────────
# Ubuntu cloud images disable root/password by default — inject cloud-init to enable it
USERDATA_FILE="$(mktemp /tmp/userdata-XXXXXX.yaml)"
GUEST_PASSWORD_VAL="${GUEST_PASSWORD:-mis@Pass01}"
cat > "$USERDATA_FILE" << CLOUD_INIT
#cloud-config
chpasswd:
  list: |
    root:${GUEST_PASSWORD_VAL}
  expire: False
password: ${GUEST_PASSWORD_VAL}
ssh_pwauth: True
disable_root: false
runcmd:
  - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - systemctl restart sshd || service sshd restart || true
CLOUD_INIT
util_log_info "User data written to: $USERDATA_FILE"

# ─── Create server from volume ────────────────────────────────────────────────
util_log_info "Creating server: $VM_NAME ..."
SERVER_ID="$(openstack_cmd server create \
  --flavor "$FLAVOR" \
  --volume "$VOLUME_ID" \
  --network "$NETWORK" \
  --security-group "$SECGROUP" \
  --user-data "$USERDATA_FILE" \
  --property pipeline_stage=build \
  "$VM_NAME" \
  -f value -c id 2>/dev/null)"
rm -f "$USERDATA_FILE"

if [[ -z "$SERVER_ID" ]]; then
  util_log_error "Server create returned empty ID — checking if server was created anyway..."
  SERVER_ID="$(os_find_server_id_by_name "$VM_NAME" 2>/dev/null || echo '')"
  if [[ -z "$SERVER_ID" ]]; then
    util_log_error "Server creation failed: no ID found for $VM_NAME"
    state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
    exit 1
  fi
  util_log_info "Found server after create: $SERVER_ID"
fi
util_log_info "Server ID: $SERVER_ID"

# Wait for server ACTIVE
util_log_info "Waiting for server $SERVER_ID to become ACTIVE (timeout 600s)..."
if ! os_wait_server_status "$SERVER_ID" "ACTIVE" 600 10; then
  util_log_error "Server did not become ACTIVE"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

# ─── Get server IP ────────────────────────────────────────────────────────────
util_log_info "Getting server IP address..."
GUEST_IP=""
for attempt in 1 2 3 4 5; do
  GUEST_IP="$(os_get_server_login_ip "$SERVER_ID" 2>/dev/null || echo '')"
  if [[ -n "$GUEST_IP" ]]; then
    break
  fi
  util_log_info "Waiting for IP assignment (attempt ${attempt}/5)..."
  sleep 10
done

if [[ -z "$GUEST_IP" ]]; then
  util_log_error "Could not determine server IP address"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi
util_log_info "Guest IP: $GUEST_IP"

# ─── Wait for SSH ─────────────────────────────────────────────────────────────
util_require_cmd sshpass
GUEST_PASSWORD="${GUEST_PASSWORD:-mis@Pass01}"
GUEST_SSH_PORT="${GUEST_SSH_PORT:-22}"

util_log_info "Waiting for SSH at ${GUEST_IP}:${GUEST_SSH_PORT} (timeout 300s)..."
SSH_READY=false
SSH_ELAPSED=0
SSH_TIMEOUT=300
SSH_INTERVAL=10

while (( SSH_ELAPSED < SSH_TIMEOUT )); do
  if sshpass -p "$GUEST_PASSWORD" ssh \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=5 \
      -o PasswordAuthentication=yes \
      -p "$GUEST_SSH_PORT" \
      "root@${GUEST_IP}" \
      "echo ssh-ok" 2>/dev/null | grep -q "ssh-ok"; then
    SSH_READY=true
    util_log_info "SSH is ready at ${GUEST_IP}:${GUEST_SSH_PORT}"
    break
  fi
  if (( SSH_ELAPSED % 30 == 0 && SSH_ELAPSED > 0 )); then
    util_log_info "  waiting for SSH... elapsed=${SSH_ELAPSED}s"
  fi
  sleep "$SSH_INTERVAL"
  SSH_ELAPSED=$(( SSH_ELAPSED + SSH_INTERVAL ))
done

if [[ "$SSH_READY" != "true" ]]; then
  util_log_warn "SSH not confirmed ready after ${SSH_TIMEOUT}s — continuing anyway (network may be slow)"
  SSH_READY=false
fi

# ─── Write state JSON ─────────────────────────────────────────────────────────
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATE_JSON="$(cat <<EOF
{
  "phase": "create",
  "os_family": "${OS_FAMILY}",
  "version": "${VERSION}",
  "run_id": "${RUN_ID}",
  "vm_name": "${VM_NAME}",
  "server_id": "${SERVER_ID}",
  "volume_name": "${VOLUME_NAME}",
  "volume_id": "${VOLUME_ID}",
  "base_image_id": "${BASE_IMAGE_ID}",
  "guest_ip": "${GUEST_IP}",
  "ssh_ready": ${SSH_READY},
  "created_at": "${CREATED_AT}"
}
EOF
)"
state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
state_mark_ready "$PHASE" "$OS_FAMILY" "$VERSION"

util_log_info "=== create_vm DONE: $OS_FAMILY $VERSION — server=$SERVER_ID ip=$GUEST_IP ==="
