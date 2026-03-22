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
    echo "  3) Edit Guest Access"
    echo "  4) Show Current Settings"
    echo "  5) Back"
    echo -n "  Select [1-5]: "
    local choice; read -r choice || return
    case "$choice" in
      1) _settings_load_openrc ;;
      2) _settings_select_resources ;;
      3) _settings_edit_guest_access ;;
      4) _settings_show ;;
      5) return ;;
      *) echo "  Invalid choice." ;;
    esac
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# Auto-select openrc by environment (Linux=internalURL, other=publicURL)
# Returns path via printf; returns 1 if cannot auto-select (fall back to list).
# ──────────────────────────────────────────────────────────────────────────────
_auto_select_openrc() {
  local openrc_dir="$1"
  local files=()
  local f
  for f in "${openrc_dir}"/*.sh "${openrc_dir}"/*.env "${openrc_dir}"/*.rc; do
    [[ -f "$f" ]] && files+=("$f") || true
  done

  local count="${#files[@]}"
  [[ "$count" -eq 0 ]] && return 1

  # Only 1 file → use it regardless
  if [[ "$count" -eq 1 ]]; then
    printf '%s' "${files[0]}"
    return 0
  fi

  # Multiple files → detect environment
  local is_linux=false
  [[ "$(uname -s)" == "Linux" ]] && is_linux=true

  local preferred=""
  for f in "${files[@]}"; do
    local content
    content=$(grep -v 'PASSWORD\|SECRET' "$f" 2>/dev/null || true)
    if $is_linux && echo "$content" | grep -qi 'internalURL\|internal'; then
      preferred="$f"
      break
    elif ! $is_linux && ! echo "$content" | grep -qi 'internalURL\|internal'; then
      preferred="$f"
      break
    fi
  done

  if [[ -n "$preferred" ]]; then
    printf '%s' "$preferred"
    return 0
  fi

  return 1
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
    # Find suggested default via environment detection (shown as hint, not forced)
    local auto_path default_idx=0
    auto_path=$(_auto_select_openrc "$openrc_dir") || true

    echo "  Select OpenRC profile:"
    local i=1
    for f in "${files[@]}"; do
      local hint=""
      [[ -n "$auto_path" && "$f" == "$auto_path" ]] && hint=" (suggested)"
      printf "    %d) %s%s\n" "$i" "$(basename "$f")" "$hint"
      [[ -n "$auto_path" && "$f" == "$auto_path" ]] && default_idx=$i
      (( i++ )) || true
    done
    if [[ "$default_idx" -gt 0 ]]; then
      echo -n "  Select [1-${#files[@]}] (Enter = ${default_idx}): "
    else
      echo -n "  Select [1-${#files[@]}]: "
    fi
    local choice; read -r choice || return 1
    if [[ -z "$choice" ]] && [[ "$default_idx" -gt 0 ]]; then
      choice="$default_idx"
    fi
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

  # Detect working Python once — avoids Windows MS Store stub triggering installer
  local PYTHON3
  PYTHON3=$(_detect_python)

  # Print a reference table from a JSON array using python.
  # Usage: _print_ref_table <json> <Header1> [Header2 ...]
  _print_ref_table() {
    local json="$1"; shift
    if [[ -z "$PYTHON3" ]]; then
      echo "  (python not available — cannot display table)"
      return
    fi
    PYTHONUTF8=1 PYTHONIOENCODING=utf-8 "$PYTHON3" - "$json" "$@" <<'PYEOF'
import sys, json, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
data = json.loads(sys.argv[1])
keys = sys.argv[2:]
widths = [len(k) for k in keys]
rows = []
for item in data:
    row = []
    for k in keys:
        val = "-"
        for dk in item:
            if dk.lower() == k.lower():
                val = str(item[dk])
                break
        row.append(val)
    rows.append(row)
    for i, v in enumerate(row):
        widths[i] = max(widths[i], len(v))
sep = "  " + "─" * (sum(widths) + 3 * max(len(keys) - 1, 0) + 4)
hdr = "  " + "  ".join(k.ljust(widths[i]) for i, k in enumerate(keys))
print(sep)
print(hdr)
print(sep)
for row in rows:
    print("  " + "  ".join(v.ljust(widths[i]) for i, v in enumerate(row)))
print(sep)
PYEOF
  }

  # Look up a field value from a JSON array given an input string (name or ID).
  # Usage: _json_lookup <json> <input> <search_key> <return_key>
  _json_lookup() {
    local json="$1" input="$2" skey="$3" rkey="$4"
    [[ -z "$PYTHON3" ]] && { printf ''; return; }
    PYTHONUTF8=1 PYTHONIOENCODING=utf-8 "$PYTHON3" - "$json" "$input" "$skey" "$rkey" <<'PYEOF'
import sys, json
data = json.loads(sys.argv[1])
inp, skey, rkey = sys.argv[2], sys.argv[3], sys.argv[4]
for item in data:
    for dk in item:
        if dk.lower() == skey.lower():
            val = str(item[dk])
            if val == inp or val.lower() == inp.lower():
                for rdk in item:
                    if rdk.lower() == rkey.lower():
                        print(str(item[rdk]))
                        sys.exit(0)
print("")
PYEOF
  }

  # Check if input matches any value in a JSON array. Returns 0 if found.
  _json_has_item() {
    local json="$1" input="$2"
    [[ -z "$PYTHON3" ]] && return 1
    local result
    result=$(PYTHONUTF8=1 PYTHONIOENCODING=utf-8 "$PYTHON3" - "$json" "$input" <<'PYEOF'
import sys, json
data = json.loads(sys.argv[1])
inp = sys.argv[2]
for item in data:
    for dk in item:
        val = str(item[dk])
        if val == inp or val.lower() == inp.lower():
            print("found")
            sys.exit(0)
print("notfound")
PYEOF
    ) || result="notfound"
    [[ "$result" == "found" ]]
  }

  # Load current saved values so empty Enter keeps them unchanged
  local cur_proj_name="" cur_proj_id="" cur_net_name="" cur_net_id=""
  local cur_flavor_name="" cur_flavor_id="" cur_volume_type=""
  local cur_sg="" cur_float_net="" cur_float_net_id="" cur_key_name=""
  if [[ -f "$OPENSTACK_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$OPENSTACK_ENV" 2>/dev/null || true
    cur_proj_name="${OS_PROJECT_NAME:-}"
    cur_proj_id="${OS_PROJECT_ID:-}"
    cur_net_name="${NETWORK_NAME:-}"
    cur_net_id="${NETWORK_ID:-}"
    cur_flavor_name="${FLAVOR_NAME:-}"
    cur_flavor_id="${FLAVOR_ID:-}"
    cur_volume_type="${VOLUME_TYPE:-}"
    cur_sg="${SECURITY_GROUP:-}"
    cur_float_net="${FLOATING_NETWORK:-}"
    cur_float_net_id="${FLOATING_NETWORK_ID:-}"
    cur_key_name="${KEY_NAME:-}"
  fi

  local env_out=""

  # ── 2a) Project ──────────────────────────────────────────────────────────────
  echo ""
  echo "  Fetching projects..."
  local proj_json
  proj_json=$(openstack_cmd project list -f json 2>/dev/null) || proj_json="[]"
  echo ""
  echo "  Available projects:"
  _print_ref_table "$proj_json" "Name" "ID"
  echo ""
  if [[ -n "$cur_proj_name" ]]; then
    printf "  Enter project name or ID (or press Enter to keep: %s): " "$cur_proj_name"
  else
    printf "  Enter project name or ID (or press Enter to skip): "
  fi
  local proj_input; read -r proj_input || proj_input=""

  local proj_name="$cur_proj_name" proj_id="$cur_proj_id"
  if [[ -n "$proj_input" ]]; then
    local fid fname
    fid=$(_json_lookup "$proj_json" "$proj_input" "Name" "ID")
    fname=$(_json_lookup "$proj_json" "$proj_input" "Name" "Name")
    if [[ -z "$fid" ]]; then
      fid=$(_json_lookup "$proj_json" "$proj_input" "ID" "ID")
      fname=$(_json_lookup "$proj_json" "$proj_input" "ID" "Name")
    fi
    if [[ -n "$fid" ]]; then
      proj_id="$fid"; proj_name="${fname:-$proj_input}"
      echo "  Selected project: ${proj_name} (${proj_id})"
    else
      echo "  Warning: '${proj_input}' not found in list — saving as-is"
      proj_name="$proj_input"; proj_id="$proj_input"
    fi
    export OS_PROJECT_ID="$proj_id"
    export OS_PROJECT_NAME="$proj_name"
  else
    [[ -n "$cur_proj_name" ]] && echo "  (kept: ${cur_proj_name})" || echo "  Skipping project selection."
    [[ -n "$proj_id" ]]   && export OS_PROJECT_ID="$proj_id"   || true
    [[ -n "$proj_name" ]] && export OS_PROJECT_NAME="$proj_name" || true
  fi
  env_out+="OS_PROJECT_NAME=\"${proj_name}\"\n"
  env_out+="OS_PROJECT_ID=\"${proj_id}\"\n"

  # ── 2b) Network ──────────────────────────────────────────────────────────────
  echo ""
  echo "  Fetching networks..."
  local net_proj_json net_ext_json net_merged_json
  net_proj_json=$(openstack_cmd network list \
    --project "${OS_PROJECT_ID:-}" -f json 2>/dev/null) || net_proj_json="[]"
  net_ext_json=$(openstack_cmd network list \
    --external -f json 2>/dev/null) || net_ext_json="[]"
  if [[ -n "$PYTHON3" ]]; then
    net_merged_json=$("$PYTHON3" - "$net_proj_json" "$net_ext_json" <<'PYEOF_NET'
import sys, json
a = json.loads(sys.argv[1]); b = json.loads(sys.argv[2])
seen = set(); merged = []
for item in a + b:
    nid = item.get("ID") or item.get("id") or ""
    if nid not in seen:
        seen.add(nid); merged.append(item)
print(json.dumps(merged))
PYEOF_NET
    ) || net_merged_json="$net_proj_json"
  else
    net_merged_json="$net_proj_json"
    echo "  Note: python not available — network list may contain duplicates"
  fi
  echo ""
  echo "  Available networks:"
  _print_ref_table "$net_merged_json" "Name" "ID" "Status"
  echo ""
  if [[ -n "$cur_net_name" ]]; then
    printf "  Enter network name or ID (or press Enter to keep: %s): " "$cur_net_name"
  else
    printf "  Enter network name or ID (or press Enter to skip): "
  fi
  local net_input; read -r net_input || net_input=""

  local net_name="$cur_net_name" net_id="$cur_net_id"
  if [[ -n "$net_input" ]]; then
    local fnid fnname
    fnid=$(_json_lookup "$net_merged_json" "$net_input" "Name" "ID")
    fnname=$(_json_lookup "$net_merged_json" "$net_input" "Name" "Name")
    if [[ -z "$fnid" ]]; then
      fnid=$(_json_lookup "$net_merged_json" "$net_input" "ID" "ID")
      fnname=$(_json_lookup "$net_merged_json" "$net_input" "ID" "Name")
    fi
    if [[ -n "$fnid" ]]; then
      net_id="$fnid"; net_name="${fnname:-$net_input}"
      echo "  Selected network: ${net_name} (${net_id})"
    else
      echo "  Warning: '${net_input}' not found in list — saving as-is"
      net_name="$net_input"; net_id="$net_input"
    fi
  else
    [[ -n "$cur_net_name" ]] && echo "  (kept: ${cur_net_name})" || echo "  Skipping network selection."
  fi
  env_out+="NETWORK_ID=\"${net_id}\"\n"
  env_out+="NETWORK_NAME=\"${net_name}\"\n"

  # ── 2c) Flavor ───────────────────────────────────────────────────────────────
  echo ""
  echo "  Fetching flavors..."
  local flavor_json
  flavor_json=$(openstack_cmd flavor list -f json 2>/dev/null) || flavor_json="[]"
  echo ""
  echo "  Available flavors:"
  _print_ref_table "$flavor_json" "Name" "VCPUs" "RAM" "Disk" "ID"
  echo ""
  if [[ -n "$cur_flavor_name" ]]; then
    printf "  Enter flavor name or ID (or press Enter to keep: %s): " "$cur_flavor_name"
  else
    printf "  Enter flavor name or ID (or press Enter to skip): "
  fi
  local flavor_input; read -r flavor_input || flavor_input=""

  local flavor_name="$cur_flavor_name" flavor_id="$cur_flavor_id"
  if [[ -n "$flavor_input" ]]; then
    local ffid ffname
    ffid=$(_json_lookup "$flavor_json" "$flavor_input" "Name" "ID")
    ffname=$(_json_lookup "$flavor_json" "$flavor_input" "Name" "Name")
    if [[ -z "$ffid" ]]; then
      ffid=$(_json_lookup "$flavor_json" "$flavor_input" "ID" "ID")
      ffname=$(_json_lookup "$flavor_json" "$flavor_input" "ID" "Name")
    fi
    if [[ -n "$ffid" ]]; then
      flavor_id="$ffid"; flavor_name="${ffname:-$flavor_input}"
      echo "  Selected flavor: ${flavor_name} (ID: ${flavor_id})"
    else
      echo "  Warning: '${flavor_input}' not found in list — saving as-is"
      flavor_name="$flavor_input"; flavor_id="$flavor_input"
    fi
  else
    [[ -n "$cur_flavor_name" ]] && echo "  (kept: ${cur_flavor_name})" || echo "  Skipping flavor selection."
  fi
  env_out+="FLAVOR_ID=\"${flavor_id}\"\n"
  env_out+="FLAVOR_NAME=\"${flavor_name}\"\n"

  # ── 2d) Volume Type ──────────────────────────────────────────────────────────
  echo ""
  echo "  Fetching volume types..."
  local voltype_json=""
  voltype_json=$(openstack_cmd volume type list \
    --os-project-id "${OS_PROJECT_ID:-}" -f json 2>/dev/null) || voltype_json="[]"
  local voltype_count=0
  if [[ -n "$PYTHON3" ]]; then
    voltype_count=$("$PYTHON3" -c 'import sys,json; print(len(json.load(sys.stdin)))' \
      <<< "$voltype_json" 2>/dev/null) || voltype_count=0
  fi
  if [[ "$voltype_count" == "0" ]]; then
    voltype_json=$(openstack_cmd volume type list -f json 2>/dev/null) || voltype_json="[]"
    if [[ -n "$PYTHON3" ]]; then
      voltype_count=$("$PYTHON3" -c 'import sys,json; print(len(json.load(sys.stdin)))' \
        <<< "$voltype_json" 2>/dev/null) || voltype_count=0
    fi
  fi

  local volume_type="$cur_volume_type"
  if [[ "$voltype_count" -gt 0 ]]; then
    echo ""
    echo "  Available volume types:"
    _print_ref_table "$voltype_json" "Name" "ID"
    echo ""
    if [[ -n "$cur_volume_type" ]]; then
      printf "  Enter volume type name or ID (or press Enter to keep: %s): " "$cur_volume_type"
    else
      printf "  Enter volume type name (or press Enter to skip): "
    fi
    local vt_input; read -r vt_input || vt_input=""
    if [[ -n "$vt_input" ]]; then
      if _json_has_item "$voltype_json" "$vt_input"; then
        local rvt
        rvt=$(_json_lookup "$voltype_json" "$vt_input" "Name" "Name")
        [[ -z "$rvt" ]] && rvt=$(_json_lookup "$voltype_json" "$vt_input" "ID" "Name")
        volume_type="${rvt:-$vt_input}"
        echo "  Selected volume type: ${volume_type}"
      else
        echo "  Warning: '${vt_input}' not found in list — saving as-is"
        volume_type="$vt_input"
      fi
    else
      [[ -n "$cur_volume_type" ]] && echo "  (kept: ${cur_volume_type})" || echo "  Skipping volume type."
    fi
  else
    echo "  Volume type list unavailable. Enter volume type name manually,"
    if [[ -n "$cur_volume_type" ]]; then
      printf "  or press Enter to keep (%s): " "$cur_volume_type"
    else
      echo "  or press Enter to skip:"
      echo -n "  Volume type: "
    fi
    local manual_vt=""
    read -r manual_vt || manual_vt=""
    if [[ -n "$manual_vt" ]]; then
      volume_type="$manual_vt"
      echo "  Volume type set to: ${volume_type}"
    else
      [[ -n "$cur_volume_type" ]] && echo "  (kept: ${cur_volume_type})" || echo "  Skipping volume type."
    fi
  fi
  env_out+="VOLUME_TYPE=\"${volume_type}\"\n"

  # ── 2e) Security Group (client-side project filter) ───────────────────────────
  echo ""
  echo "  Fetching security groups..."
  local sg_all_json sg_json
  sg_all_json=$(openstack_cmd security group list -f json 2>/dev/null) || sg_all_json="[]"
  if [[ -n "$PYTHON3" ]] && [[ -n "${OS_PROJECT_ID:-}" ]]; then
    sg_json=$(PYTHONUTF8=1 "$PYTHON3" - "$sg_all_json" "${OS_PROJECT_ID}" <<'PYEOF_SG'
import sys, json
data = json.loads(sys.argv[1]); proj_id = sys.argv[2]
filtered = [item for item in data
            if str(item.get("Project","") or item.get("project_id","") or "").lower()
               in (proj_id.lower(), "")
            or item.get("Project") is None]
result = filtered if filtered else data
print(json.dumps(result))
PYEOF_SG
    ) || sg_json="$sg_all_json"
    local sg_count=0
    sg_count=$("$PYTHON3" -c 'import sys,json; print(len(json.load(sys.stdin)))' \
      <<< "$sg_json" 2>/dev/null) || sg_count=0
    [[ "$sg_count" == "0" ]] && sg_json="$sg_all_json"
  else
    sg_json="$sg_all_json"
  fi
  echo ""
  echo "  Available security groups:"
  _print_ref_table "$sg_json" "Name" "Description"
  echo ""
  if [[ -n "$cur_sg" ]]; then
    printf "  Enter security group name (or press Enter to keep: %s): " "$cur_sg"
  else
    printf "  Enter security group name (or press Enter to skip): "
  fi
  local sg_input; read -r sg_input || sg_input=""

  local security_group="$cur_sg"
  if [[ -n "$sg_input" ]]; then
    if _json_has_item "$sg_json" "$sg_input"; then
      local rsg
      rsg=$(_json_lookup "$sg_json" "$sg_input" "Name" "Name")
      security_group="${rsg:-$sg_input}"
      echo "  Selected security group: ${security_group}"
    else
      echo "  Warning: '${sg_input}' not found in list — saving as-is"
      security_group="$sg_input"
    fi
  else
    [[ -n "$cur_sg" ]] && echo "  (kept: ${cur_sg})" || echo "  Skipping security group."
  fi
  env_out+="SECURITY_GROUP=\"${security_group}\"\n"

  # ── 2e.5) SSH Keypair ────────────────────────────────────────────────────────
  echo ""
  echo "  Fetching keypairs..."
  local keypair_json
  keypair_json=$(openstack_cmd keypair list -f json 2>/dev/null) || keypair_json="[]"
  echo ""
  echo "  Available keypairs:"
  _print_ref_table "$keypair_json" "Name" "Fingerprint"
  echo ""
  if [[ -n "$cur_key_name" ]]; then
    printf "  Enter keypair name (or press Enter to keep: %s): " "$cur_key_name"
  else
    printf "  Enter keypair name (or press Enter to skip): "
  fi
  local key_input; read -r key_input || key_input=""

  local key_name="$cur_key_name"
  if [[ -n "$key_input" ]]; then
    if _json_has_item "$keypair_json" "$key_input"; then
      local rkey
      rkey=$(_json_lookup "$keypair_json" "$key_input" "Name" "Name")
      key_name="${rkey:-$key_input}"
      echo "  Selected keypair: ${key_name}"
    else
      echo "  Warning: '${key_input}' not found in list — saving as-is"
      key_name="$key_input"
    fi
  else
    [[ -n "$cur_key_name" ]] && echo "  (kept: ${cur_key_name})" || echo "  Skipping keypair (will use password auth)."
  fi
  env_out+="KEY_NAME=\"${key_name}\"\n"

  # ── 2f) Floating Network ─────────────────────────────────────────────────────
  echo ""
  echo "  Fetching external networks (for floating IP)..."
  local extnet_json
  extnet_json=$(openstack_cmd network list --external -f json 2>/dev/null) || extnet_json="[]"
  echo ""
  echo "  Available floating networks:"
  _print_ref_table "$extnet_json" "Name" "ID"
  echo ""
  if [[ -n "$cur_float_net" ]]; then
    printf "  Enter floating network name or ID, or 'skip' (Enter to keep: %s): " "$cur_float_net"
  else
    printf "  Enter floating network name or ID (or press Enter to skip): "
  fi
  local ext_input; read -r ext_input || ext_input=""

  local float_net="$cur_float_net" float_net_id="$cur_float_net_id"
  if [[ "$ext_input" == "skip" || "$ext_input" == "0" ]]; then
    float_net=""; float_net_id=""
    echo "  Floating network: skipped"
  elif [[ -n "$ext_input" ]]; then
    local feid fename
    feid=$(_json_lookup "$extnet_json" "$ext_input" "Name" "ID")
    fename=$(_json_lookup "$extnet_json" "$ext_input" "Name" "Name")
    if [[ -z "$feid" ]]; then
      feid=$(_json_lookup "$extnet_json" "$ext_input" "ID" "ID")
      fename=$(_json_lookup "$extnet_json" "$ext_input" "ID" "Name")
    fi
    if [[ -n "$feid" ]]; then
      float_net="${fename:-$ext_input}"; float_net_id="$feid"
      echo "  Selected floating network: ${float_net} (${float_net_id})"
    else
      echo "  Warning: '${ext_input}' not found in list — saving as-is"
      float_net="$ext_input"; float_net_id="$ext_input"
    fi
  else
    [[ -n "$cur_float_net" ]] && echo "  (kept: ${cur_float_net})" || echo "  Floating network: skipped"
  fi
  env_out+="FLOATING_NETWORK=\"${float_net}\"\n"
  env_out+="FLOATING_NETWORK_ID=\"${float_net_id}\"\n"

  # Write settings/openstack.env
  util_ensure_dir "${SETTINGS_DIR}"
  printf '%b' "$env_out" > "${OPENSTACK_ENV}"
  echo ""
  echo "  ✓ Settings saved to settings/openstack.env"
}

# ──────────────────────────────────────────────────────────────────────────────
# OPTION 3 — Edit Guest Access
# ──────────────────────────────────────────────────────────────────────────────
_settings_edit_guest_access() {
  local guest_env="${GUEST_ACCESS_ENV}"
  local guest_keys_dir="${SETTINGS_DIR}/guest-keys"

  # Load current values
  local cur_mode="" cur_user="" cur_port="" cur_password=""
  local cur_private_key="" cur_auth_key=""
  local cur_enable_root="yes" cur_permit_root="yes"
  local cur_pass_auth="yes" cur_pubkey_auth="yes"
  if [[ -f "$guest_env" ]]; then
    # shellcheck disable=SC1090
    source "$guest_env" 2>/dev/null || true
    cur_mode="${SSH_AUTH_MODE:-}"
    cur_user="${SSH_USER:-}"
    cur_port="${SSH_PORT:-}"
    cur_password="${ROOT_PASSWORD:-}"
    cur_private_key="${SSH_PRIVATE_KEY:-}"
    cur_auth_key="${ROOT_AUTHORIZED_KEY:-}"
    cur_enable_root="${ENABLE_ROOT_SSH:-yes}"
    cur_permit_root="${SSH_PERMIT_ROOT_LOGIN:-yes}"
    cur_pass_auth="${SSH_PASSWORD_AUTH:-yes}"
    cur_pubkey_auth="${SSH_PUBKEY_AUTH:-yes}"
  fi

  echo ""
  echo "  Current Guest Access Settings:"
  printf "  %-20s: %s\n" "SSH_AUTH_MODE"  "${cur_mode:-(not set)}"
  printf "  %-20s: %s\n" "SSH_USER"       "${cur_user:-(not set)}"
  printf "  %-20s: %s\n" "SSH_PORT"       "${cur_port:-(not set)}"
  local pw_display="(not set)"
  [[ -n "${cur_password:-}" ]] && pw_display="***"
  printf "  %-20s: %s\n" "ROOT_PASSWORD"  "$pw_display"
  printf "  %-20s: %s\n" "SSH_PRIVATE_KEY" "${cur_private_key:-(not set)}"
  echo ""
  echo "  Press Enter to keep current value."
  echo ""

  # ── Field 1: Auth Mode ────────────────────────────────────────────────────
  local new_mode="$cur_mode"
  while true; do
    printf "  Auth mode [password/key] (keep: %s): " "${cur_mode:-(not set)}"
    local input; read -r input || input=""
    if [[ -z "$input" ]]; then
      new_mode="${cur_mode:-password}"
      break
    elif [[ "$input" == "password" || "$input" == "key" ]]; then
      new_mode="$input"
      break
    else
      echo "  Invalid — must be password or key"
    fi
  done

  # ── Field 2: SSH User ─────────────────────────────────────────────────────
  printf "  SSH user (keep: %s): " "${cur_user:-root}"
  local u_input; read -r u_input || u_input=""
  local new_user="${cur_user:-root}"
  [[ -n "$u_input" ]] && new_user="$u_input"

  # ── Field 3: SSH Port ─────────────────────────────────────────────────────
  local new_port="${cur_port:-22}"
  while true; do
    printf "  SSH port (keep: %s): " "${cur_port:-22}"
    local p_input; read -r p_input || p_input=""
    if [[ -z "$p_input" ]]; then
      break
    elif [[ "$p_input" =~ ^[0-9]+$ ]] && (( p_input >= 1 && p_input <= 65535 )); then
      new_port="$p_input"
      break
    else
      echo "  Invalid — must be a number between 1 and 65535"
    fi
  done

  # ── Field 4: Credential (password or key) ────────────────────────────────
  local new_password="$cur_password"
  local new_private_key="$cur_private_key"
  if [[ "$new_mode" == "password" ]]; then
    echo -n "  Root password (keep: ***): "
    local pw_input; read -rs pw_input || pw_input=""
    echo ""
    [[ -n "$pw_input" ]] && new_password="$pw_input"
  else
    # Scan settings/guest-keys/ for key files
    local keyfiles=()
    local kf
    for kf in "${guest_keys_dir}"/id_* "${guest_keys_dir}"/*.pem \
               "${guest_keys_dir}"/*.rsa; do
      [[ -f "$kf" ]] && keyfiles+=("$(basename "$kf")") || true
    done

    if [[ ${#keyfiles[@]} -eq 0 ]]; then
      echo "  No key files found in settings/guest-keys/"
      echo "  Place your private key there and try again."
      echo "  SSH_PRIVATE_KEY left unchanged."
    elif [[ ${#keyfiles[@]} -eq 1 ]]; then
      echo "  Auto-selected key: ${keyfiles[0]}"
      new_private_key="${guest_keys_dir}/${keyfiles[0]}"
    else
      echo "  Available keys in settings/guest-keys/:"
      local i=1
      for kf in "${keyfiles[@]}"; do
        printf "    %d) %s\n" "$i" "$kf"
        (( i++ )) || true
      done
      printf "  Select key (or press Enter to keep current): "
      local kidx; read -r kidx || kidx=""
      if [[ -n "$kidx" ]] && [[ "$kidx" =~ ^[0-9]+$ ]]; then
        local sel=$(( kidx - 1 ))
        if (( sel >= 0 && sel < ${#keyfiles[@]} )); then
          new_private_key="${guest_keys_dir}/${keyfiles[$sel]}"
        fi
      fi
    fi
  fi

  # ── Field 5: Root Authorized Key (optional) ───────────────────────────────
  local new_auth_key="$cur_auth_key"
  local ak_preview="(not set)"
  if [[ -n "$cur_auth_key" ]]; then
    ak_preview="${cur_auth_key:0:40}..."
  fi
  echo "  Root authorized key (public key to inject into guest):"
  echo "  Current: ${ak_preview}"
  echo -n "  Paste public key or press Enter to keep: "
  local ak_input; read -r ak_input || ak_input=""
  [[ -n "$ak_input" ]] && new_auth_key="$ak_input"

  # ── Field 6: Root SSH Policy ──────────────────────────────────────────────
  local new_enable_root="$cur_enable_root"
  local new_permit_root="$cur_permit_root"
  local new_pass_auth="$cur_pass_auth"
  local new_pubkey_auth="$cur_pubkey_auth"

  echo ""
  echo "  Root SSH Policy (current values):"
  printf "    %-26s: %s\n" "ENABLE_ROOT_SSH"       "${cur_enable_root:-yes}"
  printf "    %-26s: %s\n" "SSH_PERMIT_ROOT_LOGIN" "${cur_permit_root:-yes}"
  printf "    %-26s: %s\n" "SSH_PASSWORD_AUTH"     "${cur_pass_auth:-yes}"
  printf "    %-26s: %s\n" "SSH_PUBKEY_AUTH"       "${cur_pubkey_auth:-yes}"
  echo -n "  Change policy? [y/N]: "
  local ch; read -r ch || ch=""
  if [[ "${ch,,}" == "y" ]]; then
    local pol_var pol_cur pol_val
    for pol_var in ENABLE_ROOT_SSH SSH_PERMIT_ROOT_LOGIN SSH_PASSWORD_AUTH SSH_PUBKEY_AUTH; do
      case "$pol_var" in
        ENABLE_ROOT_SSH)       pol_cur="$new_enable_root" ;;
        SSH_PERMIT_ROOT_LOGIN) pol_cur="$new_permit_root" ;;
        SSH_PASSWORD_AUTH)     pol_cur="$new_pass_auth" ;;
        SSH_PUBKEY_AUTH)       pol_cur="$new_pubkey_auth" ;;
      esac
      while true; do
        printf "  %s [yes/no] (keep: %s): " "$pol_var" "${pol_cur:-yes}"
        read -r pol_val || pol_val=""
        if [[ -z "$pol_val" ]]; then
          pol_val="$pol_cur"
          break
        elif [[ "$pol_val" == "yes" || "$pol_val" == "no" ]]; then
          break
        else
          echo "  Invalid — must be yes or no"
        fi
      done
      case "$pol_var" in
        ENABLE_ROOT_SSH)       new_enable_root="$pol_val" ;;
        SSH_PERMIT_ROOT_LOGIN) new_permit_root="$pol_val" ;;
        SSH_PASSWORD_AUTH)     new_pass_auth="$pol_val" ;;
        SSH_PUBKEY_AUTH)       new_pubkey_auth="$pol_val" ;;
      esac
    done
  fi

  # ── Save to settings/guest-access.env ────────────────────────────────────
  util_ensure_dir "${SETTINGS_DIR}"
  cat > "$guest_env" <<EOF
# settings/guest-access.env — generated by control.sh
# This file is gitignored — do not commit

SSH_AUTH_MODE="${new_mode}"
SSH_USER="${new_user}"
SSH_PORT="${new_port}"
SSH_CONNECT_TIMEOUT="60"
ROOT_PASSWORD="${new_password}"
SSH_PRIVATE_KEY="${new_private_key}"
ROOT_AUTHORIZED_KEY="${new_auth_key}"
ENABLE_ROOT_SSH="${new_enable_root}"
SSH_PERMIT_ROOT_LOGIN="${new_permit_root}"
SSH_PASSWORD_AUTH="${new_pass_auth}"
SSH_PUBKEY_AUTH="${new_pubkey_auth}"
EOF
  echo ""
  echo "  ✓ Guest access saved to settings/guest-access.env"

  # ── Validate after save ───────────────────────────────────────────────────
  local warn=""
  if [[ "$new_mode" == "password" ]] && [[ -z "$new_password" ]]; then
    warn="SSH_AUTH_MODE=password but ROOT_PASSWORD is empty"
  elif [[ "$new_mode" == "key" ]] && [[ -z "$new_private_key" ]]; then
    warn="SSH_AUTH_MODE=key but SSH_PRIVATE_KEY is empty"
  elif [[ "$new_mode" == "key" ]] && [[ -n "$new_private_key" ]] && \
       [[ ! -f "$new_private_key" ]]; then
    warn="SSH_PRIVATE_KEY file not found: ${new_private_key}"
  fi

  if [[ -n "$warn" ]]; then
    echo "  ⚠ Warning: ${warn}"
  else
    echo "  ✓ Validation OK"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# OPTION 4 — Show Current Settings (read-only summary)
# ──────────────────────────────────────────────────────────────────────────────
_settings_show() {
  # Guard: prevent recursive/duplicate calls (e.g. from sourced session files)
  [[ "${_SETTINGS_SHOW_ACTIVE:-0}" == "1" ]] && return 0
  _SETTINGS_SHOW_ACTIVE=1
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
  local proj_val net_val flavor_val voltype_val sg_val float_val key_val
  proj_val="(not set)"; net_val="(not set)"; flavor_val="(not set)"
  voltype_val="(not set)"; sg_val="(not set)"; float_val="(not configured)"
  key_val="(not set)"
  if [[ -f "$OPENSTACK_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$OPENSTACK_ENV" 2>/dev/null || true
    [[ -n "${OS_PROJECT_NAME:-}" ]]  && proj_val="$OS_PROJECT_NAME"
    [[ -n "${NETWORK_NAME:-}" ]]     && net_val="$NETWORK_NAME"
    [[ -n "${FLAVOR_NAME:-}" ]]      && flavor_val="$FLAVOR_NAME"
    [[ -n "${VOLUME_TYPE:-}" ]]      && voltype_val="$VOLUME_TYPE"
    [[ -n "${SECURITY_GROUP:-}" ]]   && sg_val="$SECURITY_GROUP"
    [[ -n "${KEY_NAME:-}" ]]         && key_val="$KEY_NAME"
    if [[ "${FLOATING_NETWORK+x}" ]]; then
      [[ -n "${FLOATING_NETWORK:-}" ]] && float_val="$FLOATING_NETWORK" || float_val="(not configured)"
    fi
  fi
  printf "  %-16s: %s\n" "Project"        "$proj_val"
  printf "  %-16s: %s\n" "Network"        "$net_val"
  printf "  %-16s: %s\n" "Flavor"         "$flavor_val"
  printf "  %-16s: %s\n" "Volume Type"    "$voltype_val"
  printf "  %-16s: %s\n" "Security Group" "$sg_val"
  printf "  %-16s: %s\n" "SSH Keypair"    "$key_val"
  printf "  %-16s: %s\n" "Floating Net"   "$float_val"
  echo ""

  # Guest Access section
  echo "  [ Guest Access ]"
  local ga_mode ga_user ga_port ga_key ga_pkey
  ga_mode="(not set)"; ga_user="(not set)"; ga_port="(not set)"
  ga_key="(not set)"; ga_pkey="(not set)"
  if [[ -f "$GUEST_ACCESS_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$GUEST_ACCESS_ENV" 2>/dev/null || true
    [[ -n "${SSH_AUTH_MODE:-}" ]]   && ga_mode="$SSH_AUTH_MODE"
    [[ -n "${SSH_USER:-}" ]]        && ga_user="$SSH_USER"
    [[ -n "${SSH_PORT:-}" ]]        && ga_port="$SSH_PORT"
    if [[ "${SSH_AUTH_MODE:-}" == "password" ]]; then
      [[ -n "${ROOT_PASSWORD:-}" ]] && ga_key="***" || ga_key="(not set)"
    else
      ga_pkey="${SSH_PRIVATE_KEY:-(not set)}"
    fi
  fi
  printf "  %-20s: %s\n" "Auth Mode"    "$ga_mode"
  printf "  %-20s: %s\n" "SSH User"     "$ga_user"
  printf "  %-20s: %s\n" "SSH Port"     "$ga_port"
  if [[ "${ga_mode}" == "password" ]]; then
    printf "  %-20s: %s\n" "Root Password" "$ga_key"
  else
    printf "  %-20s: %s\n" "Private Key"   "$ga_pkey"
  fi
  echo ""

  # Files section
  echo "  [ Files ]"
  local _exists _missing
  _exists="exists"; _missing="missing"
  printf "  %-16s: %s\n" "openstack.env"  "$( [[ -f "$OPENSTACK_ENV" ]]      && echo "$_exists" || echo "$_missing" )"
  printf "  %-16s: %s\n" "guest-access"   "$( [[ -f "$GUEST_ACCESS_ENV" ]]   && echo "$_exists" || echo "$_missing" )"
  printf "  %-16s: %s\n" "active-profile" "$( [[ -f "$profile_file" ]]       && echo "$_exists" || echo "$_missing" )"
  echo ""
  _SETTINGS_SHOW_ACTIVE=0
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
# ─── Build helpers ────────────────────────────────────────────────────────────

_build_select_os() {
  local os_list="ubuntu debian fedora almalinux rocky"
  local os ready_vers dryrun_vers label
  local -a display=()
  local -a valid_oses=()

  for os in $os_list; do
    ready_vers=$(_build_list_ready | awk -v o="$os" \
      '$1==o && $3=="ready" {print $2}' | sort -V | tr '\n' ' ')
    dryrun_vers=$(_build_list_ready | awk -v o="$os" \
      '$1==o && $3=="dryrun-only" {print $2}' | sort -V | tr '\n' ' ')

    if [[ -n "$ready_vers" ]]; then
      label="$os  [ready: ${ready_vers% }]"
      display+=("$label")
      valid_oses+=("$os")
    elif [[ -n "$dryrun_vers" ]]; then
      label="$os  [not downloaded: ${dryrun_vers% }]"
      display+=("$label")
      valid_oses+=("$os")
    fi
  done

  if [[ ${#valid_oses[@]} -eq 0 ]]; then
    echo "  No OS versions found. Run Sync → Download first." >&2
    return 1
  fi

  echo "  Select OS:" >&2
  local i=1
  for label in "${display[@]}"; do
    printf "    %d) %s\n" "$i" "$label" >&2
    (( i++ )) || true
  done
  echo -n "  Select [1-${#valid_oses[@]}]: " >&2
  local choice
  read -r choice || return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  local idx=$(( choice - 1 ))
  [[ $idx -ge 0 && $idx -lt ${#valid_oses[@]} ]] || return 1
  printf '%s' "${valid_oses[$idx]}"
}

_build_select_version() {
  local os="$1"
  local -a versions=()
  local -a statuses=()
  local ver st

  while IFS=' ' read -r _ ver st; do
    versions+=("$ver")
    statuses+=("$st")
  done < <(_build_list_ready | awk -v o="$os" '$1==o' | sort -t' ' -k2 -V)

  if [[ ${#versions[@]} -eq 0 ]]; then
    echo "  No versions found for $os." >&2
    return 1
  fi

  echo "  Select version for $os:" >&2
  local i=1
  for ver in "${versions[@]}"; do
    st="${statuses[$((i-1))]}"
    if [[ "$st" == "ready" ]]; then
      printf "    %d) %s  [ready]\n" "$i" "$ver" >&2
    else
      printf "    %d) %s  [not downloaded — run Sync first]\n" "$i" "$ver" >&2
    fi
    (( i++ )) || true
  done
  echo -n "  Select [1-${#versions[@]}]: " >&2
  local choice
  read -r choice || return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  local idx=$(( choice - 1 ))
  [[ $idx -ge 0 && $idx -lt ${#versions[@]} ]] || return 1

  if [[ "${statuses[$idx]}" != "ready" ]]; then
    echo "  ✗ Version ${versions[$idx]} is not downloaded." >&2
    echo "  → Go to Sync → Download first." >&2
    return 1
  fi
  printf '%s' "${versions[$idx]}"
}

_build_preflight() {
  local os="$1" version="$2"
  local ok=true

  echo "  Checking preflight for $os $version..."

  if [[ -z "${OS_AUTH_URL:-}" ]]; then
    echo "  ✗ OpenRC not loaded — go to Settings → Load OpenRC first"
    ok=false
  else
    echo "  ✓ OpenRC loaded (${OS_AUTH_URL})"
  fi

  if [[ ! -f "${OPENSTACK_ENV}" ]]; then
    echo "  ✗ settings/openstack.env missing"
    ok=false
  else
    echo "  ✓ openstack.env exists"
  fi

  if [[ ! -f "${GUEST_ACCESS_ENV}" ]]; then
    echo "  ✗ settings/guest-access.env missing — go to Settings → Edit Guest Access"
    ok=false
  else
    echo "  ✓ guest-access.env exists"
  fi

  local sync_ready="${STATE_SYNC_DIR}/${os}-${version}.ready"
  if [[ ! -f "$sync_ready" ]]; then
    echo "  ✗ $os $version not downloaded — go to Sync → Download first"
    ok=false
  else
    echo "  ✓ sync ready: $os $version"
  fi

  local guest_cfg="${CONFIG_DIR}/guest/${os}/${version}.env"
  local guest_default="${CONFIG_DIR}/guest/${os}/default.env"
  if [[ ! -f "$guest_cfg" && ! -f "$guest_default" ]]; then
    echo "  ✗ guest config missing: config/guest/${os}/${version}.env"
    ok=false
  else
    echo "  ✓ guest config found"
  fi

  $ok && return 0 || return 1
}

_build_run_pipeline() {
  local os="$1" version="$2"
  local phase rc

  local phases="import_base create_vm configure_guest clean_guest publish_final"

  for phase in $phases; do
    echo ""
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  PHASE: $phase  ($os $version)"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "${PHASES_DIR}/${phase}.sh" --os "$os" --version "$version"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo ""
      echo "  ✗ PHASE FAILED: $phase (exit $rc)"
      echo "  Pipeline stopped. Check runtime/logs/$phase/${os}-${version}.log"
      return 1
    fi
    echo "  ✓ PHASE DONE: $phase"
  done

  echo ""
  echo "  ✓ PIPELINE COMPLETE: $os $version"
}

_build_run_one_phase() {
  local os="$1" version="$2" phase="$3"

  case "$phase" in
    create_vm)
      [[ -f "${STATE_DIR}/import/${os}-${version}.ready" ]] || {
        echo "  ✗ import not done yet — run Import Base Image first"
        return 1
      } ;;
    configure_guest)
      [[ -f "${STATE_DIR}/create/${os}-${version}.ready" ]] || {
        echo "  ✗ create not done yet — run Create VM first"
        return 1
      } ;;
    clean_guest)
      [[ -f "${STATE_DIR}/configure/${os}-${version}.ready" ]] || {
        echo "  ✗ configure not done yet — run Configure Guest first"
        return 1
      } ;;
    publish_final)
      [[ -f "${STATE_DIR}/clean/${os}-${version}.ready" ]] || {
        echo "  ✗ clean not done yet — run Final Clean first"
        return 1
      } ;;
  esac

  echo "  Running: $phase ($os $version)..."
  bash "${PHASES_DIR}/${phase}.sh" --os "$os" --version "$version"
  local rc=$?
  [[ $rc -eq 0 ]] \
    && echo "  ✓ $phase DONE" \
    || echo "  ✗ $phase FAILED (exit $rc)"
  return $rc
}

_build_step_status() {
  local os="$1" ver="$2"
  local phases="import create configure clean publish"
  local phase icon
  echo "  Current state:"
  for phase in $phases; do
    if [[ -f "${STATE_DIR}/${phase}/${os}-${ver}.ready" ]]; then
      icon="✓"
    elif [[ -f "${STATE_DIR}/${phase}/${os}-${ver}.failed" ]]; then
      icon="✗"
    else
      icon="○"
    fi
    printf "    %s %s\n" "$icon" "$phase"
  done
  echo ""
}

_menu_build_auto_os_latest() {
  local os ver
  os=$(_build_select_os) || return
  ver=$(_build_latest_ready_version "$os")
  if [[ -z "$ver" ]]; then
    echo "  No downloaded versions for $os. Run Sync → Download first."
    return
  fi
  echo "  Auto-selected: $os $ver (latest ready)"
  _build_preflight "$os" "$ver" || return
  echo "  Starting pipeline: $os $ver"
  _build_run_pipeline "$os" "$ver"
}

_menu_build_auto_os_all() {
  local os ver
  os=$(_build_select_os) || return
  local versions
  versions=$(_build_all_ready_versions "$os")
  if [[ -z "$versions" ]]; then
    echo "  No downloaded versions for $os. Run Sync → Download first."
    return
  fi
  echo "  Will run pipeline for: $os — versions: $(echo "$versions" | tr '\n' ' ')"
  for ver in $versions; do
    echo ""
    echo "  ══════════════════════════════════════"
    echo "  Starting: $os $ver"
    echo "  ══════════════════════════════════════"
    _build_preflight "$os" "$ver" || continue
    _build_run_pipeline "$os" "$ver" || true
  done
  echo ""
  echo "  ✓ All versions processed for $os"
}

_menu_build_auto_all() {
  local all_ready
  all_ready=$(_build_list_ready | awk '$3=="ready" {print $1, $2}' | sort -k1,1 -k2,2V)
  if [[ -z "$all_ready" ]]; then
    echo "  No downloaded images found. Run Sync → Download first."
    return
  fi
  echo "  Will run pipeline for ALL:"
  echo "$all_ready" | while read -r os ver; do
    echo "    - $os $ver"
  done
  echo ""
  echo "$all_ready" | while read -r os ver; do
    echo ""
    echo "  ══════════════════════════════════════"
    echo "  Starting: $os $ver"
    echo "  ══════════════════════════════════════"
    _build_preflight "$os" "$ver" || continue
    _build_run_pipeline "$os" "$ver" || true
  done
  echo ""
  echo "  ✓ All OS all versions processed"
}

_menu_build_manual_full() {
  local os ver
  os=$(_build_select_os)   || return
  ver=$(_build_select_version "$os") || return
  _build_preflight "$os" "$ver" || return
  echo "  Starting full pipeline: $os $ver"
  _build_run_pipeline "$os" "$ver"
}

_menu_build_manual_step() {
  local os ver
  os=$(_build_select_os)   || return
  ver=$(_build_select_version "$os") || return
  _build_preflight "$os" "$ver" || return

  while true; do
    echo ""
    echo "  --- Build: Step-by-Step ($os $ver) ---"
    _build_step_status "$os" "$ver"
    echo "  1) Import Base Image"
    echo "  2) Create VM"
    echo "  3) Configure Guest"
    echo "  4) Final Clean"
    echo "  5) Publish Final Image"
    echo "  6) Back"
    echo -n "  Select [1-6]: "
    local sc; read -r sc || return
    case "$sc" in
      1) _build_run_one_phase "$os" "$ver" "import_base" ;;
      2) _build_run_one_phase "$os" "$ver" "create_vm" ;;
      3) _build_run_one_phase "$os" "$ver" "configure_guest" ;;
      4) _build_run_one_phase "$os" "$ver" "clean_guest" ;;
      5) _build_run_one_phase "$os" "$ver" "publish_final" ;;
      6) return ;;
      *) echo "  Invalid choice." ;;
    esac
  done
}

# ─── Build menu ───────────────────────────────────────────────────────────────
menu_build() {
  while true; do
    echo ""
    echo "--- Build ---"
    echo "  1) Auto   — select OS  → run latest version"
    echo "  2) Auto   — select OS  → run all versions"
    echo "  3) Auto   — ALL OS, all versions"
    echo "  4) Manual — select OS + version (full pipeline)"
    echo "  5) Manual — select OS + version (step-by-step)"
    echo "  6) Back"
    echo -n "  Select [1-6]: "
    local choice; read -r choice || return
    case "$choice" in
      1) _menu_build_auto_os_latest ;;
      2) _menu_build_auto_os_all ;;
      3) _menu_build_auto_all ;;
      4) _menu_build_manual_full ;;
      5) _menu_build_manual_step ;;
      6) return ;;
      *) echo "  Invalid choice." ;;
    esac
  done
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
