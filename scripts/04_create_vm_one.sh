#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

OPENSTACK_ENV_FILE="${OPENSTACK_ENV_FILE:-$REPO_ROOT/config/openstack.env}"
GUEST_ENV_FILE="${GUEST_ENV_FILE:-$REPO_ROOT/config/guest.env}"
OPENRC_PATH_FILE="${OPENRC_PATH_FILE:-$REPO_ROOT/config/openrc.path}"

[[ -f "$OPENSTACK_ENV_FILE" ]] || { echo "missing config: $OPENSTACK_ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$OPENSTACK_ENV_FILE"

[[ -f "$GUEST_ENV_FILE" ]] || { echo "missing config: $GUEST_ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$GUEST_ENV_FILE"

[[ -f "$OPENRC_PATH_FILE" ]] || { echo "missing config: $OPENRC_PATH_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$OPENRC_PATH_FILE"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <ubuntu-version>" >&2
  echo "example: $0 24.04" >&2
  exit 1
fi

PIPELINE_ROOT="${PIPELINE_ROOT:-}"
if [[ -z "$PIPELINE_ROOT" ]]; then
  PIPELINE_ROOT="$REPO_ROOT"
fi

SUMMARY_FILE="${SUMMARY_FILE:-$PIPELINE_ROOT/manifest/ubuntu/ubuntu-auto-discover-summary.tsv}"
OPENSTACK_MANIFEST_DIR="${OPENSTACK_MANIFEST_DIR:-$PIPELINE_ROOT/manifest/openstack}"
STATE_DIR="${STATE_DIR:-$PIPELINE_ROOT/runtime/state}"
LOG_DIR="${LOG_DIR:-$PIPELINE_ROOT/logs}"
OUTPUT_DIR="${OUTPUT_DIR:-$STATE_DIR}"

WAIT_SERVER_ACTIVE_SECS="${WAIT_SERVER_ACTIVE_SECS:-600}"
WAIT_VOLUME_SECS="${WAIT_VOLUME_SECS:-600}"
ROOT_USER="${ROOT_USER:-root}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"
SSH_PORT="${SSH_PORT:-22}"
ROOT_AUTHORIZED_KEY="${ROOT_AUTHORIZED_KEY:-}"

NETWORK_ID="${NETWORK_ID:-}"
FLAVOR_ID="${FLAVOR_ID:-}"
VOLUME_TYPE="${VOLUME_TYPE:-}"
VOLUME_SIZE_GB="${VOLUME_SIZE_GB:-}"
SECURITY_GROUP="${SECURITY_GROUP:-}"
KEY_NAME="${KEY_NAME:-}"
FLOATING_NETWORK="${FLOATING_NETWORK:-}"
EXISTING_FLOATING_IP="${EXISTING_FLOATING_IP:-}"
VM_NAME_TEMPLATE="${VM_NAME_TEMPLATE:-ubuntu-{version}-ci-{ts}}"
VOLUME_NAME_TEMPLATE="${VOLUME_NAME_TEMPLATE:-{vm_name}-boot}"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$OUTPUT_DIR"

LOG_FILE="$LOG_DIR/04_create_vm_one.log"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

shell_escape() {
  printf '%q' "$1"
}

trap 'die "line=$LINENO cmd=$BASH_COMMAND"' ERR

need_cmd openstack
need_cmd awk
need_cmd sed
need_cmd mktemp
need_cmd mkdir
need_cmd head

[[ -n "${OPENRC_FILE:-}" ]] || die "OPENRC_FILE is empty in $OPENRC_PATH_FILE"
[[ -f "$OPENRC_FILE" ]] || die "OPENRC_FILE not found: $OPENRC_FILE"
[[ -n "$NETWORK_ID" ]] || die "NETWORK_ID is empty"
[[ -n "$FLAVOR_ID" ]] || die "FLAVOR_ID is empty"
[[ -n "$VOLUME_TYPE" ]] || die "VOLUME_TYPE is empty"
[[ -n "$VOLUME_SIZE_GB" ]] || die "VOLUME_SIZE_GB is empty"
[[ -n "$SECURITY_GROUP" ]] || die "SECURITY_GROUP is empty"
[[ -n "$ROOT_PASSWORD" ]] || die "ROOT_PASSWORD is empty"

# shellcheck disable=SC1090
source "$OPENRC_FILE"
log "checking OpenStack auth"
openstack token issue >/dev/null

manifest_file="$OPENSTACK_MANIFEST_DIR/base-image-${VERSION}.env"
[[ -f "$manifest_file" ]] || die "base image manifest not found: $manifest_file"

# shellcheck disable=SC1090
source "$manifest_file"

IMAGE_ID="${BASE_IMAGE_ID:-}"
IMAGE_NAME="${BASE_IMAGE_NAME:-}"
[[ -n "$IMAGE_ID" ]] || die "BASE_IMAGE_ID is empty in $manifest_file"
[[ -n "$IMAGE_NAME" ]] || die "BASE_IMAGE_NAME is empty in $manifest_file"

log "checking source image id=$IMAGE_ID name=$IMAGE_NAME"
openstack image show "$IMAGE_ID" >/dev/null

ts="$(date +%Y%m%d%H%M%S)"
version_slug="${VERSION//./-}"
VM_NAME="${VM_NAME_TEMPLATE//\{version\}/$version_slug}"
VM_NAME="${VM_NAME//\{ts\}/$ts}"
VOLUME_NAME="${VOLUME_NAME_TEMPLATE//\{vm_name\}/$VM_NAME}"
OUTPUT_PREFIX="$VM_NAME"

if openstack server show "$VM_NAME" >/dev/null 2>&1; then
  die "server already exists: $VM_NAME"
fi
if openstack volume show "$VOLUME_NAME" >/dev/null 2>&1; then
  die "volume already exists: $VOLUME_NAME"
fi

OUTPUT_ENV_FILE="$OUTPUT_DIR/${OUTPUT_PREFIX}.env"
OUTPUT_TXT_FILE="$OUTPUT_DIR/${OUTPUT_PREFIX}.txt"
OUTPUT_CONFIGURE_ENV_FILE="$OUTPUT_DIR/${OUTPUT_PREFIX}.configure.env"

USER_DATA_FILE="$(mktemp /tmp/${VM_NAME}.cloudinit.XXXXXX.yaml)"
trap 'rm -f "$USER_DATA_FILE"' EXIT

{
  echo '#cloud-config'
  echo 'disable_root: false'
  echo 'ssh_pwauth: true'
  echo
  echo 'chpasswd:'
  echo '  expire: false'
  echo '  users:'
  echo '    - name: root'
  echo "      password: ${ROOT_PASSWORD}"
  echo '      type: text'
  if [[ -n "$ROOT_AUTHORIZED_KEY" ]]; then
    echo
    echo 'ssh_authorized_keys:'
    printf '  - %s\n' "$ROOT_AUTHORIZED_KEY"
  fi
  echo
  echo 'runcmd:'
  echo "  - passwd -u root || true"
  echo "  - chage -d -1 root || true"
  echo "  - sed -i 's/^#\\\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config"
  echo "  - (grep -q '^PermitRootLogin' /etc/ssh/sshd_config && sed -i 's/^#\\\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config) || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"
  echo "  - (grep -q '^PubkeyAuthentication' /etc/ssh/sshd_config && sed -i 's/^#\\\\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config) || echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config"
  echo "  - systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true"
} > "$USER_DATA_FILE"

log "creating boot volume: $VOLUME_NAME from image_id=$IMAGE_ID"
VOLUME_ID="$(openstack volume create \
  --image "$IMAGE_ID" \
  --size "$VOLUME_SIZE_GB" \
  --type "$VOLUME_TYPE" \
  -f value -c id \
  "$VOLUME_NAME")"
[[ -n "$VOLUME_ID" ]] || die "failed to create volume"

log "waiting for volume to become available"
end_ts=$(( $(date +%s) + WAIT_VOLUME_SECS ))
while true; do
  vol_status="$(openstack volume show "$VOLUME_ID" -f value -c status 2>/dev/null || true)"
  case "$vol_status" in
    available) break ;;
    error|error_restoring|error_extending|error_managing) die "volume entered bad state: $vol_status" ;;
  esac
  if (( $(date +%s) >= end_ts )); then
    die "timeout waiting for volume; last status=$vol_status"
  fi
  sleep 5
done

log "creating server: $VM_NAME"
server_create_cmd=(
  openstack server create
  --flavor "$FLAVOR_ID"
  --network "$NETWORK_ID"
  --security-group "$SECURITY_GROUP"
  --volume "$VOLUME_ID"
  --user-data "$USER_DATA_FILE"
  -f value -c id
)
if [[ -n "$KEY_NAME" ]]; then
  server_create_cmd+=( --key-name "$KEY_NAME" )
fi
server_create_cmd+=( "$VM_NAME" )

SERVER_ID="$("${server_create_cmd[@]}")"
[[ -n "$SERVER_ID" ]] || die "failed to create server"

log "waiting for server to become ACTIVE"
end_ts=$(( $(date +%s) + WAIT_SERVER_ACTIVE_SECS ))
while true; do
  srv_status="$(openstack server show "$SERVER_ID" -f value -c status 2>/dev/null || true)"
  case "$srv_status" in
    ACTIVE) break ;;
    ERROR) die "server entered ERROR state" ;;
  esac
  if (( $(date +%s) >= end_ts )); then
    die "timeout waiting for server; last status=$srv_status"
  fi
  sleep 5
