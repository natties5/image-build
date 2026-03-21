#!/usr/bin/env bash
# lib/state_store.sh — Read/write flag files and runtime JSON state.
# TODO: implement all functions — see /rebuild-project-doc/01_START_PROJECT_BLUEPRINT.md §8
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

# Read a field value from a runtime JSON (requires jq or python3)
# Usage: state_read_json_field <phase> <os_family> <os_version> <field>
state_read_json_field() {
  # TODO: implement — see /rebuild-project-doc/01_START_PROJECT_BLUEPRINT.md §8
  util_log_info "NOT IMPLEMENTED: state_read_json_field $*"
  return 0
}

# Print a summary of all phase states for a given os/version
# Usage: state_summary <os_family> <os_version>
state_summary() {
  # TODO: implement — see /rebuild-project-doc/07_MENU_DESIGN.md §5 Dashboard
  util_log_info "NOT IMPLEMENTED: state_summary $*"
  return 0
}
