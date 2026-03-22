#!/usr/bin/env bash
# lib/state_store.sh — Read/write flag files and runtime JSON state.
set -Eeuo pipefail

# ─── Flag file helpers ────────────────────────────────────────────────────────

# Write a named flag file for a phase/os/version
# Usage: state_mark_flag <phase> <os_family> <os_version> <flag_name>
state_mark_flag() {
  local flag_path; flag_path="$(core_flag_path "$1" "$2" "$3" "$4")"
  util_ensure_parent_dir "$flag_path"
  touch "$flag_path"
}

# Clear a named flag file
# Usage: state_clear_named_flag <phase> <os_family> <os_version> <flag_name>
state_clear_named_flag() {
  local flag_path; flag_path="$(core_flag_path "$1" "$2" "$3" "$4")"
  rm -f "$flag_path"
}

# Check if a flag file exists
# Usage: state_has_flag <phase> <os_family> <os_version> <flag_name>
state_has_flag() {
  local flag_path; flag_path="$(core_flag_path "$1" "$2" "$3" "$4")"
  [[ -f "$flag_path" ]]
}

# Mark a phase as ready (sets <phase>/<os>-<ver>.ready)
# Usage: state_mark_ready <phase> <os_family> <os_version>
state_mark_ready() {
  state_clear_named_flag "$1" "$2" "$3" "failed"
  state_mark_flag "$1" "$2" "$3" "ready"
}

# Mark a phase as failed (sets <phase>/<os>-<ver>.failed, clears ready)
# Usage: state_mark_failed <phase> <os_family> <os_version>
state_mark_failed() {
  state_clear_named_flag "$1" "$2" "$3" "ready"
  state_mark_flag "$1" "$2" "$3" "failed"
}

# Check if a phase is ready for an os/version
# Usage: state_is_ready <phase> <os_family> <os_version>
state_is_ready() {
  state_has_flag "$1" "$2" "$3" "ready"
}

# ─── Runtime JSON helpers ─────────────────────────────────────────────────────

# Write (or overwrite) runtime JSON for a phase/os/version
# Usage: state_write_runtime_json <phase> <os_family> <os_version> <json_content>
state_write_runtime_json() {
  local phase="$1" os_family="$2" os_version="$3" content="$4"
  local json_path; json_path="$(core_state_json "$phase" "$os_family" "$os_version")"
  util_ensure_parent_dir "$json_path"
  printf '%s\n' "$content" > "$json_path"
  util_log_info "State JSON written: $json_path"
}

# Read a field value from a runtime JSON (uses python3 if available, else grep+sed)
# Usage: state_read_json_field <phase> <os_family> <os_version> <field>
state_read_json_field() {
  local phase="$1" os_family="$2" os_version="$3" field="$4"
  local json_path; json_path="$(core_state_json "$phase" "$os_family" "$os_version")"
  if [[ ! -f "$json_path" ]]; then
    util_log_error "state_read_json_field: file not found: $json_path"
    return 5
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
try:
    d = json.load(open('${json_path}'))
    v = d.get('${field}', '')
    print(v)
except Exception as e:
    sys.exit(1)
"
  else
    grep -o '"'"${field}"'"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_path" 2>/dev/null \
      | head -1 \
      | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'
  fi
}

# Print a summary of all phase states for a given os/version
# Usage: state_summary <os_family> <os_version>
state_summary() {
  local os_family="$1" os_version="$2"
  local phases=("sync" "import" "create" "configure" "clean" "publish")
  for p in "${phases[@]}"; do
    local flag_ready; flag_ready="$(core_flag_path "$p" "$os_family" "$os_version" "ready")"
    local flag_failed; flag_failed="$(core_flag_path "$p" "$os_family" "$os_version" "failed")"
    if [[ -f "$flag_ready" ]]; then
      echo "  ${p}: READY"
    elif [[ -f "$flag_failed" ]]; then
      echo "  ${p}: FAILED"
    else
      echo "  ${p}: pending"
    fi
  done
}