done

FIXED_IP="$(openstack server show "$SERVER_ID" -f value -c addresses | sed -E 's/.*=([0-9.]+).*/\1/' | head -n1)"
FLOATING_IP=""

if [[ -n "$EXISTING_FLOATING_IP" ]]; then
  log "associating existing floating IP: $EXISTING_FLOATING_IP"
  openstack server add floating ip "$SERVER_ID" "$EXISTING_FLOATING_IP"
  FLOATING_IP="$EXISTING_FLOATING_IP"
elif [[ -n "$FLOATING_NETWORK" ]]; then
  log "creating floating IP from network: $FLOATING_NETWORK"
  FLOATING_IP="$(openstack floating ip create "$FLOATING_NETWORK" -f value -c floating_ip_address)"
  [[ -n "$FLOATING_IP" ]] || die "failed to allocate floating IP"
  log "associating floating IP: $FLOATING_IP"
  openstack server add floating ip "$SERVER_ID" "$FLOATING_IP"
fi

LOGIN_IP="$FIXED_IP"
if [[ -n "$FLOATING_IP" ]]; then
  LOGIN_IP="$FLOATING_IP"
fi

SSH_COMMAND="ssh -o StrictHostKeyChecking=no -p $SSH_PORT $ROOT_USER@$LOGIN_IP"

