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

# Load OpenStack settings (network, flavor, etc.)
if [[ -f "$OPENSTACK_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$OPENSTACK_ENV"
  util_log_info "Sourced openstack.env"
fi

# Source guest-access.env
if [[ -f "$GUEST_ACCESS_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$GUEST_ACCESS_ENV"
  util_log_info "Sourced guest-access.env"
else
  util_log_error "guest-access.env not found: $GUEST_ACCESS_ENV"
  util_log_error "→ Run: Settings → Edit Guest Access first"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
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
FLAVOR="${FLAVOR_ID:?FLAVOR_ID not set — run Settings → Select Resources}"
NETWORK="${NETWORK_ID:?NETWORK_ID not set — run Settings → Select Resources}"
SECGROUP="${SECURITY_GROUP:?SECURITY_GROUP not set — run Settings → Select Resources}"
VOLUME_SIZE="${VOLUME_SIZE_GB:?VOLUME_SIZE_GB not set — run Settings → Select Resources}"
VTYPE="${VOLUME_TYPE:?VOLUME_TYPE not set — run Settings → Select Resources}"
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
_CLOUD_INIT_PASSWORD="${ROOT_PASSWORD:?ROOT_PASSWORD not set in guest-access.env}"
USERDATA_FILE="$(mktemp /tmp/userdata-XXXXXX.yaml)"
trap 'rm -f "${USERDATA_FILE:-}"' EXIT

_write_userdata() {
  cat <<YAML
#cloud-config
disable_root: false
ssh_pwauth: true

chpasswd:
  expire: false
  users:
    - name: root
      password: ${_CLOUD_INIT_PASSWORD}
      type: text

YAML

  if [[ -n "${ROOT_AUTHORIZED_KEY:-}" ]]; then
    cat <<YAML
ssh_authorized_keys:
  - ${ROOT_AUTHORIZED_KEY}

YAML
  fi

  cat <<YAML
runcmd:
  - passwd -u root || true
  - chage -d -1 root || true
YAML
}
_write_userdata > "$USERDATA_FILE"
util_log_info "User data written to: $USERDATA_FILE"

# ─── Create server from volume ────────────────────────────────────────────────
util_log_info "Creating server: $VM_NAME ..."
_SERVER_CREATE_ARGS=(
  --flavor    "$FLAVOR"
  --volume    "$VOLUME_ID"
  --network   "$NETWORK"
  --security-group "$SECGROUP"
  --user-data "$USERDATA_FILE"
  --property  pipeline_stage=build
)
[[ -n "${KEY_NAME:-}" ]] && _SERVER_CREATE_ARGS+=(--key-name "$KEY_NAME")

SERVER_ID="$(openstack_cmd server create \
  "${_SERVER_CREATE_ARGS[@]}" \
  "$VM_NAME" \
  -f value -c id 2>/dev/null)"

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

# ─── Resolve login IP (Floating IP if configured) ─────────────────────────────
util_log_info "Resolving login IP..."
FIXED_IP="$GUEST_IP"
FLOATING_IP=""

if [[ -n "${FLOATING_NETWORK:-}" || -n "${EXISTING_FLOATING_IP:-}" ]]; then
  if [[ -n "${EXISTING_FLOATING_IP:-}" ]]; then
    util_log_info "Associating existing floating IP: $EXISTING_FLOATING_IP"
    openstack_cmd server add floating ip "$SERVER_ID" "$EXISTING_FLOATING_IP" 2>/dev/null || true
    FLOATING_IP="$EXISTING_FLOATING_IP"
  else
    util_log_info "Allocating floating IP from network: $FLOATING_NETWORK"
    FLOATING_IP="$(openstack_cmd floating ip create "$FLOATING_NETWORK" \
      -f value -c floating_ip_address 2>/dev/null || echo '')"
    if [[ -z "$FLOATING_IP" ]]; then
      util_log_warn "  Failed to allocate floating IP — falling back to fixed IP"
    else
      openstack_cmd server add floating ip "$SERVER_ID" "$FLOATING_IP" 2>/dev/null || true
      util_log_info "  Floating IP allocated: $FLOATING_IP"
    fi
  fi
fi

# Login IP = floating if available, else fixed
[[ -n "$FLOATING_IP" ]] && GUEST_IP="$FLOATING_IP"
util_log_info "Login IP: $GUEST_IP (fixed=$FIXED_IP floating=${FLOATING_IP:-none})"

# ─── Wait for SSH ─────────────────────────────────────────────────────────────
_SSH_PORT="${SSH_PORT:-22}"
util_require_cmd sshpass

util_log_info "Waiting for SSH at ${GUEST_IP}:${_SSH_PORT} (timeout 300s)..."
SSH_READY=false
SSH_ELAPSED=0
SSH_TIMEOUT=300
SSH_INTERVAL=10

while (( SSH_ELAPSED < SSH_TIMEOUT )); do
  if sshpass -p "$_CLOUD_INIT_PASSWORD" ssh \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=5 \
      -o PasswordAuthentication=yes \
      -p "$_SSH_PORT" \
      "root@${GUEST_IP}" \
      "echo ssh-ok" 2>/dev/null | grep -q "ssh-ok"; then
    SSH_READY=true
    util_log_info "SSH is ready at ${GUEST_IP}:${_SSH_PORT}"
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
  "fixed_ip": "${FIXED_IP}",
  "floating_ip": "${FLOATING_IP:-}",
  "ssh_ready": ${SSH_READY},
  "created_at": "${CREATED_AT}"
}
EOF
)"
state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
state_mark_ready "$PHASE" "$OS_FAMILY" "$VERSION"

util_log_info "=== create_vm DONE: $OS_FAMILY $VERSION — server=$SERVER_ID ip=$GUEST_IP ==="
