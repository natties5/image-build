#!/usr/bin/env bash
# scripts/control.sh — Single user-facing entrypoint for the image-build pipeline.
# Usage:
#   bash scripts/control.sh                                  # interactive menu
#   bash scripts/control.sh --help
#   bash scripts/control.sh sync dry-run --os ubuntu
#   bash scripts/control.sh sync dry-run --os ubuntu --version 24.04
#   bash scripts/control.sh sync download --os ubuntu --version 24.04
#   bash scripts/control.sh settings show
#   bash scripts/control.sh status dashboard
#   bash scripts/control.sh cleanup reconcile
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"

# ─── Windows: auto-add Python Scripts to PATH ─────────────────────────────────
# Needed so `openstack` and `python3` resolve correctly in Git Bash on Windows.
_setup_windows_python_path() {
  # Already have both? nothing to do
  if command -v openstack >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  # Find newest Python install under AppData/Local/Programs/Python
  local py_scripts_dir=""
  local candidate
  for candidate in \
    /c/Users/"$(whoami)"/AppData/Local/Programs/Python/Python3*/Scripts \
    /c/Users/"$(whoami)"/AppData/Local/Programs/Python/Python*/Scripts; do
    # glob expands — pick the last (newest) match that actually has openstack
    if [[ -f "${candidate}/openstack.exe" ]] || [[ -f "${candidate}/openstack" ]]; then
      py_scripts_dir="$candidate"
    fi
  done
  if [[ -n "$py_scripts_dir" ]]; then
    export PATH="${py_scripts_dir}:${PATH}"
    # Also set PYTHON3 var so pick helpers can call it directly
    local py_dir
    py_dir="$(dirname "$py_scripts_dir")"
    export PYTHON3="${py_dir}/python.exe"
  fi
}
_setup_windows_python_path

# ─── Help ─────────────────────────────────────────────────────────────────────
show_help() {
  cat <<'EOF'
image-build — Portable OpenStack Image Build Pipeline
======================================================

Usage:
  scripts/control.sh [command] [subcommand] [options]

Commands:
  (no args)                       Open interactive menu
  sync  dry-run                          Discover all OS (no download)
        dry-run --os <os>                Discover one OS
        dry-run --os <os> --version <v>  Discover one version
        download --os <os> --version <v> Download one version
        download --os <os>               Download all versions for OS
        download --all                   Download all OS, all versions
  build  import  --os <os> --version <ver>   Import base image to Glance
         create  ...                          Create VM from image
         configure ...                        Configure guest OS
         clean   ...                          Final clean + poweroff
         publish ...                          Upload final image
  settings  validate-auth         Test OpenStack auth
            show                  Show current settings
            validate              Validate all settings
  status    dashboard             Show all phase states
            logs --os <os> ...    Show logs
  cleanup   reconcile             Find and clean orphan resources
            current-run           Delete resources from last run
  --help                          Show this help

OS names: ubuntu, debian, fedora, almalinux, rocky

Examples:
  scripts/control.sh sync dry-run --os ubuntu
  scripts/control.sh sync dry-run --os debian --version 12
  scripts/control.sh sync download --os ubuntu --version 24.04
  scripts/control.sh status dashboard

EOF
}

# ─── Interactive menu ─────────────────────────────────────────────────────────
show_main_menu() {
  echo ""
  echo "========================================"
  echo "  image-build Pipeline"
  echo "========================================"
  echo "  1) Settings   — validate auth, select resources"
  echo "  2) Sync       — discover / download base images"
  echo "  3) Build      — run OpenStack pipeline"
  echo "  4) Resume     — continue from a paused run"
  echo "  5) Status     — view state, logs, manifests"
  echo "  6) Cleanup    — delete resources, reconcile"
  echo "  7) Exit"
  echo "========================================"
  echo -n "  Select [1-7]: "
}

run_interactive_menu() {
  while true; do
    show_main_menu
    local choice
    read -r choice || break
    case "$choice" in
      1) menu_settings ;;
      2) menu_sync ;;
      3) menu_build ;;
      4) menu_resume ;;
      5) menu_status ;;
      6) menu_cleanup ;;
      7) echo "Exiting."; exit 0 ;;
      *) echo "  Invalid choice: $choice" ;;
    esac
  done
}