log "writing output files"
cat > "$OUTPUT_ENV_FILE" <<EOF_ENV
VERSION=$(shell_escape "$VERSION")
VM_NAME=$(shell_escape "$VM_NAME")
SERVER_ID=$(shell_escape "$SERVER_ID")
VOLUME_NAME=$(shell_escape "$VOLUME_NAME")
VOLUME_ID=$(shell_escape "$VOLUME_ID")
IMAGE_ID=$(shell_escape "$IMAGE_ID")
IMAGE_NAME=$(shell_escape "$IMAGE_NAME")
FIXED_IP=$(shell_escape "$FIXED_IP")
FLOATING_IP=$(shell_escape "$FLOATING_IP")
LOGIN_IP=$(shell_escape "$LOGIN_IP")
LOGIN_USER=$(shell_escape "$ROOT_USER")
LOGIN_PASSWORD=$(shell_escape "$ROOT_PASSWORD")
SSH_PORT=$(shell_escape "$SSH_PORT")
SSH_COMMAND=$(shell_escape "$SSH_COMMAND")
OUTPUT_TXT_FILE=$(shell_escape "$OUTPUT_TXT_FILE")
OUTPUT_CONFIGURE_ENV_FILE=$(shell_escape "$OUTPUT_CONFIGURE_ENV_FILE")
EOF_ENV

