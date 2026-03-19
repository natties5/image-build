#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_os.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_jump_host.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_sync.sh"

imagectl_control_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh <command> [args]

commands:
  sync      run jump-host sync/update mode
  manual    interactive menu mode
  auto      run full pipeline for one OS/version
  status    show remote repo status and recent logs
  logs      show recent remote logs
  help      show this help

examples:
  scripts/control.sh sync --mode safe
  scripts/control.sh manual
  scripts/control.sh auto --os ubuntu --version 24.04
EOF
}

imagectl_run_phase_remote() {
  local os="$1"
  local phase="$2"
  local version="${3:-}"
  local cmd=""
  cmd="$(imagectl_phase_command "$os" "$phase" "$version")" || imagectl_die "phase '$phase' not available for os '$os'"
  imagectl_log "run phase os=$os phase=$phase version=${version:-n/a}"
  imagectl_run_remote_repo_cmd "$cmd"
}

imagectl_select_os_interactive() {
  local options
  mapfile -t options < <(imagectl_list_supported_oses)
  imagectl_select_from_list "select OS" "${options[@]}"
}

imagectl_select_version_interactive() {
  local os="$1"
  local versions=()
  local selected=""
  mapfile -t versions < <(imagectl_version_list_for_os "$os")
  if [[ "${#versions[@]}" -gt 0 ]]; then
    selected="$(imagectl_select_from_list "select version for $os" "${versions[@]}")"
    printf '%s' "$selected"
    return 0
  fi
  read -r -p "enter version for $os (example 24.04): " selected
  [[ -n "$selected" ]] || imagectl_die "version is required"
  printf '%s' "$selected"
}

imagectl_manual_menu_once() {
  local os="$1"
  local version="$2"
  local action="$3"
  case "$action" in
    sync-safe) imagectl_sync --mode safe ;;
    sync-code-overwrite) imagectl_sync --mode code-overwrite ;;
    sync-clean) imagectl_sync --mode clean ;;
    preflight|download|import|create|configure|clean|publish|status|logs)
      if ! imagectl_os_is_implemented "$os"; then
        imagectl_log "os '$os' is not implemented yet"
        return 0
      fi
      imagectl_run_phase_remote "$os" "$action" "$version"
      ;;
    *)
      imagectl_die "unknown manual action: $action"
      ;;
  esac
}

imagectl_manual_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh manual
  scripts/control.sh manual --os <name> --version <x.yz> --action <action>
EOF
}

imagectl_manual() {
  local os=""
  local version=""
  local action=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --os) os="${2:-}"; shift 2 ;;
      --version) version="${2:-}"; shift 2 ;;
      --action) action="${2:-}"; shift 2 ;;
      -h|--help) imagectl_manual_usage; return 0 ;;
      *) imagectl_die "unknown manual argument: $1" ;;
    esac
  done

  imagectl_load_jump_host_config
  imagectl_check_remote_connection >/dev/null

  if [[ -n "$action" ]]; then
    os="$(imagectl_require_supported_os "${os:-ubuntu}")"
    [[ -n "$version" ]] || imagectl_die "--version is required when --action is set"
    imagectl_manual_menu_once "$os" "$version" "$action"
    return 0
  fi

  os="$(imagectl_select_os_interactive)"
  os="$(imagectl_require_supported_os "$os")"
  version="$(imagectl_select_version_interactive "$os")"

  while true; do
    local choice=""
    choice="$(imagectl_select_from_list "manual mode: os=$os version=$version" \
      "sync-safe" \
      "sync-code-overwrite" \
      "sync-clean" \
      "preflight" \
      "download" \
      "import" \
      "create" \
      "configure" \
      "clean" \
      "publish" \
      "status" \
      "logs" \
      "change-version" \
      "change-os" \
      "exit")"
    case "$choice" in
      change-version)
        version="$(imagectl_select_version_interactive "$os")"
        ;;
      change-os)
        os="$(imagectl_select_os_interactive)"
        os="$(imagectl_require_supported_os "$os")"
        version="$(imagectl_select_version_interactive "$os")"
        ;;
      exit)
        break
        ;;
      *)
        if imagectl_manual_menu_once "$os" "$version" "$choice"; then
          imagectl_log "action done: $choice"
          imagectl_log "logs directory: $JUMP_HOST_REPO_PATH/logs"
        fi
        ;;
    esac
  done
}

