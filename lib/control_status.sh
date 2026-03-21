#!/usr/bin/env bash
set -Eeuo pipefail

# Global state map loaded from remote (os/version/phase → status)
declare -A _IMAGECTL_STATE_MAP=()

# ── Helpers ──────────────────────────────────────────────────────────────────

imagectl_status_display_phases() {
  printf '%s\n' download import vm configure publish
}

imagectl_status_phase_col_header() {
  case "$1" in
    download)  printf 'DL    ' ;;
    import)    printf 'IMPORT' ;;
    vm)        printf 'VM    ' ;;
    configure) printf 'CONFIG' ;;
    publish)   printf 'PUBLSH' ;;
    *)         printf '%6.6s' "$1" ;;
  esac
}

imagectl_status_symbol() {
  case "${1:-}" in
    success) printf '[✓]' ;;
    failed)  printf '[✗]' ;;
    running) printf '[⋯]' ;;
    *)       printf '[-]' ;;
  esac
}

# ── Remote state loading ──────────────────────────────────────────────────────

# Read runtime/state/*/*/last-*.env from remote.
# Outputs "os/version/phase=status" lines.
imagectl_status_read_remote_states_raw() {
  local cmd
  cmd='set -euo pipefail
sd=runtime/state
[[ -d "$sd" ]] || exit 0
while IFS= read -r f; do
  s="$(grep -m1 "^STATUS=" "$f" 2>/dev/null | cut -d= -f2- || true)"
  r="${f#"$sd/"}"
  o="${r%%/*}"; r="${r#*/}"
  v="${r%%/*}"; p="${r#*/}"
  p="${p#last-}"; p="${p%.env}"
  printf "%s/%s/%s=%s\n" "$o" "$v" "$p" "$s"
done < <(find "$sd" -name "last-*.env" -type f 2>/dev/null | sort)'
  imagectl_run_remote_repo_cmd "$cmd" 2>/dev/null || true
}

# Populate _IMAGECTL_STATE_MAP from remote state files.
imagectl_status_load() {
  _IMAGECTL_STATE_MAP=()
  local line key val
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    _IMAGECTL_STATE_MAP["$key"]="$val"
  done < <(imagectl_status_read_remote_states_raw)
}

# Look up a state value by "os/version/phase" key.
imagectl_status_get() {
  printf '%s' "${_IMAGECTL_STATE_MAP[${1}]:-}"
}

# ── Config-based version list ─────────────────────────────────────────────────

# List versions for an OS from local config/os/[os]/*.env (excluding base.env).
imagectl_status_versions_for_os() {
  local os="$1"
  local dir="$IMAGECTL_REPO_ROOT/config/os/$os"
  [[ -d "$dir" ]] || return 0
  local f fname
  for f in "$dir"/*.env; do
    [[ -f "$f" ]] || continue
    fname="$(basename "$f" .env)"
    [[ "$fname" == "base" ]] && continue
    printf '%s\n' "$fname"
  done | sort -V
}

# ── Dashboard ─────────────────────────────────────────────────────────────────

# Print the status dashboard.
# Args: connected(yes|no)  jump_target  project
imagectl_status_dashboard_print() {
  local connected="${1:-no}"
  local jump_target="${2:-}"
  local project="${3:-}"

  local phases=()
  mapfile -t phases < <(imagectl_status_display_phases)

  local conn_str
  if [[ "$connected" == "yes" ]]; then
    conn_str="● Connected   ${jump_target}"
  else
    conn_str="○ Disconnected"
  fi

  printf '\n'
  printf '═══════════════════════════════════════════════════════\n'
  printf '  Image Build System\n'
  printf '═══════════════════════════════════════════════════════\n'
  printf ' Connection : %s\n' "$conn_str"
  printf ' Project    : %s\n' "${project:-(not selected)}"
  printf '\n'

  # Header row
  printf ' %-20s' "OS"
  local ph
  for ph in "${phases[@]}"; do
    printf '  %-6s' "$(imagectl_status_phase_col_header "$ph")"
  done
  printf '\n'
  printf ' ──────────────────────────────────────────────────────\n'

  # Data rows
  local oses=() os versions=() version st
  mapfile -t oses < <(imagectl_list_supported_oses)
  for os in "${oses[@]}"; do
    mapfile -t versions < <(imagectl_status_versions_for_os "$os")
    [[ "${#versions[@]}" -gt 0 ]] || continue
    for version in "${versions[@]}"; do
      printf ' %-20s' "$os $version"
      for ph in "${phases[@]}"; do
        st="$(imagectl_status_get "$os/$version/$ph")"
        printf '  %-6s' "$(imagectl_status_symbol "$st")"
      done
      printf '\n'
    done
  done

  printf '═══════════════════════════════════════════════════════\n'
  printf '\n'
}

# ── Public API ────────────────────────────────────────────────────────────────

# Show startup dashboard (graceful — does not die if SSH is unavailable).
imagectl_status_show() {
  local connected="no"
  local jump_target="(not configured)"
  local project=""
  # Try to load jump host config (graceful — skip if settings/ not set up yet)
  if ( imagectl_load_jump_host_config ) >/dev/null 2>&1; then
    imagectl_load_jump_host_config >/dev/null 2>&1
    jump_target="$(imagectl_jump_target)"
    project="${EXPECTED_PROJECT_NAME:-}"
    if imagectl_check_remote_connection >/dev/null 2>&1; then
      connected="yes"
      imagectl_status_load
    fi
  fi

  if [[ -z "$project" ]]; then
    project="$(imagectl_runtime_effective_local_value "EXPECTED_PROJECT_NAME" 2>/dev/null || true)"
  fi

  imagectl_status_dashboard_print "$connected" "$jump_target" "$project"
}

# Detailed status view for menu option 5.
imagectl_status_detailed() {
  imagectl_status_show

  if ( imagectl_load_jump_host_config ) >/dev/null 2>&1; then
    imagectl_load_jump_host_config >/dev/null 2>&1
    if imagectl_check_remote_connection >/dev/null 2>&1; then
      printf '--- Remote Git Status ---\n'
      imagectl_run_remote_repo_cmd "git status --short --branch" || true
      printf '\n--- Recent Logs ---\n'
      imagectl_run_remote_repo_cmd \
        'ls -1t logs/summary/ 2>/dev/null | head -10 || ls -1 logs/ 2>/dev/null | tail -15 || echo "(no logs)"' \
        || true
    fi
  fi
}
