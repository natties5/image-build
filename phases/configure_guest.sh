#!/usr/bin/env bash
# phases/configure_guest.sh � Full guest OS configure phase driven by GUEST_* config vars.
# Usage: bash phases/configure_guest.sh --os <name> --version <ver>
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="configure"

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
util_log_info "=== configure_guest: $OS_FAMILY $VERSION ==="

# --- PHASE 0: Resolve Config --------------------------------------------------
util_log_info "--- Phase 0: Resolve Config ---"

OPENRC_FILE="${ROOT_DIR}/settings/openrc-file/openrc-nutpri.sh"
if [[ -f "$OPENRC_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$OPENRC_FILE"
  util_log_info "  Sourced openrc: $OPENRC_FILE"
else
  util_log_warn "  openrc not found: $OPENRC_FILE"
fi

if [[ -f "$GUEST_ACCESS_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$GUEST_ACCESS_ENV"
  util_log_info "  Sourced guest-access.env"
else
  util_log_warn "  guest-access.env not found: $GUEST_ACCESS_ENV"
fi

_GUEST_CFG_DEFAULT="${GUEST_CONFIG_DIR}/${OS_FAMILY}/default.env"
_GUEST_CFG_VERSION="${GUEST_CONFIG_DIR}/${OS_FAMILY}/${VERSION}.env"
if [[ -f "$_GUEST_CFG_DEFAULT" ]]; then
  # shellcheck disable=SC1090
  source "$_GUEST_CFG_DEFAULT"
  util_log_info "  Loaded default config: $_GUEST_CFG_DEFAULT"
fi
if [[ -f "$_GUEST_CFG_VERSION" ]]; then
  # shellcheck disable=SC1090
  source "$_GUEST_CFG_VERSION"
  util_log_info "  Loaded version config: $_GUEST_CFG_VERSION"
fi

_G_PORT="${SSH_PORT:-22}"
_G_USER="${SSH_USER:-root}"
_G_AUTH_MODE="${SSH_AUTH_MODE:-password}"
_G_AUTH_VAL="${ROOT_PASSWORD:-}"

if ! state_is_ready "create" "$OS_FAMILY" "$VERSION"; then
  util_log_error "Create phase is not ready -- run create_vm.sh first"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi

GUEST_IP="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "guest_ip")"
SERVER_ID="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "server_id")"
VOLUME_ID="$(state_read_json_field "create" "$OS_FAMILY" "$VERSION" "volume_id" 2>/dev/null || echo "")"

if [[ -z "$GUEST_IP" ]]; then
  util_log_error "Cannot read guest_ip from create state JSON"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
fi
util_log_info "  Guest IP: $GUEST_IP  Server: $SERVER_ID  Volume: ${VOLUME_ID:-n/a}"

_OLS_USED=false
_OLS_SKIPPED=false
_REBOOT_DONE=false
_STEPS=()

_REPO_MODE_USED="official"
_REPO_MODE_REASON="official_ok"
_OLS_ATTEMPTED=false
_OLS_REACHABLE=false
_VAULT_ATTEMPTED=false
_VAULT_REACHABLE=false
_OFFICIAL_DEGRADED=false

if ! command -v sshpass >/dev/null 2>&1; then
  util_log_info "  sshpass not found -- installing..."
  apt-get install -y sshpass >/dev/null 2>&1 || true
fi
util_require_cmd sshpass

_gssh() {
  ssh_run "$GUEST_IP" "$_G_PORT" "$_G_USER" "$_G_AUTH_MODE" "$_G_AUTH_VAL" "$@" 2>&1
}

_fail() {
  util_log_error "$1"
  state_mark_failed "$PHASE" "$OS_FAMILY" "$VERSION"
  exit 1
}

# --- PHASE 1: Guest Preflight ------------------------------------------------
util_log_info "--- Phase 1: Guest Preflight ---"
_PREFLIGHT_EXIT=0
_gssh "echo preflight-ok" >/dev/null 2>&1 || _PREFLIGHT_EXIT=$?
if [[ $_PREFLIGHT_EXIT -ne 0 ]]; then
  _fail "SSH preflight failed -- cannot connect to $GUEST_IP"
fi
util_log_info "  SSH: OK"
for _CHK in \
  "id root" \
  "cat /etc/os-release | grep VERSION_ID" \
  "which apt-get 2>/dev/null || which dnf 2>/dev/null || echo no-pkg-mgr" \
  "curl -s --max-time 5 http://1.1.1.1 -o /dev/null && echo net-ok || echo net-warn" \
  "host google.com >/dev/null 2>&1 && echo dns-ok || echo dns-warn"
do
  _OUT="$(_gssh "$_CHK" 2>&1)" || true
  util_log_info "  [preflight] $_OUT"
done
_STEPS+=("preflight")

# --- PHASE 2: Wait for cloud-init --------------------------------------------
if [[ "${GUEST_WAIT_FOR_CLOUD_INIT:-0}" == "1" ]]; then
  util_log_info "--- Phase 2: Wait for cloud-init ---"
  _CINIT_CMD="${GUEST_CLOUD_INIT_WAIT_COMMAND:-cloud-init status --wait || cloud-init status || true}"
  _CI_EXIT=0
  _CI_OUT="$(_gssh "$_CINIT_CMD")" || _CI_EXIT=$?
  util_log_info "  cloud-init: $_CI_OUT (exit=${_CI_EXIT})"
  _STEPS+=("cloud-init-wait")
else
  util_log_info "--- Phase 2: cloud-init wait skipped ---"
fi

# --- PHASE 3: Baseline Official Repo Test ------------------------------------
util_log_info "--- Phase 3: Baseline Repo Test ---"
_BL_CMD="${GUEST_REPO_BASELINE_UPDATE_COMMAND:-apt-get update}"
_BL_EXIT=0
_BL_OUT="$(_gssh "DEBIAN_FRONTEND=noninteractive $_BL_CMD" 2>&1)" || _BL_EXIT=$?
while IFS= read -r _line; do util_log_info "  [baseline] $_line"; done <<< "$_BL_OUT"
if [[ $_BL_EXIT -ne 0 ]]; then
  _OFFICIAL_DEGRADED=true
  _REPO_MODE_REASON="official_degraded"
  util_log_warn "  official repo degraded at baseline"
else
  _OFFICIAL_DEGRADED=false
  util_log_info "  official repo baseline OK"
fi
_STEPS+=("baseline-repo")

# --- PHASE 4: Repo Backup ----------------------------------------------------
util_log_info "--- Phase 4: Repo Backup ---"
_BACKUP_DIR="${GUEST_REPO_BACKUP_DIR:-/var/backups/image-build/repos}"
_BACKUP_EXIT=0
_REPO_DRIVER="${GUEST_REPO_DRIVER:-apt}"
if [[ "$_REPO_DRIVER" == "dnf-repo" ]]; then
  _BACKUP_OUT="$(_gssh "mkdir -p $_BACKUP_DIR; cp /etc/yum.repos.d/*.repo $_BACKUP_DIR/ 2>/dev/null || true; echo backup-ok" 2>&1)" || _BACKUP_EXIT=$?
else
  _BACKUP_OUT="$(_gssh "mkdir -p $_BACKUP_DIR; cp /etc/apt/sources.list $_BACKUP_DIR/ 2>/dev/null || true; cp /etc/apt/sources.list.d/*.list $_BACKUP_DIR/ 2>/dev/null || true; cp /etc/apt/sources.list.d/*.sources $_BACKUP_DIR/ 2>/dev/null || true; echo backup-ok" 2>&1)" || _BACKUP_EXIT=$?
fi
util_log_info "  [backup] $_BACKUP_OUT (exit=${_BACKUP_EXIT})"
_STEPS+=("repo-backup")

# --- PHASE 5: Repo Selection (OLS -> vault -> official-fallback) -------------
_OLS_ATTEMPTED=false
_VAULT_ATTEMPTED=false

if [[ "${GUEST_ENABLE_OLS_FAILOVER:-0}" == "1" ]]; then
  util_log_info "--- Phase 5: OLS Injection ---"
  _OLS_ATTEMPTED=true

  _OLS_URL="${GUEST_OLS_URL:-http://mirrors.openlandscape.cloud}"
  _OLS_CHECK_OUT="$(_gssh "curl -s --max-time 10 $_OLS_URL -o /dev/null && echo ols-ok || echo ols-skip" 2>&1)" || true

  if echo "$_OLS_CHECK_OUT" | grep -q "ols-ok"; then
    _OLS_REACHABLE=true
    util_log_info "  OLS reachable: $_OLS_URL"

    # Inject OLS (existing injection logic -- keep as-is)
    util_log_info "  Injecting OLS mirror: $_OLS_URL"
    if [[ "${GUEST_REPO_DRIVER:-apt}" == "dnf-repo" ]]; then
      _INJ_OUT="$(_gssh "for f in /etc/yum.repos.d/*.repo; do [ -f \"\$f\" ] || continue; sed -i 's|^mirrorlist=|#mirrorlist=|g' \"\$f\" 2>/dev/null || true; sed -i 's|^metalink=|#metalink=|g' \"\$f\" 2>/dev/null || true; sed -i \"s|^#baseurl=http://dl.rockylinux.org|baseurl=$_OLS_URL|g\" \"\$f\" 2>/dev/null || true; sed -i \"s|^#baseurl=https://dl.rockylinux.org|baseurl=$_OLS_URL|g\" \"\$f\" 2>/dev/null || true; done; echo inject-done" 2>&1)" || true
    else
      _INJ_OUT="$(_gssh "for f in /etc/apt/sources.list.d/*.sources; do [ -f \"\$f\" ] || continue; sed -i 's|URIs: http://archive.ubuntu.com/ubuntu|URIs: $_OLS_URL/ubuntu|g' \"\$f\" 2>/dev/null || true; sed -i 's|URIs: http://security.ubuntu.com/ubuntu|URIs: $_OLS_URL/ubuntu|g' \"\$f\" 2>/dev/null || true; done; if [ -f /etc/apt/sources.list ]; then sed -i 's|http://archive.ubuntu.com/ubuntu|$_OLS_URL/ubuntu|g' /etc/apt/sources.list 2>/dev/null || true; sed -i 's|http://security.ubuntu.com/ubuntu|$_OLS_URL/ubuntu|g' /etc/apt/sources.list 2>/dev/null || true; fi; echo inject-done" 2>&1)" || true
    fi
    util_log_info "  [ols-inject] $_INJ_OUT"

    # Validate OLS
    _VAL_CMD="${GUEST_REPO_VALIDATION_COMMAND:-apt-get clean && apt-get update}"
    _VAL_EXIT=0
    _VAL_OUT="$(_gssh "DEBIAN_FRONTEND=noninteractive $_VAL_CMD" 2>&1)" || _VAL_EXIT=$?
    while IFS= read -r _line; do util_log_info "  [ols-val] $_line"; done <<< "$_VAL_OUT"

    if [[ $_VAL_EXIT -eq 0 ]]; then
      util_log_info "  OLS validation OK -> using OLS"
      _REPO_MODE_USED="ols"
      _REPO_MODE_REASON="ols_ok"
      _OLS_USED=true
    else
      util_log_warn "  OLS validation FAILED (exit=$_VAL_EXIT)"
      _REPO_MODE_REASON="ols_failed"
      _OLS_USED=false
      # Rollback OLS -> restore backup (existing rollback logic -- keep as-is)
      _FAILBACK="${GUEST_REPO_FAILBACK_ACTION:-restore-backup}"
      if [[ "$_FAILBACK" == "restore-backup" ]]; then
        if [[ "${GUEST_REPO_DRIVER:-apt}" == "dnf-repo" ]]; then
          _RB_OUT="$(_gssh "cp $_BACKUP_DIR/*.repo /etc/yum.repos.d/ 2>/dev/null || true; dnf clean all; dnf -y makecache; echo rollback-done" 2>&1)" || true
        else
          _RB_OUT="$(_gssh "cp $_BACKUP_DIR/*.list /etc/apt/sources.list.d/ 2>/dev/null || true; cp $_BACKUP_DIR/*.sources /etc/apt/sources.list.d/ 2>/dev/null || true; cp $_BACKUP_DIR/sources.list /etc/apt/ 2>/dev/null || true; DEBIAN_FRONTEND=noninteractive apt-get update; echo rollback-done" 2>&1)" || true
        fi
        while IFS= read -r _line; do util_log_info "  [rollback] $_line"; done <<< "$_RB_OUT"
        util_log_info "  OLS failed -- rolled back to official repo"
      fi
      util_log_info "  OLS rolled back -- trying vault next"
    fi
  else
    util_log_info "  OLS not reachable: $_OLS_CHECK_OUT"
    _OLS_REACHABLE=false
    _REPO_MODE_REASON="ols_unreachable"
  fi
else
  util_log_info "--- Phase 5: OLS disabled ---"
fi

# -- Vault fallback (if OLS failed or unreachable) ----------------------------
if [[ "${GUEST_ENABLE_VAULT_FALLBACK:-0}" == "1" ]] && \
   [[ "$_REPO_MODE_USED" != "ols" ]]; then

  _VAULT_URL="${GUEST_VAULT_URL:-}"
  if [[ -z "$_VAULT_URL" ]]; then
    util_log_info "  vault skipped: GUEST_VAULT_URL not set"
  else
    util_log_info "--- Phase 5b: Vault Fallback ---"
    _VAULT_ATTEMPTED=true

    _VAULT_CHECK="$(_gssh "curl -s --max-time 10 $_VAULT_URL -o /dev/null && echo vault-ok || echo vault-skip" 2>&1)" || true

    if echo "$_VAULT_CHECK" | grep -q "vault-ok"; then
      _VAULT_REACHABLE=true
      util_log_info "  vault reachable: $_VAULT_URL"

      # Inject vault -- same method as OLS injection but use VAULT_URL
      if [[ "${GUEST_REPO_DRIVER:-apt}" == "dnf-repo" ]]; then
        _VINJ_OUT="$(_gssh "for f in /etc/yum.repos.d/*.repo; do [ -f \"\$f\" ] || continue; sed -i 's|^mirrorlist=|#mirrorlist=|g' \"\$f\" 2>/dev/null || true; sed -i 's|^metalink=|#metalink=|g' \"\$f\" 2>/dev/null || true; sed -i \"s|^baseurl=https://dl.rockylinux.org|baseurl=$_VAULT_URL|g\" \"\$f\" 2>/dev/null || true; sed -i \"s|^baseurl=https://repo.almalinux.org|baseurl=$_VAULT_URL|g\" \"\$f\" 2>/dev/null || true; sed -i \"s|^#baseurl=|baseurl=$_VAULT_URL/|g\" \"\$f\" 2>/dev/null || true; done; echo vault-inject-done" 2>&1)" || true
      else
        _VINJ_OUT="$(_gssh "for f in /etc/apt/sources.list.d/*.sources; do [ -f \"\$f\" ] || continue; sed -i \"s|URIs: http://archive.ubuntu.com/ubuntu|URIs: $_VAULT_URL|g\" \"\$f\" 2>/dev/null || true; sed -i \"s|URIs: http://security.ubuntu.com/ubuntu|URIs: $_VAULT_URL|g\" \"\$f\" 2>/dev/null || true; sed -i \"s|URIs: https://deb.debian.org/debian|URIs: $_VAULT_URL|g\" \"\$f\" 2>/dev/null || true; done; if [ -f /etc/apt/sources.list ]; then sed -i \"s|http://archive.ubuntu.com/ubuntu|$_VAULT_URL|g\" /etc/apt/sources.list 2>/dev/null || true; sed -i \"s|http://security.ubuntu.com/ubuntu|$_VAULT_URL|g\" /etc/apt/sources.list 2>/dev/null || true; sed -i \"s|http://deb.debian.org/debian|$_VAULT_URL|g\" /etc/apt/sources.list 2>/dev/null || true; fi; echo vault-inject-done" 2>&1)" || true
      fi
      util_log_info "  [vault-inject] $_VINJ_OUT"

      # Validate vault
      _VVAL_CMD="${GUEST_VAULT_VALIDATION_COMMAND:-${GUEST_REPO_VALIDATION_COMMAND:-apt-get clean && apt-get update}}"
      _VVAL_EXIT=0
      _VVAL_OUT="$(_gssh "DEBIAN_FRONTEND=noninteractive $_VVAL_CMD" 2>&1)" || _VVAL_EXIT=$?
      while IFS= read -r _line; do util_log_info "  [vault-val] $_line"; done <<< "$_VVAL_OUT"

      if [[ $_VVAL_EXIT -eq 0 ]]; then
        util_log_info "  vault validation OK -> using vault"
        _REPO_MODE_USED="vault"
        _REPO_MODE_REASON="ols_failed_vault_ok"
      else
        util_log_warn "  vault validation FAILED (exit=$_VVAL_EXIT)"
        _VAULT_REACHABLE=false
        _REPO_MODE_REASON="vault_failed"
        # Rollback vault -> restore backup
        _VROLLBACK="${GUEST_REPO_FAILBACK_ACTION:-restore-backup}"
        if [[ "$_VROLLBACK" == "restore-backup" ]]; then
          if [[ "${GUEST_REPO_DRIVER:-apt}" == "dnf-repo" ]]; then
            _gssh "cp $_BACKUP_DIR/*.repo /etc/yum.repos.d/ 2>/dev/null || true; dnf clean all; echo vault-rollback-done" 2>&1 || true
          else
            _gssh "cp $_BACKUP_DIR/*.list /etc/apt/sources.list.d/ 2>/dev/null || true; cp $_BACKUP_DIR/*.sources /etc/apt/sources.list.d/ 2>/dev/null || true; cp $_BACKUP_DIR/sources.list /etc/apt/ 2>/dev/null || true; apt-get clean; echo vault-rollback-done" 2>&1 || true
          fi
          util_log_info "  vault rolled back -- trying official as last resort"
        fi
      fi
    else
      util_log_warn "  vault not reachable: $_VAULT_CHECK"
      _VAULT_REACHABLE=false
      _REPO_MODE_REASON="vault_unreachable"
    fi
  fi
fi

# -- Official last resort (if OLS + vault both failed) ------------------------
if [[ "$_REPO_MODE_USED" != "ols" && "$_REPO_MODE_USED" != "vault" ]]; then
  util_log_info "--- Phase 5c: Official Repo (last resort) ---"
  _LAST_CMD="${GUEST_REPO_BASELINE_UPDATE_COMMAND:-apt-get update}"
  _LAST_EXIT=0
  _LAST_OUT="$(_gssh "DEBIAN_FRONTEND=noninteractive $_LAST_CMD" 2>&1)" || _LAST_EXIT=$?
  while IFS= read -r _line; do util_log_info "  [official-lr] $_line"; done <<< "$_LAST_OUT"

  if [[ $_LAST_EXIT -eq 0 ]]; then
    util_log_info "  official repo OK (last resort) -> continuing"
    _REPO_MODE_USED="official-fallback"
    _REPO_MODE_REASON="ols_and_vault_failed_official_ok"
  else
    util_log_warn "  ALL repo modes failed: official + OLS + vault"
    _REPO_MODE_USED="failed"
    _REPO_MODE_REASON="all_repos_failed"
    _fail "all repo modes exhausted (official + OLS + vault all failed)"
  fi
fi

util_log_info "  repo_mode_used=$_REPO_MODE_USED reason=$_REPO_MODE_REASON"
_STEPS+=("repo-selection")

# --- PHASE 6: Update / Upgrade -----------------------------------------------
util_log_info "--- Phase 6: Update / Upgrade ---"
if [[ "${GUEST_RUN_BASELINE_UPDATE:-0}" == "1" ]]; then
  _UPD_CMD="${GUEST_UPDATE_COMMAND:-apt-get update}"
  _UPD_EXIT=0
  _UPD_OUT="$(_gssh "DEBIAN_FRONTEND=noninteractive $_UPD_CMD" 2>&1)" || _UPD_EXIT=$?
  while IFS= read -r _line; do util_log_info "  [update] $_line"; done <<< "$_UPD_OUT"
  [[ $_UPD_EXIT -ne 0 ]] && _fail "Update failed (exit=$_UPD_EXIT)"
  util_log_info "  Update OK"
  _STEPS+=("update")
fi
if [[ "${GUEST_RUN_FULL_UPGRADE:-0}" == "1" ]]; then
  _UPG_CMD="${GUEST_UPGRADE_COMMAND:-DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y}"
  _UPG_EXIT=0
  _UPG_OUT="$(_gssh "DEBIAN_FRONTEND=noninteractive $_UPG_CMD" 2>&1)" || _UPG_EXIT=$?
  while IFS= read -r _line; do util_log_info "  [upgrade] $_line"; done <<< "$_UPG_OUT"
  [[ $_UPG_EXIT -ne 0 ]] && _fail "Upgrade failed (exit=$_UPG_EXIT)"
  util_log_info "  Upgrade OK"
  _STEPS+=("upgrade")
fi

# --- PHASE 7: Install Required Packages --------------------------------------
util_log_info "--- Phase 7: Install Packages ---"
if [[ -n "${GUEST_REQUIRED_PACKAGES:-}" ]]; then
  _INST_CMD="${GUEST_INSTALL_COMMAND:-DEBIAN_FRONTEND=noninteractive apt-get install -y}"
  _PKG_EXIT=0
  _PKG_OUT="$(_gssh "DEBIAN_FRONTEND=noninteractive $_INST_CMD $GUEST_REQUIRED_PACKAGES" 2>&1)" || _PKG_EXIT=$?
  while IFS= read -r _line; do util_log_info "  [pkg] $_line"; done <<< "$_PKG_OUT"
  if [[ $_PKG_EXIT -ne 0 ]] && [[ "${GUEST_FAIL_ON_PACKAGE_ERROR:-0}" == "1" ]]; then
    _fail "Package install failed (exit=$_PKG_EXIT)"
  fi
  util_log_info "  Packages exit=$_PKG_EXIT"
fi
_STEPS+=("packages")

# --- PHASE 8: Reboot ---------------------------------------------------------
if [[ "${GUEST_REBOOT_AFTER_UPGRADE:-0}" == "1" ]]; then
  util_log_info "--- Phase 8: Reboot ---"
  _gssh "shutdown -r now || reboot || true" 2>/dev/null || true
  sleep 15
  _REBOOT_TIMEOUT="${GUEST_REBOOT_TIMEOUT_SEC:-1800}"
  _REBOOT_INTERVAL=15
  _ELAPSED=0
  util_log_info "  Waiting for SSH to return (timeout ${_REBOOT_TIMEOUT}s)..."
  while [[ $_ELAPSED -lt $_REBOOT_TIMEOUT ]]; do
    sleep $_REBOOT_INTERVAL
    _ELAPSED=$(( _ELAPSED + _REBOOT_INTERVAL ))
    if ssh_run "$GUEST_IP" "$_G_PORT" "$_G_USER" "$_G_AUTH_MODE" "$_G_AUTH_VAL" "true" >/dev/null 2>&1; then
      util_log_info "  Guest SSH back after ${_ELAPSED}s"
      _REBOOT_DONE=true
      break
    fi
    util_log_info "  waiting for reboot... elapsed=${_ELAPSED}s"
  done
  if [[ "$_REBOOT_DONE" != "true" ]]; then
    _fail "Guest did not come back after reboot (timeout=${_REBOOT_TIMEOUT}s)"
  fi
  _STEPS+=("reboot")
fi

# --- PHASE 9: Locale / Timezone ----------------------------------------------
util_log_info "--- Phase 9: Locale / Timezone ---"
if [[ "${GUEST_SET_TIMEZONE:-0}" == "1" ]]; then
  _TZ="${GUEST_TIMEZONE:-Asia/Bangkok}"
  _TZ_OUT="$(_gssh "timedatectl set-timezone $_TZ 2>/dev/null || ln -sf /usr/share/zoneinfo/$_TZ /etc/localtime && echo tz-ok" 2>&1)" || true
  util_log_info "  [timezone] $_TZ_OUT"
  _STEPS+=("timezone")
fi
if [[ "${GUEST_SET_LOCALE:-0}" == "1" ]]; then
  _LOCALE_GEN="${GUEST_LOCALE_GENERATION:-en_US.UTF-8 UTF-8}"
  _LOCALE_VAL="${GUEST_LOCALE:-en_US.UTF-8}"
  _LOCALE_METHOD="${GUEST_LOCALE_METHOD:-locale-gen}"
  if [[ "$_LOCALE_METHOD" == "localectl" ]]; then
    _LOCALE_OUT="$(_gssh "localectl set-locale LANG=$_LOCALE_VAL || true; echo locale-ok" 2>&1)" || true
  else
    _LOCALE_OUT="$(_gssh "locale-gen \"$_LOCALE_GEN\" && update-locale LANG=$_LOCALE_VAL && echo locale-ok" 2>&1)" || true
  fi
  util_log_info "  [locale] $_LOCALE_OUT"
  _STEPS+=("locale")
fi

# --- PHASE 10: Disable Auto-Updates ------------------------------------------
util_log_info "--- Phase 10: Disable Auto-Updates ---"
if [[ "${GUEST_DISABLE_AUTO_UPDATES:-0}" == "1" && -n "${GUEST_DISABLE_AUTO_UPDATE_UNITS:-}" ]]; then
  _AUU_OUT="$(_gssh "systemctl disable $GUEST_DISABLE_AUTO_UPDATE_UNITS 2>/dev/null || true; systemctl stop $GUEST_DISABLE_AUTO_UPDATE_UNITS 2>/dev/null || true; echo autoupdate-disabled" 2>&1)" || true
  util_log_info "  [auto-update] $_AUU_OUT"
  _STEPS+=("disable-autoupdate")
fi

# --- PHASE 11: Disable Firewall ----------------------------------------------
util_log_info "--- Phase 11: Disable Firewall ---"
if [[ "${GUEST_DISABLE_FIREWALL:-0}" == "1" && -n "${GUEST_FIREWALL_DISABLE_UNITS:-}" ]]; then
  _FW_OUT="$(_gssh "systemctl disable $GUEST_FIREWALL_DISABLE_UNITS 2>/dev/null || true; systemctl stop $GUEST_FIREWALL_DISABLE_UNITS 2>/dev/null || true; echo firewall-disabled" 2>&1)" || true
  util_log_info "  [firewall] $_FW_OUT"
  _STEPS+=("disable-firewall")
fi

# --- PHASE 12: SSH Root Policy -----------------------------------------------
util_log_info "--- Phase 12: SSH Root Policy ---"
_SSHD_DROPIN="${GUEST_SSHD_DROPIN_FILE:-/etc/ssh/sshd_config.d/99-image-build.conf}"
_PERMIT="${GUEST_SSH_PERMIT_ROOT_LOGIN:-yes}"
_PASSAUTH="${GUEST_SSH_PASSWORD_AUTHENTICATION:-yes}"
_PUBKEY="${GUEST_SSH_PUBKEY_AUTHENTICATION:-yes}"
_KBDINT="${GUEST_SSH_KBD_INTERACTIVE_AUTHENTICATION:-no}"
_SSH_SVC="${GUEST_SSH_SERVICE:-ssh}"
_SSH_POL_EXIT=0
_SSH_POL_OUT="$(_gssh "mkdir -p \$(dirname $_SSHD_DROPIN); printf 'PermitRootLogin $_PERMIT\nPasswordAuthentication $_PASSAUTH\nPubkeyAuthentication $_PUBKEY\nKbdInteractiveAuthentication $_KBDINT\n' > $_SSHD_DROPIN; systemctl restart $_SSH_SVC 2>/dev/null || true; echo sshd-policy-ok" 2>&1)" || _SSH_POL_EXIT=$?
util_log_info "  [ssh-policy] $_SSH_POL_OUT (exit=${_SSH_POL_EXIT})"
_STEPS+=("ssh-policy")

# --- PHASE 13: Enable/Disable Services ---------------------------------------
util_log_info "--- Phase 13: Services ---"
if [[ -n "${GUEST_ENABLE_SERVICES:-}" || -n "${GUEST_DISABLE_SERVICES:-}" ]]; then
  _SVC_CMDS=""
  for _svc in ${GUEST_ENABLE_SERVICES:-}; do
    _SVC_CMDS+="systemctl enable $_svc 2>/dev/null || true; "
  done
  for _svc in ${GUEST_DISABLE_SERVICES:-}; do
    _SVC_CMDS+="systemctl disable $_svc 2>/dev/null || true; "
  done
  _SVC_OUT="$(_gssh "${_SVC_CMDS}echo services-ok" 2>&1)" || true
  util_log_info "  [services] $_SVC_OUT"
  _STEPS+=("services")
fi

# --- Write state JSON ---------------------------------------------------------
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
_STEPS_JSON="$(printf '"%s",' "${_STEPS[@]}" | sed 's/,$//')"

STATE_JSON="{
  \"phase\": \"configure\",
  \"os_family\": \"${OS_FAMILY}\",
  \"version\": \"${VERSION}\",
  \"guest_ip\": \"${GUEST_IP}\",
  \"server_id\": \"${SERVER_ID}\",
  \"config_file\": \"config/guest/${OS_FAMILY}/${VERSION}.env\",
  \"ols_used\": ${_OLS_USED},
  \"ols_skipped\": ${_OLS_SKIPPED},
  \"reboot_done\": ${_REBOOT_DONE},
  \"repo_mode_used\": \"${_REPO_MODE_USED}\",
  \"repo_mode_reason\": \"${_REPO_MODE_REASON}\",
  \"official_degraded\": ${_OFFICIAL_DEGRADED},
  \"ols_attempted\": ${_OLS_ATTEMPTED},
  \"ols_reachable\": ${_OLS_REACHABLE},
  \"vault_attempted\": ${_VAULT_ATTEMPTED},
  \"vault_reachable\": ${_VAULT_REACHABLE},
  \"steps_completed\": [${_STEPS_JSON}],
  \"status\": \"ok\",
  \"configured_at\": \"${CONFIGURED_AT}\"
}"

state_write_runtime_json "$PHASE" "$OS_FAMILY" "$VERSION" "$STATE_JSON"
state_mark_ready "$PHASE" "$OS_FAMILY" "$VERSION"
util_log_info "=== configure_guest DONE: $OS_FAMILY $VERSION ==="
