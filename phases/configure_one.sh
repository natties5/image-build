#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/local_overrides.sh"
STAGE_CONFIG_FILE="${STAGE_CONFIG_FILE:-$REPO_ROOT/config/guest/policy.env}"
LEGACY_STAGE_CONFIG_FILE="${REPO_ROOT}/config/guest/config.env"
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

# ==============================================
# CONFIG
# ใช้ได้ 2 แบบ:
# 1) แก้ค่าตรงนี้แล้วรันเลย
# 2) ส่งไฟล์ .configure.env เป็น arg:
#    ./configure_vm_phase2_stable.sh ./vm.configure.env
# ถ้าไม่ส่ง arg และในโฟลเดอร์มี *.configure.env แค่ไฟล์เดียว
# script จะอ่านให้อัตโนมัติ
# ==============================================
VM_HOST=""
SSH_PORT="22"
SSH_USER="root"
SSH_PRIVATE_KEY=""
SSH_PASSWORD=""
ROOT_PASSWORD=""

OLS_BASE_URL="http://mirrors.openlandscape.cloud/ubuntu"
OLD_RELEASES_URL="http://old-releases.ubuntu.com/ubuntu"
OFFICIAL_ARCHIVE_URL="http://archive.ubuntu.com/ubuntu"
OFFICIAL_SECURITY_URL="http://security.ubuntu.com/ubuntu"

DEFAULT_LANG="en_US.UTF-8"
EXTRA_LOCALES="th_TH.UTF-8"
TIMEZONE="Asia/Bangkok"
KERNEL_KEEP="2"
DO_UPGRADE="yes"                # yes/no
REBOOT_AFTER_UPGRADE="yes"      # yes/no
WAIT_CLOUD_INIT="yes"           # yes/no
DISABLE_AUTO_UPDATES="yes"      # yes/no
DISABLE_MOTD_NEWS="yes"         # yes/no
DISABLE_GUEST_FIREWALL="yes"    # yes/no
ROOT_SSH_PERMIT="yes"
ROOT_PASSWORD_AUTH="yes"
ROOT_PUBKEY_AUTH="yes"
ROOT_AUTHORIZED_KEY=""
# ==============================================