# ─── Settings menu ────────────────────────────────────────────────────────────
menu_settings() {
  while true; do
    echo ""
    echo "--- Settings ---"
    echo "  1) Load OpenRC & Validate Auth"
    echo "  2) Select Resources"
    echo "  3) Show Current Settings"
    echo "  4) Back"
    echo -n "  Select [1-4]: "
    local choice; read -r choice || return
    case "$choice" in
      1) _settings_load_openrc ;;
      2) _settings_select_resources ;;
      3) _settings_show ;;
      4) return ;;
      *) echo "  Invalid choice." ;;
    esac
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# OPTION 1 — Load OpenRC & Validate Auth
# ──────────────────────────────────────────────────────────────────────────────
_settings_load_openrc() {
  local openrc_dir="${SETTINGS_DIR}/openrc-file"

  # Step A: scan for openrc files
  local files=()
  local f
  for f in "${openrc_dir}"/*.sh "${openrc_dir}"/*.env "${openrc_dir}"/*.rc; do
    [[ -f "$f" ]] && files+=("$f") || true
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "  ERROR: No openrc files found in settings/openrc-file/"
    echo "  Place your openrc files there and try again."
    return 1
  fi

  local selected_openrc=""
  if [[ ${#files[@]} -eq 1 ]]; then
    selected_openrc="${files[0]}"
    echo "  Auto-selected: $(basename "$selected_openrc")"
  else
    echo "  Select OpenRC profile:"
    local i=1
    for f in "${files[@]}"; do
      printf "    %d) %s\n" "$i" "$(basename "$f")"
      (( i++ )) || true
    done
    echo -n "  Select [1-${#files[@]}]: "
    local choice; read -r choice || return 1
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
      echo "  Invalid selection."; return 1
    fi
    local idx=$(( choice - 1 ))
    if [[ $idx -lt 0 ]] || [[ $idx -ge ${#files[@]} ]]; then
      echo "  Invalid selection."; return 1
    fi
    selected_openrc="${files[$idx]}"
  fi

  # Step B: source the selected file
  # Reset insecure state before loading new profile
  unset OS_INSECURE OPENSTACK_INSECURE 2>/dev/null || true
  # shellcheck disable=SC1090
  if ! source "$selected_openrc" 2>/tmp/openrc_source_err; then
    echo "  ERROR: Failed to source $(basename "$selected_openrc")"
    cat /tmp/openrc_source_err
    return 1
  fi
  # On Windows/Git Bash: OS_CACERT Linux paths don't exist — unset to use Python certifi
  if [[ -n "${OS_CACERT:-}" && ! -f "${OS_CACERT}" ]]; then
    echo "  Note: OS_CACERT path not found (${OS_CACERT}) — using default CA bundle"
    unset OS_CACERT
  fi

  # Step C: detect --insecure need (two methods)
  local insecure_detected=""

  # Method A: env var after sourcing
  if [[ "${OS_INSECURE:-}" == "true" ]]; then
    insecure_detected="env_var"
  fi

  # Method B: scan file content for OS_INSECURE string
  if grep -q 'OS_INSECURE' "$selected_openrc" 2>/dev/null; then
    if [[ -z "$insecure_detected" ]]; then
      insecure_detected="file_content"
    else
      insecure_detected="${insecure_detected}+file_content"
    fi
  fi

  if [[ -n "$insecure_detected" ]]; then
    export OS_INSECURE="true"
    echo "  Insecure detection: method(s) = ${insecure_detected} → OS_INSECURE=true"
  else
    echo "  Insecure detection: not needed"
  fi

  # Step D: validate auth
  local token_out token_err
  token_out=$(os_token_issue 2>/tmp/token_err_tmp) || true
  token_err=$(cat /tmp/token_err_tmp 2>/dev/null) || true

  local auth_ok=false
  if echo "$token_out" | grep -q 'expires' 2>/dev/null || \
     echo "$token_out" | grep -qi 'id' 2>/dev/null; then
    auth_ok=true
  fi
  # Also check exit code via subshell
  if os_token_issue >/dev/null 2>&1; then
    auth_ok=true
  fi

  local ts; ts="$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)"
  local insecure_val="false"
  [[ -n "$insecure_detected" ]] && insecure_val="true"

  if $auth_ok; then
    echo "  ✓ Auth OK"
    echo "  Profile : $(basename "$selected_openrc")"
    echo "  Project : ${OS_PROJECT_NAME:-<unknown>}"
    echo "  User    : ${OS_USERNAME:-<unknown>}"
    if [[ -n "$insecure_detected" ]]; then
      echo "  Insecure: yes (method: ${insecure_detected})"
    else
      echo "  Insecure: no"
    fi
    util_ensure_dir "${SESSION_DIR}"
    cat > "${SESSION_DIR}/active-profile.env" <<EOF
ACTIVE_OPENRC="${selected_openrc}"
ACTIVE_OPENRC_NAME="$(basename "$selected_openrc")"
ACTIVE_OPENRC_SELECTED_AT="${ts}"
OS_INSECURE="${insecure_val}"
AUTH_STATUS="ok"
EOF
  else
    echo "  ✗ Auth FAILED"
    [[ -n "$token_err" ]] && echo "  Error: ${token_err}" || echo "  Error: token issue returned no output"
    echo "  Profile : $(basename "$selected_openrc")"
    if [[ -n "$insecure_detected" ]]; then
      echo "  Insecure flag used: yes (method: ${insecure_detected})"
    else
      echo "  Insecure flag used: no"
    fi
    util_ensure_dir "${SESSION_DIR}"
    cat > "${SESSION_DIR}/active-profile.env" <<EOF
ACTIVE_OPENRC="${selected_openrc}"
ACTIVE_OPENRC_NAME="$(basename "$selected_openrc")"
ACTIVE_OPENRC_SELECTED_AT="${ts}"
OS_INSECURE="${insecure_val}"
AUTH_STATUS="failed"
EOF
    return 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# OPTION 2 — Select Resources
# ──────────────────────────────────────────────────────────────────────────────
_settings_select_resources() {
  if [[ -z "${OS_AUTH_URL:-}" ]]; then
    echo "  ERROR: No OpenRC loaded. Run option 1 first."
    return 1
  fi

  # Helper: parse JSON array from openstack_cmd, show numbered list,
  # return chosen index. Prints chosen line to stdout.
  # Usage: _pick_from_json <json_string> <col1_key> [col2_key] [col3_key]
  _os_pick_item() {
    local json="$1"; shift
    local keys=("$@")
    # Resolve Python: prefer PYTHON3 env (set by _setup_windows_python_path),
    # then python3, then python — skip Windows Store stubs (they exit 9009)
    local py_cmd="${PYTHON3:-}"
    if [[ -z "$py_cmd" ]]; then
      local _c
      for _c in python3 python; do
        if command -v "$_c" >/dev/null 2>&1; then
          # Skip Windows App Execution Alias stubs
          if "$_c" --version >/dev/null 2>&1; then
            py_cmd="$_c"; break
          fi
        fi
      done
    fi
    if [[ -z "$py_cmd" ]]; then
      echo "  ERROR: python3/python not found. Install python-openstackclient first." >&2; return 1
    fi
    local items
    items=$(PYTHONUTF8=1 PYTHONIOENCODING=utf-8 $py_cmd - "$json" "${keys[@]}" <<'PYEOF'
import sys, json, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
data = json.loads(sys.argv[1])
keys = sys.argv[2:]
for item in data:
    row = []
    for k in keys:
        # case-insensitive key lookup
        for dk in item:
            if dk.lower() == k.lower():
                row.append(str(item[dk]))
                break
        else:
            row.append("-")
    print("\t".join(row))
PYEOF
    ) || { echo "  ERROR: JSON parse failed" >&2; return 1; }
    if [[ -z "$items" ]]; then
      echo "  (no items returned)" >&2; return 1
    fi
    local lines=()
    while IFS= read -r line; do
      lines+=("$line")
    done <<< "$items"
    local i=1
    for line in "${lines[@]}"; do
      printf "    %d) %s\n" "$i" "$(echo "$line" | tr '\t' ' | ')" >&2
      (( i++ )) || true
    done
    printf "  Select [1-%d]: " "${#lines[@]}" >&2
    local choice; read -r choice || return 1
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
      echo "  Invalid selection." >&2; return 1
    fi
    local idx=$(( choice - 1 ))
    if [[ $idx -lt 0 ]] || [[ $idx -ge ${#lines[@]} ]]; then
      echo "  Invalid selection." >&2; return 1
    fi
    echo "${lines[$idx]}"
  }

  local env_out=""

  # 2a) Select Project
  echo ""
  echo "  Fetching projects..."
  local proj_json
  proj_json=$(openstack_cmd project list -f json 2>/dev/null) || proj_json="[]"
  echo "  Select Project (name | id):"
  local proj_line
  if proj_line=$(_os_pick_item "$proj_json" "Name" "ID"); then
    local proj_name proj_id
    proj_name=$(echo "$proj_line" | cut -f1)
    proj_id=$(echo "$proj_line" | cut -f2)
    env_out+="OS_PROJECT_NAME=\"${proj_name}\"\n"
    env_out+="OS_PROJECT_ID=\"${proj_id}\"\n"
    echo "  Selected project: ${proj_name} (${proj_id})"
  else
    echo "  Skipping project selection."
  fi

  # 2b) Select Network
  echo ""
  echo "  Fetching networks..."
  local net_json
  net_json=$(openstack_cmd network list -f json 2>/dev/null) || net_json="[]"
  echo "  Select Network (name | id | status):"
  local net_line
  if net_line=$(_os_pick_item "$net_json" "Name" "ID" "Status"); then
    local net_name net_id
    net_name=$(echo "$net_line" | cut -f1)
    net_id=$(echo "$net_line" | cut -f2)
    env_out+="NETWORK_ID=\"${net_id}\"\n"
    env_out+="NETWORK_NAME=\"${net_name}\"\n"
    echo "  Selected network: ${net_name} (${net_id})"
  else
    echo "  Skipping network selection."
  fi

  # 2c) Select Flavor
  echo ""
  echo "  Fetching flavors..."
  local flavor_json
  flavor_json=$(openstack_cmd flavor list -f json 2>/dev/null) || flavor_json="[]"
  echo "  Select Flavor (name | vcpus | ram | disk):"
  local flavor_line
  if flavor_line=$(_os_pick_item "$flavor_json" "Name" "VCPUs" "RAM" "Disk"); then
    local flavor_name flavor_vcpus
    flavor_name=$(echo "$flavor_line" | cut -f1)
    flavor_vcpus=$(echo "$flavor_line" | cut -f2)
    local flavor_id
    flavor_id=$(openstack_cmd flavor show "$flavor_name" -f value -c id 2>/dev/null) || flavor_id=""
    env_out+="FLAVOR_ID=\"${flavor_id}\"\n"
    env_out+="FLAVOR_NAME=\"${flavor_name}\"\n"
    echo "  Selected flavor: ${flavor_name} (${flavor_vcpus} vCPUs)"
  else
    echo "  Skipping flavor selection."
  fi

  # 2d) Select Volume Type
  echo ""
  echo "  Fetching volume types..."
  local voltype_json
  voltype_json=$(openstack_cmd volume type list -f json 2>/dev/null) || voltype_json="[]"
  echo "  Select Volume Type (name | id):"
  local voltype_line
  if voltype_line=$(_os_pick_item "$voltype_json" "Name" "ID"); then
    local voltype_name
    voltype_name=$(echo "$voltype_line" | cut -f1)
    env_out+="VOLUME_TYPE=\"${voltype_name}\"\n"
    echo "  Selected volume type: ${voltype_name}"
  else
    echo "  Skipping volume type selection."
  fi

  # 2e) Select Security Group
  echo ""
  echo "  Fetching security groups..."
  local sg_json
  sg_json=$(openstack_cmd security group list -f json 2>/dev/null) || sg_json="[]"
  echo "  Select Security Group (name | description):"
  local sg_line
  if sg_line=$(_os_pick_item "$sg_json" "Name" "Description"); then
    local sg_name
    sg_name=$(echo "$sg_line" | cut -f1)
    env_out+="SECURITY_GROUP=\"${sg_name}\"\n"
    echo "  Selected security group: ${sg_name}"
  else
    echo "  Skipping security group selection."
  fi

  # 2f) Select Floating Network (optional)
  echo ""
  echo "  Fetching external networks (for floating IP)..."
  local extnet_json
  extnet_json=$(openstack_cmd network list --external -f json 2>/dev/null) || extnet_json="[]"
  echo "  Select Floating Network (name | id):"
  echo "    0) Skip (no floating IP)"
  local extnet_line=""
  local ext_choice
  # Show list then read
  local ext_lines=()
  local py_cmd2="${PYTHON3:-}"
  [[ -z "$py_cmd2" ]] && command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1 && py_cmd2="python3"
  [[ -z "$py_cmd2" ]] && command -v python  >/dev/null 2>&1 && python  --version >/dev/null 2>&1 && py_cmd2="python"
  if [[ -n "$py_cmd2" ]]; then
    local ext_items
    ext_items=$($py_cmd2 - "$extnet_json" "Name" "ID" <<'PYEOF2'
import sys, json
data = json.loads(sys.argv[1])
keys = sys.argv[2:]
for item in data:
    row = []
    for k in keys:
        for dk in item:
            if dk.lower() == k.lower():
                row.append(str(item[dk]))
                break
        else:
            row.append("-")
    print("\t".join(row))
PYEOF2
    ) || ext_items=""
    if [[ -n "$ext_items" ]]; then
      local ei=1
      while IFS= read -r line; do
        ext_lines+=("$line")
        printf "    %d) %s\n" "$ei" "$(echo "$line" | tr '\t' ' | ')"
        (( ei++ )) || true
      done <<< "$ext_items"
    fi
  fi
  printf "  Select [0-%d]: " "${#ext_lines[@]}"
  read -r ext_choice || ext_choice="0"
  if [[ "$ext_choice" == "0" ]] || ! [[ "$ext_choice" =~ ^[0-9]+$ ]]; then
    env_out+="FLOATING_NETWORK=\"\"\n"
    echo "  Floating network: skipped"
  else
    local eidx=$(( ext_choice - 1 ))
    if [[ $eidx -ge 0 ]] && [[ $eidx -lt ${#ext_lines[@]} ]]; then
      local ext_name
      ext_name=$(echo "${ext_lines[$eidx]}" | cut -f1)
      env_out+="FLOATING_NETWORK=\"${ext_name}\"\n"
      echo "  Selected floating network: ${ext_name}"
    else
      env_out+="FLOATING_NETWORK=\"\"\n"
      echo "  Floating network: skipped"
    fi
  fi

  # Write settings/openstack.env
  util_ensure_dir "${SETTINGS_DIR}"
  printf '%b' "$env_out" > "${OPENSTACK_ENV}"
  echo ""
  echo "  ✓ Settings saved to settings/openstack.env"
}

# ──────────────────────────────────────────────────────────────────────────────
# OPTION 3 — Show Current Settings (read-only summary)
# ──────────────────────────────────────────────────────────────────────────────
_settings_show() {
  echo ""
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║       Current Settings Summary       ║"
  echo "  ╚══════════════════════════════════════╝"
  echo ""

  # OpenRC Profile section
  echo "  [ OpenRC Profile ]"
  local active_profile="none loaded"
  local selected_at="—"
  local auth_status="✗ not validated"
  local insecure_mode="no"
  local profile_file="${SESSION_DIR}/active-profile.env"
  if [[ -f "$profile_file" ]]; then
    # shellcheck disable=SC1090
    source "$profile_file" 2>/dev/null || true
    active_profile="${ACTIVE_OPENRC_NAME:-none loaded}"
    selected_at="${ACTIVE_OPENRC_SELECTED_AT:-—}"
    if [[ "${AUTH_STATUS:-}" == "ok" ]]; then
      auth_status="✓ valid"
    elif [[ "${AUTH_STATUS:-}" == "failed" ]]; then
      auth_status="✗ failed"
    fi
    [[ "${OS_INSECURE:-}" == "true" ]] && insecure_mode="yes" || insecure_mode="no"
  fi
  printf "  %-16s: %s\n" "Active Profile" "$active_profile"
  printf "  %-16s: %s\n" "Selected At" "$selected_at"
  printf "  %-16s: %s\n" "Auth Status" "$auth_status"
  printf "  %-16s: %s\n" "Insecure Mode" "$insecure_mode"
  echo ""

  # OpenStack Resources section
  echo "  [ OpenStack Resources ]"
  local proj_val net_val flavor_val voltype_val sg_val float_val
  proj_val="(not set)"; net_val="(not set)"; flavor_val="(not set)"
  voltype_val="(not set)"; sg_val="(not set)"; float_val="(not configured)"
  if [[ -f "$OPENSTACK_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$OPENSTACK_ENV" 2>/dev/null || true
    [[ -n "${OS_PROJECT_NAME:-}" ]]  && proj_val="$OS_PROJECT_NAME"
    [[ -n "${NETWORK_NAME:-}" ]]     && net_val="$NETWORK_NAME"
    [[ -n "${FLAVOR_NAME:-}" ]]      && flavor_val="$FLAVOR_NAME"
    [[ -n "${VOLUME_TYPE:-}" ]]      && voltype_val="$VOLUME_TYPE"
    [[ -n "${SECURITY_GROUP:-}" ]]   && sg_val="$SECURITY_GROUP"
    if [[ "${FLOATING_NETWORK+x}" ]]; then
      [[ -n "${FLOATING_NETWORK:-}" ]] && float_val="$FLOATING_NETWORK" || float_val="(not configured)"
    fi
  fi
  printf "  %-16s: %s\n" "Project"        "$proj_val"
  printf "  %-16s: %s\n" "Network"        "$net_val"
  printf "  %-16s: %s\n" "Flavor"         "$flavor_val"
  printf "  %-16s: %s\n" "Volume Type"    "$voltype_val"
  printf "  %-16s: %s\n" "Security Group" "$sg_val"
  printf "  %-16s: %s\n" "Floating Net"   "$float_val"
  echo ""

  # Files section
  echo "  [ Files ]"
  local _exists _missing
  _exists="exists"; _missing="missing"
  printf "  %-16s: %s\n" "openstack.env"  "$( [[ -f "$OPENSTACK_ENV" ]]      && echo "$_exists" || echo "$_missing" )"
  printf "  %-16s: %s\n" "guest-access"   "$( [[ -f "$GUEST_ACCESS_ENV" ]]   && echo "$_exists" || echo "$_missing" )"
  printf "  %-16s: %s\n" "active-profile" "$( [[ -f "$profile_file" ]]       && echo "$_exists" || echo "$_missing" )"
  echo ""
}

# Legacy aliases used by dispatch
cmd_settings_validate_auth() { _settings_load_openrc; }
cmd_settings_show()          { _settings_show; }
cmd_settings_validate() {
  util_log_info "NOT IMPLEMENTED: settings validate — see 07_MENU_DESIGN.md §1.10"
  echo "  [TODO] validate-all-settings not yet implemented."
}

# ─── Sync menu ────────────────────────────────────────────────────────────────
menu_sync() {
  echo ""
  echo "--- Sync ---"
  echo "  1) Dry-run Discover  (all OS, all tracked versions)"
  echo "  2) Dry-run Discover  (select OS)"
  echo "  3) Download          (select OS → select version)"
  echo "  4) Download          (select OS → all versions in that OS)"
  echo "  5) Download ALL      (all OS, all tracked versions)"
  echo "  6) Show Sync Results"
  echo "  7) Back"
  echo -n "  Select [1-7]: "
  local choice; read -r choice || return
  case "$choice" in
    1) _menu_sync_all_dry_run ;;
    2) _menu_sync_os_dry_run ;;
    3) _menu_sync_os_version_download ;;
    4) _menu_sync_os_all_versions_download ;;
    5) _menu_sync_all_download ;;
    6) _menu_sync_show_results ;;
    7) return ;;
    *) echo "Invalid choice." ;;
  esac
}

_menu_sync_all_dry_run() {
  local os
  for os in ubuntu debian fedora almalinux rocky; do
    echo "  --- dry-run: $os ---"
    bash "${PHASES_DIR}/sync_download.sh" --os "$os" --dry-run || true
  done
}

_menu_sync_os_dry_run() {
  local os
  os=$(_sync_select_os) || return
  bash "${PHASES_DIR}/sync_download.sh" --os "$os" --dry-run
}

_menu_sync_os_version_download() {
  local os
  os=$(_sync_select_os) || return
  local ver
  ver=$(_sync_select_version "$os") || return
  echo "  Starting download: $os $ver ..."
  echo "  (Ctrl+C to cancel download at any time)"
  bash "${PHASES_DIR}/sync_download.sh" --os "$os" --version "$ver"
}

_menu_sync_os_all_versions_download() {
  local os
  os=$(_sync_select_os) || return
  echo ""
  echo "  Versions for ${os}:"
  _sync_list_versions_for_os "$os" | while IFS= read -r line; do
    echo "    $line"
  done
  echo ""
  echo "  Will download all tracked versions for: $os"
  bash "${PHASES_DIR}/sync_download.sh" --os "$os"
}

_menu_sync_all_download() {
  echo "  Starting download: all OS, all tracked versions"
  echo "  (Ctrl+C to cancel at any time)"
  local os
  for os in ubuntu debian fedora almalinux rocky; do
    bash "${PHASES_DIR}/sync_download.sh" --os "$os" || true
  done
}

_menu_sync_show_results() {
  local files=()
  local f
  for f in "${STATE_SYNC_DIR}"/*.json; do
    [[ -f "$f" ]] && files+=("$f") || true
  done
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "  (no sync results yet — run Dry-run first)"
    return
  fi
  echo ""
  echo "=== Sync Results ==="
  printf "%-12s  %-8s  %-8s  %-10s  %-8s  %s\n" \
    "OS" "VERSION" "FORMAT" "SIZE" "HASH_OK" "STATUS"
  printf "%-12s  %-8s  %-8s  %-10s  %-8s  %s\n" \
    "──────────" "───────" "──────" "─────────" "───────" "──────────"
  for f in "${files[@]}"; do
    local base os ver fmt wspath size hash_ok status
    base="$(basename "$f" .json)"
    os=$(grep -o '"os_family"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null \
      | sed 's/.*"os_family"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1) || true
    ver=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null \
      | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1) || true
    fmt=$(grep -o '"format_selected"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null \
      | sed 's/.*"format_selected"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1) || true
    wspath=$(grep -o '"workspace_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null \
      | sed 's/.*"workspace_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1) || true
    size="-"
    if [[ -n "$wspath" && -f "$wspath" ]]; then
      size=$(du -sh "$wspath" 2>/dev/null | cut -f1) || size="-"
    fi
    if [[ -f "${STATE_SYNC_DIR}/${base}.ready" ]]; then
      status="downloaded"; hash_ok="YES"
    elif [[ -f "${STATE_SYNC_DIR}/${base}.dryrun-ok" ]]; then
      status="dry-run ok"; hash_ok="-"
    elif [[ -f "${STATE_SYNC_DIR}/${base}.failed" ]]; then
      status="failed"; hash_ok="NO"
    else
      status="pending"; hash_ok="-"
    fi
    printf "%-12s  %-8s  %-8s  %-10s  %-8s  %s\n" \
      "${os:-?}" "${ver:-?}" "${fmt:-?}" "$size" "$hash_ok" "$status"
  done
  echo ""
}

# ─── Build menu (skeleton) ────────────────────────────────────────────────────
menu_build() {
  echo ""
  echo "--- Build (not yet implemented) ---"
  echo "  Phases: import -> create -> configure -> clean -> publish"
  echo "  [TODO] see 06_OPENSTACK_PIPELINE_DESIGN.md"
  echo ""
}

# ─── Resume menu (skeleton) ───────────────────────────────────────────────────
menu_resume() {
  util_log_info "NOT IMPLEMENTED: resume — see 07_MENU_DESIGN.md §4"
  echo "  [TODO] resume not yet implemented."
}

# ─── Status menu ──────────────────────────────────────────────────────────────
menu_status() {
  echo ""
  echo "--- Status ---"
  echo "  1) Dashboard"
  echo "  2) Show Sync State"
  echo "  3) Back"
  echo -n "  Select [1-3]: "
  local choice; read -r choice || return
  case "$choice" in
    1) cmd_status_dashboard ;;
    2) cmd_status_sync ;;
    3) return ;;
    *) echo "Invalid choice." ;;
  esac
}

cmd_status_dashboard() {
  echo ""
  echo "=== Pipeline Status Dashboard ==="
  echo "Sync state files:"
  ls -1 "${STATE_SYNC_DIR}/" 2>/dev/null | sort || echo "  (none)"
  echo ""
  echo "Recent logs:"
  ls -1t "${LOG_SYNC_DIR}/" 2>/dev/null | head -5 || echo "  (none)"
  echo ""
}

cmd_status_sync() {
  echo ""
  echo "=== Sync State ==="
  local f
  for f in "${STATE_SYNC_DIR}"/*.json; do
    [[ -f "$f" ]] || continue
    echo "--- $(basename "$f") ---"
    cat "$f"
    echo ""
  done
}

# ─── Cleanup menu (skeleton) ──────────────────────────────────────────────────
menu_cleanup() {
  util_log_info "NOT IMPLEMENTED: cleanup — see 07_MENU_DESIGN.md §6"
  echo "  [TODO] cleanup not yet implemented."
}

# ─── Direct command dispatch ──────────────────────────────────────────────────
dispatch_command() {
  local domain="$1"; shift
  case "$domain" in
    sync)
      local subcmd="${1:-}"; shift || true
      case "$subcmd" in
        dry-run)
          # sync dry-run                          → dry-run all OS
          # sync dry-run --os <os>                → dry-run one OS
          # sync dry-run --os <os> --version <v>  → dry-run one version
          if [[ $# -eq 0 ]]; then
            local os
            for os in ubuntu debian fedora almalinux rocky; do
              echo "  --- dry-run: $os ---"
              bash "${PHASES_DIR}/sync_download.sh" --os "$os" --dry-run || true
            done
          else
            bash "${PHASES_DIR}/sync_download.sh" --dry-run "$@"
          fi
          ;;
        download)
          # sync download --os <os> --version <v> → download one version
          # sync download --os <os>               → download all versions in OS
          # sync download --all                   → download all OS all versions
          local _all_flag=false
          local _remaining=()
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --all) _all_flag=true; shift ;;
              *) _remaining+=("$1"); shift ;;
            esac
          done
          if $_all_flag; then
            echo "  Starting download: all OS, all tracked versions"
            local os
            for os in ubuntu debian fedora almalinux rocky; do
              bash "${PHASES_DIR}/sync_download.sh" --os "$os" || true
            done
          else
            bash "${PHASES_DIR}/sync_download.sh" "${_remaining[@]}"
          fi
          ;;
        *) util_die "Unknown sync subcommand: ${subcmd}. Try: dry-run | download" ;;
      esac
      ;;
    settings)
      local subcmd="${1:-}"; shift || true
      case "$subcmd" in
        validate-auth) _settings_load_openrc ;;
        show)          _settings_show ;;
        validate)      cmd_settings_validate ;;
        *) util_die "Unknown settings subcommand: ${subcmd}" ;;
      esac
      ;;
    status)
      local subcmd="${1:-}"; shift || true
      case "$subcmd" in
        dashboard) cmd_status_dashboard ;;
        sync)      cmd_status_sync ;;
        logs)
          util_log_info "TODO: status logs"
          echo "  [TODO] logs viewer not yet implemented."
          ;;
        *) util_die "Unknown status subcommand: ${subcmd}" ;;
      esac
      ;;
    cleanup)
      util_log_info "NOT IMPLEMENTED: cleanup — see 07_MENU_DESIGN.md §6"
      echo "  [TODO] cleanup not yet implemented."
      ;;
    build)
      util_log_info "NOT IMPLEMENTED: build — see 06_OPENSTACK_PIPELINE_DESIGN.md"
      echo "  [TODO] build pipeline not yet implemented."
      ;;
    --help|-h|help)
      show_help
      ;;
    *)
      echo "Unknown command: ${domain}. Run with --help for usage." >&2
      show_help
      exit 1
      ;;
  esac
}

# ─── Auto-load last profile on startup ────────────────────────────────────────
_autoload_profile() {
  local profile_file="${SESSION_DIR}/active-profile.env"
  [[ -f "$profile_file" ]] || return 0
  # shellcheck disable=SC1090
  source "$profile_file" 2>/dev/null || return 0
  local openrc_path="${ACTIVE_OPENRC:-}"
  [[ -n "$openrc_path" && -f "$openrc_path" ]] || return 0
  unset OS_INSECURE OPENSTACK_INSECURE 2>/dev/null || true
  # shellcheck disable=SC1090
  source "$openrc_path" 2>/dev/null || return 0
  # Fix OS_CACERT Linux path on Windows
  if [[ -n "${OS_CACERT:-}" && ! -f "${OS_CACERT}" ]]; then
    unset OS_CACERT
  fi
  echo "  [auto-loaded profile: ${ACTIVE_OPENRC_NAME:-$(basename "$openrc_path")}]"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  core_ensure_runtime_dirs
  _autoload_profile

  if [[ $# -eq 0 ]]; then
    run_interactive_menu
  else
    dispatch_command "$@"
  fi
}

main "$@"
