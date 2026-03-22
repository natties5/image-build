#!/usr/bin/env bash
# scripts/control.sh — Single user-facing entrypoint for the image-build pipeline.
# Usage:
#   bash scripts/control.sh                                  # interactive menu
#   bash scripts/control.sh --help
#   bash scripts/control.sh sync dry-run --os ubuntu
#   bash scripts/control.sh sync dry-run --os ubuntu --version 24.04
#   bash scripts/control.sh sync download --os ubuntu --version 24.04
#   bash scripts/control.sh settings validate-auth
#   bash scripts/control.sh status dashboard
#   bash scripts/control.sh cleanup reconcile
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"

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
  echo ""
  echo "--- Settings ---"
  echo "  1) Validate OpenStack Auth"
  echo "  2) Show Current Settings"
  echo "  3) Validate All Settings"
  echo "  4) Back"
  echo -n "  Select [1-4]: "
  local choice; read -r choice || return
  case "$choice" in
    1) cmd_settings_validate_auth ;;
    2) cmd_settings_show ;;
    3) cmd_settings_validate ;;
    4) return ;;
    *) echo "Invalid choice." ;;
  esac
}

cmd_settings_validate_auth() {
  util_log_info "NOT IMPLEMENTED: settings validate-auth — see 06_OPENSTACK_PIPELINE_DESIGN.md"
  echo "  [TODO] validate-auth not yet implemented."
}

cmd_settings_show() {
  echo "  OpenStack settings: ${OPENSTACK_ENV}"
  [[ -f "$OPENSTACK_ENV" ]] && cat "$OPENSTACK_ENV" || echo "  (file not found)"
  echo "  Guest access settings: ${GUEST_ACCESS_ENV}"
  [[ -f "$GUEST_ACCESS_ENV" ]] && cat "$GUEST_ACCESS_ENV" || echo "  (file not found)"
}

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
        validate-auth) cmd_settings_validate_auth ;;
        show)          cmd_settings_show ;;
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

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  core_ensure_runtime_dirs

  if [[ $# -eq 0 ]]; then
    run_interactive_menu
  else
    dispatch_command "$@"
  fi
}

main "$@"