RUN_ID="$(date +%Y%m%d%H%M%S)"
CONFIG_FILE="$RESOLVED_CONFIG_FILE"
mkdir -p "$LOG_DIR"
if [[ -f "$STAGE_CONFIG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$STAGE_CONFIG_FILE"
  set +a
fi
if [[ -f "$LEGACY_STAGE_CONFIG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$LEGACY_STAGE_CONFIG_FILE"
  set +a
fi
imagectl_source_local_overrides "$REPO_ROOT"

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


normalize_state_host() {
  local ip=""
  ip="$(extract_first_ipv4 "${VM_HOST:-${LOGIN_IP:-}}")"
  [[ -z "$ip" ]] && return 0
  VM_HOST="$ip"
  LOGIN_IP="$ip"
  if [[ -n "${CONFIG_FILE:-}" && -f "$CONFIG_FILE" ]]; then
    sed -i "s|^VM_HOST=.*|VM_HOST=$ip|" "$CONFIG_FILE" 2>/dev/null || true
    if grep -q '^LOGIN_IP=' "$CONFIG_FILE" 2>/dev/null; then
      sed -i "s|^LOGIN_IP=.*|LOGIN_IP=$ip|" "$CONFIG_FILE" 2>/dev/null || true
    else
      printf '\nLOGIN_IP=%s\n' "$ip" >> "$CONFIG_FILE" 2>/dev/null || true
    fi
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
normalize_state_host
VM_HOST="$(extract_first_ipv4 "${VM_HOST:-}")"
LOGIN_IP="$VM_HOST"

[[ -n "$VM_HOST" ]] || { echo "VM_HOST is empty" >&2; exit 1; }
[[ -n "$SSH_USER" ]] || { echo "SSH_USER is empty" >&2; exit 1; }
[[ -n "$ROOT_PASSWORD" ]] || { echo "ROOT_PASSWORD is empty" >&2; exit 1; }
[[ -n "$SSH_PRIVATE_KEY" || -n "$SSH_PASSWORD" ]] || { echo "set SSH_PRIVATE_KEY or SSH_PASSWORD" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }
}

need_cmd ssh
need_cmd scp
if [[ -n "$SSH_PASSWORD" ]]; then
  need_cmd sshpass
fi

if [[ -n "$SSH_PRIVATE_KEY" && ! -f "$SSH_PRIVATE_KEY" ]]; then
  echo "SSH_PRIVATE_KEY not found: $SSH_PRIVATE_KEY" >&2
  exit 1
fi

LOCAL_LOG="$LOG_DIR/configure_vm_${VM_HOST}_${RUN_ID}.log"
REMOTE_LOG="/var/log/phase2-config-${RUN_ID}.log"
REMOTE_LOG_COPY="$LOG_DIR/remote_phase2_${VM_HOST}_${RUN_ID}.log"
SUMMARY_FILE="$LOG_DIR/configure_vm_${VM_HOST}_${RUN_ID}.summary.txt"
REMOTE_SCRIPT="/var/tmp/phase2_config_remote_${RUN_ID}.sh"
LOCAL_REMOTE_FILE="$(mktemp)"
REMOTE_BACKUP_DIR="/var/tmp/phase2-backup-${RUN_ID}"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOCAL_LOG"
}

cleanup_local() {
  rm -f "$LOCAL_REMOTE_FILE"
}
trap cleanup_local EXIT

write_summary() {
  cat > "$SUMMARY_FILE" <<EOS
VM_HOST=$VM_HOST
SSH_USER=$SSH_USER
SSH_PORT=$SSH_PORT
LOCAL_LOG=$LOCAL_LOG
REMOTE_LOG=$REMOTE_LOG
REMOTE_LOG_COPY=$REMOTE_LOG_COPY
SUMMARY_FILE=$SUMMARY_FILE
EOS
}

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
  -p "$SSH_PORT"
)

SCP_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
  -P "$SSH_PORT"
)

if [[ -n "$SSH_PRIVATE_KEY" ]]; then
  SSH_OPTS+=( -i "$SSH_PRIVATE_KEY" )
  SCP_OPTS+=( -i "$SSH_PRIVATE_KEY" )
fi

ssh_run() {
  if [[ -n "$SSH_PASSWORD" ]]; then
    sshpass -p "$SSH_PASSWORD" ssh "${SSH_OPTS[@]}" "$SSH_USER@$VM_HOST" "$@"
  else
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$VM_HOST" "$@"
  fi
}

scp_put() {
  local src="$1" dst="$2"
  if [[ -n "$SSH_PASSWORD" ]]; then
    sshpass -p "$SSH_PASSWORD" scp "${SCP_OPTS[@]}" "$src" "$SSH_USER@$VM_HOST:$dst"
  else
    scp "${SCP_OPTS[@]}" "$src" "$SSH_USER@$VM_HOST:$dst"
  fi
}

scp_get() {
  local src="$1" dst="$2"
  if [[ -n "$SSH_PASSWORD" ]]; then
    sshpass -p "$SSH_PASSWORD" scp "${SCP_OPTS[@]}" "$SSH_USER@$VM_HOST:$src" "$dst"
  else
    scp "${SCP_OPTS[@]}" "$SSH_USER@$VM_HOST:$src" "$dst"
  fi
}

fetch_remote_log() {
  log "trying to fetch remote log: $REMOTE_LOG"
  if scp_get "$REMOTE_LOG" "$REMOTE_LOG_COPY" >/dev/null 2>&1; then
    log "fetched remote log to: $REMOTE_LOG_COPY"
  else
    log "remote log not fetched"
  fi
}

on_error() {
  local ec="$1" line_no="$2" cmd="$3"
  log "ERROR exit_code=$ec line=$line_no cmd=$cmd"
  fetch_remote_log || true
  write_summary || true
  exit "$ec"
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

wait_ssh() {
  log "waiting for SSH on $VM_HOST:$SSH_PORT"
  for _ in $(seq 1 180); do
    if ssh_run 'echo ssh-ok' >/dev/null 2>&1; then
      log "SSH is ready"
      return 0
    fi
    sleep 5
  done
  return 1
}

cat > "$LOCAL_REMOTE_FILE" <<'REMOTE_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="$1"
REMOTE_LOG_PATH="${REMOTE_LOG_PATH:-/var/log/phase2-config.log}"
BACKUP_DIR="${BACKUP_DIR:-/var/tmp/phase2-backup}"

mkdir -p "$(dirname "$REMOTE_LOG_PATH")"
exec > >(tee -a "$REMOTE_LOG_PATH") 2>&1

log() {
  printf '[remote %s] %s\n' "$(date '+%F %T')" "$*"
}

remote_error() {
  local ec="$1" line_no="$2" cmd="$3"
  log "ERROR exit_code=$ec line=$line_no cmd=$cmd"
  log "BACKUP_DIR=$BACKUP_DIR"
  exit "$ec"
}
trap 'remote_error $? $LINENO "$BASH_COMMAND"' ERR

ensure_root() {
  if [[ $(id -u) -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "$0" "$@"
    else
      echo "sudo is required" >&2
      exit 1
    fi
  fi
}
ensure_root "$@"

with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

check_url() {
  local url="$1"
  curl -fsI --max-time 15 "$url" >/dev/null 2>&1
}

wait_cloud_init_if_needed() {
  if [[ "$WAIT_CLOUD_INIT" == "yes" ]] && command -v cloud-init >/dev/null 2>&1; then
    log "waiting for cloud-init (timeout=1200s)"
    with_timeout 1200 cloud-init status --wait || true
  fi
}

detect_os() {
  source /etc/os-release
  UBUNTU_VERSION_ID="${VERSION_ID:-}"
  UBUNTU_CODENAME="${VERSION_CODENAME:-}"
  if [[ -z "$UBUNTU_CODENAME" ]]; then
    case "$UBUNTU_VERSION_ID" in
      18.04) UBUNTU_CODENAME="bionic" ;;
      20.04) UBUNTU_CODENAME="focal" ;;
      22.04) UBUNTU_CODENAME="jammy" ;;
      24.04) UBUNTU_CODENAME="noble" ;;
      *) echo "Unsupported Ubuntu version: $UBUNTU_VERSION_ID" >&2; exit 1 ;;
    esac
  fi
  export UBUNTU_VERSION_ID UBUNTU_CODENAME
  log "detected Ubuntu $UBUNTU_VERSION_ID ($UBUNTU_CODENAME)"
}

