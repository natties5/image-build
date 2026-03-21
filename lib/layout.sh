#!/usr/bin/env bash
# lib/layout.sh
# Legacy layout wrapper, now points to core_paths.sh

set -Eeuo pipefail

# Find the directory of this script, then source core_paths.sh
_layout_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$_layout_dir/core_paths.sh"

imagectl_init_layout() {
  local repo_root="${1:-}"
  # Already initialized by core_paths.sh, kept for compat
  imagectl_init_core_paths
}

imagectl_ensure_layout_dirs() {
  # Now handles all core dirs
  imagectl_ensure_core_dirs
}

imagectl_resolve_summary_for_read() {
  if [[ -f "$SUMMARY_FILE" ]]; then
    printf '%s' "$SUMMARY_FILE"
    return 0
  fi
  if [[ -f "$LEGACY_SUMMARY_FILE" ]]; then
    printf '%s' "$LEGACY_SUMMARY_FILE"
    return 0
  fi
  printf '%s' "$SUMMARY_FILE"
}

imagectl_sync_file_to_legacy() {
  local src="$1"
  local dst="$2"
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname -- "$dst")"
  cp -f "$src" "$dst"
}