imagectl_auto_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh auto --os <name> --version <x.yz> [--stop-before <phase>] [--resume-from <phase>] [--fail-fast yes|no] [--cleanup-mode <value>]
EOF
}

imagectl_auto() {
  local os=""
  local version=""
  local stop_before=""
  local resume_from=""
  local fail_fast="yes"
  local cleanup_mode="default"
  local phases=(preflight download import create configure clean publish)
  local idx=0
  local start_idx=0
  local stop_idx=-1
  local found_resume="no"
  local found_stop="no"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --os) os="${2:-}"; shift 2 ;;
      --version) version="${2:-}"; shift 2 ;;
      --stop-before) stop_before="${2:-}"; shift 2 ;;
      --resume-from) resume_from="${2:-}"; shift 2 ;;
      --fail-fast) fail_fast="${2:-}"; shift 2 ;;
      --cleanup-mode) cleanup_mode="${2:-}"; shift 2 ;;
      -h|--help) imagectl_auto_usage; return 0 ;;
      *) imagectl_die "unknown auto argument: $1" ;;
    esac
  done

  os="$(imagectl_require_supported_os "$os")"
  [[ -n "$version" ]] || imagectl_die "--version is required"

  if ! imagectl_os_is_implemented "$os"; then
    imagectl_die "os '$os' is not implemented yet"
  fi

  imagectl_load_jump_host_config
  imagectl_check_remote_connection >/dev/null

  if [[ -n "$resume_from" ]]; then
    for idx in "${!phases[@]}"; do
      if [[ "${phases[$idx]}" == "$resume_from" ]]; then
        start_idx="$idx"
        found_resume="yes"
        break
      fi
    done
    [[ "$found_resume" == "yes" ]] || imagectl_die "invalid --resume-from phase: $resume_from"
  fi

  if [[ -n "$stop_before" ]]; then
    for idx in "${!phases[@]}"; do
      if [[ "${phases[$idx]}" == "$stop_before" ]]; then
        stop_idx="$idx"
        found_stop="yes"
        break
      fi
    done
    [[ "$found_stop" == "yes" ]] || imagectl_die "invalid --stop-before phase: $stop_before"
  fi

  imagectl_log "auto start os=$os version=$version fail_fast=$fail_fast cleanup_mode=$cleanup_mode"
  for idx in "${!phases[@]}"; do
    if (( idx < start_idx )); then
      continue
    fi
    if (( stop_idx >= 0 && idx >= stop_idx )); then
      imagectl_log "auto stop-before reached phase=${phases[$idx]}"
      break
    fi
    if ! imagectl_run_phase_remote "$os" "${phases[$idx]}" "$version"; then
      imagectl_log "phase failed: ${phases[$idx]}"
      if [[ "$fail_fast" == "yes" ]]; then
        return 1
      fi
    fi
  done
  imagectl_log "auto done os=$os version=$version"
}

imagectl_status() {
  imagectl_load_jump_host_config
  imagectl_check_remote_connection >/dev/null
  imagectl_run_remote_repo_cmd "git status --short --branch && echo '--- logs ---' && ls -1 logs | tail -n 15"
}

imagectl_logs() {
  imagectl_load_jump_host_config
  imagectl_check_remote_connection >/dev/null
  imagectl_run_remote_repo_cmd "ls -1 logs | tail -n 30"
}

imagectl_control_main() {
  imagectl_require_repo_root
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    help|-h|--help) imagectl_control_usage ;;
    sync) imagectl_sync "$@" ;;
    manual) imagectl_manual "$@" ;;
    auto) imagectl_auto "$@" ;;
    status) imagectl_status ;;
    logs) imagectl_logs ;;
    *)
      imagectl_control_usage
      imagectl_die "unknown command: $cmd"
      ;;
  esac
}