backup_apt_sources() {
  mkdir -p "$BACKUP_DIR/apt"
  [[ -f /etc/apt/sources.list ]] && cp -a /etc/apt/sources.list "$BACKUP_DIR/apt/" || true
  [[ -d /etc/apt/sources.list.d ]] && cp -a /etc/apt/sources.list.d "$BACKUP_DIR/apt/" || true
}

choose_repo_mode() {
  local suite="$UBUNTU_CODENAME"
  local ols_ok="yes"
  for pocket in "$suite" "$suite-updates" "$suite-security" "$suite-backports"; do
    if ! check_url "$OLS_BASE_URL/dists/$pocket/InRelease" && ! check_url "$OLS_BASE_URL/dists/$pocket/Release"; then
      ols_ok="no"
      break
    fi
  done
  if [[ "$ols_ok" == "yes" ]]; then
    REPO_MODE="ols"
  else
    case "$UBUNTU_VERSION_ID" in
      18.04|20.04) REPO_MODE="old-releases" ;;
      22.04|24.04) REPO_MODE="official" ;;
      *) echo "Unsupported Ubuntu version: $UBUNTU_VERSION_ID" >&2; exit 1 ;;
    esac
  fi
  export REPO_MODE
  log "repo mode: $REPO_MODE"
}

write_apt_sources() {
  local suite="$UBUNTU_CODENAME"
  backup_apt_sources
  rm -f /etc/apt/sources.list
  mkdir -p /etc/apt/sources.list.d
  find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -delete
  case "$REPO_MODE" in
    ols)
      cat > /etc/apt/sources.list <<EOF_OLS
# primary: OLS
# fallback: handled by script if apt update fails

deb $OLS_BASE_URL $suite main restricted universe multiverse
deb $OLS_BASE_URL $suite-updates main restricted universe multiverse
deb $OLS_BASE_URL $suite-security main restricted universe multiverse
deb $OLS_BASE_URL $suite-backports main restricted universe multiverse
EOF_OLS
      ;;
    old-releases)
      cat > /etc/apt/sources.list <<EOF_OLD