cat > "$OUTPUT_CONFIGURE_ENV_FILE" <<EOF_CFG
VERSION=$(shell_escape "$VERSION")
VM_HOST=$(shell_escape "$LOGIN_IP")
SSH_PORT=$(shell_escape "$SSH_PORT")
SSH_USER=$(shell_escape "$ROOT_USER")
SSH_PRIVATE_KEY=''
SSH_PASSWORD=$(shell_escape "$ROOT_PASSWORD")
ROOT_PASSWORD=$(shell_escape "$ROOT_PASSWORD")
SERVER_ID=$(shell_escape "$SERVER_ID")
VOLUME_ID=$(shell_escape "$VOLUME_ID")
IMAGE_ID=$(shell_escape "$IMAGE_ID")
VM_NAME=$(shell_escape "$VM_NAME")
VOLUME_NAME=$(shell_escape "$VOLUME_NAME")
EOF_CFG

cat > "$OUTPUT_TXT_FILE" <<EOF_TXT
CREATE VM DONE
VERSION=$VERSION
VM_NAME=$VM_NAME
SERVER_ID=$SERVER_ID
VOLUME_NAME=$VOLUME_NAME
VOLUME_ID=$VOLUME_ID
IMAGE_ID=$IMAGE_ID
IMAGE_NAME=$IMAGE_NAME
FIXED_IP=$FIXED_IP
FLOATING_IP=${FLOATING_IP:-}
LOGIN_IP=$LOGIN_IP
LOGIN_USER=$ROOT_USER
LOGIN_PASSWORD=$ROOT_PASSWORD
SSH_PORT=$SSH_PORT
SSH_COMMAND=$SSH_COMMAND
OUTPUT_ENV_FILE=$OUTPUT_ENV_FILE
OUTPUT_CONFIGURE_ENV_FILE=$OUTPUT_CONFIGURE_ENV_FILE
NOTE=cloud-init sets root password login and does not force password change on first login
EOF_TXT

cp -f "$OUTPUT_ENV_FILE" "$STATE_DIR/current.vm-${VERSION}.env"
cp -f "$OUTPUT_CONFIGURE_ENV_FILE" "$STATE_DIR/current.configure-${VERSION}.env"
cp -f "$OUTPUT_CONFIGURE_ENV_FILE" "$STATE_DIR/current.configure.env"

cat <<OUT

CREATE VM DONE
VERSION=$VERSION
VM_NAME=$VM_NAME
SERVER_ID=$SERVER_ID
VOLUME_NAME=$VOLUME_NAME
VOLUME_ID=$VOLUME_ID
IMAGE_ID=$IMAGE_ID
IMAGE_NAME=$IMAGE_NAME
FIXED_IP=$FIXED_IP
FLOATING_IP=${FLOATING_IP:-}
LOGIN_IP=$LOGIN_IP
LOGIN_USER=$ROOT_USER
LOGIN_PASSWORD=$ROOT_PASSWORD
SSH_PORT=$SSH_PORT
SSH_COMMAND=$SSH_COMMAND
OUTPUT_ENV_FILE=$OUTPUT_ENV_FILE
OUTPUT_CONFIGURE_ENV_FILE=$OUTPUT_CONFIGURE_ENV_FILE
OUTPUT_TXT_FILE=$OUTPUT_TXT_FILE
NOTE=cloud-init sets root password login and does not force password change on first login

OUT