# primary: old-releases

deb $OLD_RELEASES_URL $suite main restricted universe multiverse
deb $OLD_RELEASES_URL $suite-updates main restricted universe multiverse
deb $OLD_RELEASES_URL $suite-security main restricted universe multiverse
deb $OLD_RELEASES_URL $suite-backports main restricted universe multiverse
EOF_OLD
      ;;
    official)
      cat > /etc/apt/sources.list <<EOF_OFF
# primary: official

deb $OFFICIAL_ARCHIVE_URL $suite main restricted universe multiverse
deb $OFFICIAL_ARCHIVE_URL $suite-updates main restricted universe multiverse
deb $OFFICIAL_ARCHIVE_URL $suite-backports main restricted universe multiverse
deb $OFFICIAL_SECURITY_URL $suite-security main restricted universe multiverse
EOF_OFF
      ;;
    *)
      echo "Unknown REPO_MODE: $REPO_MODE" >&2
      exit 1
      ;;
  esac
}

fallback_update() {
  case "$UBUNTU_VERSION_ID" in
    18.04|20.04) REPO_MODE="old-releases" ;;
    22.04|24.04) REPO_MODE="official" ;;
  esac
  export REPO_MODE
  log "apt update failed, switching to fallback mode: $REPO_MODE"
  write_apt_sources
  DEBIAN_FRONTEND=noninteractive apt-get update
}

setup_repo_and_update() {
  choose_repo_mode
  write_apt_sources
  DEBIAN_FRONTEND=noninteractive apt-get update || fallback_update
}

configure_ssh_single_file() {
  mkdir -p "$BACKUP_DIR/ssh"
  cp -a /etc/ssh/sshd_config "$BACKUP_DIR/ssh/" || true
  cp -a /etc/ssh/sshd_config.d "$BACKUP_DIR/ssh/" || true

  ssh_supports_dropin() {
    local test_cfg test_cfg_new test_dir
    test_cfg="$(mktemp)"
    test_cfg_new="$(mktemp)"
    test_dir="$(mktemp -d)"
    cp -a /etc/ssh/sshd_config "$test_cfg"
    {
      echo "Include $test_dir/*.conf"
      cat "$test_cfg"
    } > "$test_cfg_new"
    mv -f "$test_cfg_new" "$test_cfg"
    printf 'PermitRootLogin yes\nPasswordAuthentication yes\nPubkeyAuthentication yes\n' > "$test_dir/99-phase2-root.conf"
    install -d -m 755 /run/sshd
    if sshd -t -f "$test_cfg" >/dev/null 2>&1; then
      rm -f "$test_cfg"
      rm -rf "$test_dir"
      return 0
    fi
    rm -f "$test_cfg"
    rm -rf "$test_dir"
    return 1
  }

  strip_root_auth_directives() {
    sed -ri \
      -e '/^\s*# BEGIN phase2 managed block$/,/^\s*# END phase2 managed block$/d' \
      -e 's/^\s*(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)\b/# disabled-by-phase2 &/I' \
      /etc/ssh/sshd_config
  }

  ensure_root_ssh_material() {
    echo "root:$ROOT_PASSWORD" | chpasswd

    install -d -m 700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    if [[ -n "$ROOT_AUTHORIZED_KEY" ]]; then
      grep -qxF "$ROOT_AUTHORIZED_KEY" /root/.ssh/authorized_keys || echo "$ROOT_AUTHORIZED_KEY" >> /root/.ssh/authorized_keys
    fi

    mkdir -p /var/lib/cloud/scripts/per-instance
    cat > /var/lib/cloud/scripts/per-instance/10-root-authorized-keys.sh <<'EOF_KEYS'
#!/usr/bin/env bash
set -euo pipefail
install -d -m 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
for f in /home/*/.ssh/authorized_keys; do
  [ -f "$f" ] || continue
  cat "$f" >> /root/.ssh/authorized_keys
  break
done
sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys || true
EOF_KEYS
    chmod 755 /var/lib/cloud/scripts/per-instance/10-root-authorized-keys.sh
  }

  if [[ "$UBUNTU_VERSION_ID" == "18.04" ]]; then
    SSH_CONFIG_STRATEGY="legacy-main-file"
  elif ssh_supports_dropin; then
    SSH_CONFIG_STRATEGY="dropin"
  else
    SSH_CONFIG_STRATEGY="legacy-main-file"
  fi
  export SSH_CONFIG_STRATEGY
  log "ssh config strategy: $SSH_CONFIG_STRATEGY"

  strip_root_auth_directives
  ensure_root_ssh_material

  case "$SSH_CONFIG_STRATEGY" in
    dropin)
      if ! grep -Eq '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf\s*$' /etc/ssh/sshd_config; then
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
      fi
      mkdir -p /etc/ssh/sshd_config.d
      find /etc/ssh/sshd_config.d -maxdepth 1 -type f -name '*.conf' -exec rm -f {} +
      cat > /etc/ssh/sshd_config.d/99-phase2-root.conf <<EOF_SSH
PermitRootLogin $ROOT_SSH_PERMIT
PasswordAuthentication $ROOT_PASSWORD_AUTH
PubkeyAuthentication $ROOT_PUBKEY_AUTH
EOF_SSH
      ;;
    legacy-main-file)
      sed -ri '/^\s*Include\s+\/etc\/ssh\/sshd_config\.d\/\*\.conf\s*$/d' /etc/ssh/sshd_config
      if [[ -d /etc/ssh/sshd_config.d ]]; then
        find /etc/ssh/sshd_config.d -maxdepth 1 -type f -name '*.conf' -exec rm -f {} +
      fi
      cat >> /etc/ssh/sshd_config <<EOF_SSH
# BEGIN phase2 managed block
PermitRootLogin $ROOT_SSH_PERMIT
PasswordAuthentication $ROOT_PASSWORD_AUTH
PubkeyAuthentication $ROOT_PUBKEY_AUTH
# END phase2 managed block
EOF_SSH
      ;;
    *)
      echo "Unknown SSH_CONFIG_STRATEGY: $SSH_CONFIG_STRATEGY" >&2
      exit 1
      ;;
  esac

  install -d -m 755 /run/sshd
  sshd -t
  systemctl restart ssh || systemctl restart sshd

  install -d -m 755 /run/sshd
  local sshd_effective
  sshd_effective="$(sshd -T)"
  grep -qi '^permitrootlogin yes$' <<<"$sshd_effective"
  grep -qi '^passwordauthentication yes$' <<<"$sshd_effective"
  grep -qi '^pubkeyauthentication yes$' <<<"$sshd_effective"

  case "$SSH_CONFIG_STRATEGY" in
    dropin)
      test -f /etc/ssh/sshd_config.d/99-phase2-root.conf
      ;;
    legacy-main-file)
      grep -q '^# BEGIN phase2 managed block$' /etc/ssh/sshd_config
      ;;
  esac
}

configure_locale_timezone() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y locales tzdata curl ca-certificates
  locale-gen "$DEFAULT_LANG" "$EXTRA_LOCALES" || true
  update-locale LANG="$DEFAULT_LANG" || true
  if [[ -f /etc/default/locale ]]; then
    sed -i "s/^LANG=.*/LANG=$DEFAULT_LANG/" /etc/default/locale || true
    grep -q '^LANG=' /etc/default/locale || echo "LANG=$DEFAULT_LANG" >> /etc/default/locale
  fi
  timedatectl set-timezone "$TIMEZONE" || ln -snf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

configure_cloud_init_policy() {
  mkdir -p /etc/cloud/cloud.cfg.d
  cat > /etc/cloud/cloud.cfg.d/99-phase2.cfg <<EOF_CI
preserve_hostname: false
manage_etc_hosts: true
disable_root: false
EOF_CI
}

configure_guest_policy() {
  if [[ "$DISABLE_AUTO_UPDATES" == "yes" ]]; then
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99-phase2-disable-auto-upgrades <<'EOF_AU'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF_AU
    systemctl disable --now unattended-upgrades 2>/dev/null || true
    systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
  fi

  if [[ "$DISABLE_MOTD_NEWS" == "yes" ]]; then
    if [[ -f /etc/default/motd-news ]]; then
      sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news || true
      grep -q '^ENABLED=' /etc/default/motd-news || echo 'ENABLED=0' >> /etc/default/motd-news
    else
      echo 'ENABLED=0' > /etc/default/motd-news
    fi
  fi

  if [[ "$DISABLE_GUEST_FIREWALL" == "yes" ]]; then
    systemctl disable --now ufw 2>/dev/null || true
    ufw disable 2>/dev/null || true
  fi
}

cleanup_kernels() {
  mapfile -t kernels < <(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' 2>/dev/null | sort -V || true)
  local count="${#kernels[@]}"
  log "installed kernels: $count"
  if (( count > KERNEL_KEEP )); then
    local remove_count=$((count - KERNEL_KEEP))
    local to_remove=("${kernels[@]:0:remove_count}")
    DEBIAN_FRONTEND=noninteractive apt-get purge -y "${to_remove[@]}" || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true
  else
    log "kernel cleanup not needed"
  fi
}

cleanup_success_artifacts() {
  rm -rf /root/apt-backup-* 2>/dev/null || true
  rm -rf "$BACKUP_DIR" 2>/dev/null || true
}

normalize_text() {
  local raw="${1:-}"
  raw="${raw//$'\r'/}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  printf '%s' "$raw"
}

read_current_timezone() {
  local tz=""

  tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  tz="$(normalize_text "$tz")"
  if [[ -n "$tz" ]]; then
    printf '%s' "$tz"
    return 0
  fi

  tz="$(timedatectl 2>/dev/null | awk -F': ' '/^[[:space:]]*Time zone:/ {print $2; exit}' | awk '{print $1}' || true)"
  tz="$(normalize_text "$tz")"
  if [[ -n "$tz" ]]; then
    printf '%s' "$tz"
    return 0
  fi

  if [[ -L /etc/localtime ]]; then
    tz="$(readlink /etc/localtime 2>/dev/null || true)"
    tz="$(normalize_text "$tz")"
    tz="${tz#*/usr/share/zoneinfo/}"
    if [[ -n "$tz" ]]; then
      printf '%s' "$tz"
      return 0
    fi
  fi

  printf '%s' ""
}

validate_state() {
  cloud-init status || true
  install -d -m 755 /run/sshd

  local sshd_effective
  local current_timezone expected_timezone
  sshd_effective="$(sshd -T)"
  current_timezone="$(read_current_timezone)"
  expected_timezone="$(normalize_text "$TIMEZONE")"
  grep -qi '^permitrootlogin yes$' <<<"$sshd_effective"
  grep -qi '^passwordauthentication yes$' <<<"$sshd_effective"
  grep -qi '^pubkeyauthentication yes$' <<<"$sshd_effective"
  grep -q '^LANG=en_US.UTF-8' /etc/default/locale
  [[ -n "$current_timezone" ]] || { echo "cannot detect timezone from timedatectl or /etc/localtime" >&2; exit 1; }
  test "$current_timezone" = "$expected_timezone"
  test -f /var/lib/cloud/scripts/per-instance/10-root-authorized-keys.sh

  if [[ -f /etc/ssh/sshd_config.d/99-phase2-root.conf ]]; then
    SSH_CONFIG_STRATEGY="dropin"
  else
    SSH_CONFIG_STRATEGY="legacy-main-file"
  fi
  export SSH_CONFIG_STRATEGY

  log "validation summary"
  log "ssh config strategy: $SSH_CONFIG_STRATEGY"
  log "timezone detected: $current_timezone (expected: $expected_timezone)"
  cloud-init status || true
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    find /etc/ssh/sshd_config.d -maxdepth 1 -type f -name '*.conf' -printf '%f\n' | sort || true
  fi
  grep -Ei 'permitrootlogin|passwordauthentication|pubkeyauthentication' <<<"$sshd_effective" || true
  if [[ "$SSH_CONFIG_STRATEGY" == "legacy-main-file" ]]; then
    sed -n '/^# BEGIN phase2 managed block$/,/^# END phase2 managed block$/p' /etc/ssh/sshd_config || true
  fi
  locale || true
  timedatectl | sed -n '1,8p' || true
  sed -n '1,20p' /etc/apt/sources.list || true
  ls -l /var/lib/cloud/scripts/per-instance/ || true
}

case "$PHASE" in
  pre)
    log "PHASE=pre"
    mkdir -p "$BACKUP_DIR"
    wait_cloud_init_if_needed
    detect_os
    setup_repo_and_update
    if [[ "$DO_UPGRADE" == "yes" ]]; then
      log "running apt upgrade"
      DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    fi
    configure_ssh_single_file
    configure_locale_timezone
    configure_cloud_init_policy
    configure_guest_policy
    log "pre phase done"
    ;;
  post)
    log "PHASE=post"
    wait_cloud_init_if_needed
    detect_os
    cleanup_kernels
    validate_state
    cleanup_success_artifacts
    rm -f "$0" 2>/dev/null || true
    log "post phase done"
    ;;
  *)
    echo "usage: $0 {pre|post}" >&2
    exit 1
    ;;
esac
REMOTE_EOF

log "LOCAL_LOG=$LOCAL_LOG"
log "REMOTE_LOG=$REMOTE_LOG"
log "REMOTE_LOG_COPY=$REMOTE_LOG_COPY"
log "SUMMARY_FILE=$SUMMARY_FILE"

wait_ssh
log "upload remote script"
scp_put "$LOCAL_REMOTE_FILE" "$REMOTE_SCRIPT"
ssh_run "chmod +x '$REMOTE_SCRIPT'"

remote_env_prefix=$(cat <<EOFV
REMOTE_LOG_PATH='$REMOTE_LOG' \
BACKUP_DIR='$REMOTE_BACKUP_DIR' \
WAIT_CLOUD_INIT='$WAIT_CLOUD_INIT' \
OLS_BASE_URL='$OLS_BASE_URL' \
OLD_RELEASES_URL='$OLD_RELEASES_URL' \
OFFICIAL_ARCHIVE_URL='$OFFICIAL_ARCHIVE_URL' \
OFFICIAL_SECURITY_URL='$OFFICIAL_SECURITY_URL' \
DEFAULT_LANG='$DEFAULT_LANG' \
EXTRA_LOCALES='$EXTRA_LOCALES' \
TIMEZONE='$TIMEZONE' \
KERNEL_KEEP='$KERNEL_KEEP' \
DO_UPGRADE='$DO_UPGRADE' \
DISABLE_AUTO_UPDATES='$DISABLE_AUTO_UPDATES' \
DISABLE_MOTD_NEWS='$DISABLE_MOTD_NEWS' \
DISABLE_GUEST_FIREWALL='$DISABLE_GUEST_FIREWALL' \
ROOT_SSH_PERMIT='$ROOT_SSH_PERMIT' \
ROOT_PASSWORD_AUTH='$ROOT_PASSWORD_AUTH' \
ROOT_PUBKEY_AUTH='$ROOT_PUBKEY_AUTH' \
ROOT_PASSWORD='$ROOT_PASSWORD' \
ROOT_AUTHORIZED_KEY='$ROOT_AUTHORIZED_KEY'
EOFV
)

log "run pre phase"
ssh_run "$remote_env_prefix bash '$REMOTE_SCRIPT' pre"
fetch_remote_log || true

if [[ "$DO_UPGRADE" == "yes" && "$REBOOT_AFTER_UPGRADE" == "yes" ]]; then
  log "rebooting VM"
  ssh_run 'reboot' || true
  sleep 5
  wait_ssh
  log "re-upload remote script after reboot"
  scp_put "$LOCAL_REMOTE_FILE" "$REMOTE_SCRIPT"
  ssh_run "chmod +x '$REMOTE_SCRIPT'"
else
  log "skip reboot phase"
fi

log "run post phase"
ssh_run "$remote_env_prefix bash '$REMOTE_SCRIPT' post"
fetch_remote_log || true
write_summary

cat <<EOFOUT
DONE
VM_HOST=$VM_HOST
SSH_USER=$SSH_USER
SSH_PORT=$SSH_PORT
ROOT_LOGIN=ssh -o StrictHostKeyChecking=no -p $SSH_PORT root@$VM_HOST
LOCAL_LOG=$LOCAL_LOG
REMOTE_LOG=$REMOTE_LOG
REMOTE_LOG_COPY=$REMOTE_LOG_COPY
SUMMARY_FILE=$SUMMARY_FILE
NOTE=VM is kept running for manual verification
EOFOUT
