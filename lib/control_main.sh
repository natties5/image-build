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
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_git.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_runtime_config.sh"

imagectl_control_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh
  scripts/control.sh ssh <connect|validate|info>
  scripts/control.sh git <bootstrap|sync-safe|sync-code-overwrite|sync-clean|status|branch|push> [--yes]
  scripts/control.sh pipeline <manual|auto-by-os|auto-by-os-version|status|logs> [args]
  scripts/control.sh script <manual|auto|auto-by-os|auto-by-os-version|status|logs> [args]
  scripts/control.sh manual [args]
  scripts/control.sh auto [args]
  scripts/control.sh sync [--mode safe|code-overwrite|clean] [--yes]
  scripts/control.sh status
  scripts/control.sh logs
EOF
}

imagectl_phase_requires_version() {
  local phase="$1"
  case "$phase" in
    import|create|configure|clean|publish) return 0 ;;
    *) return 1 ;;
  esac
}

imagectl_run_phase_remote() {
  local os="$1"
  local phase="$2"
  local version="${3:-}"
  local cmd=""
  local expected_q=""

  cmd="$(imagectl_phase_command "$os" "$phase" "$version")" || imagectl_die "phase '$phase' not available for os '$os'"
  imagectl_require_remote_repo_for_script

  if [[ "$phase" == "preflight" && -n "${EXPECTED_PROJECT_NAME:-}" ]]; then
    expected_q="$(printf '%q' "$EXPECTED_PROJECT_NAME")"
    cmd="EXPECTED_PROJECT_NAME=$expected_q $cmd"
  fi

  imagectl_log "run phase os=$os phase=$phase version=${version:-n/a}"
  imagectl_run_remote_repo_cmd "$cmd"
}

imagectl_select_os_interactive() {
  local options
  mapfile -t options < <(imagectl_list_supported_oses)
  imagectl_select_from_list "select OS" "${options[@]}"
}

imagectl_select_version_from_manifest_remote_interactive() {
  local os="$1"
  local versions=()
  mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")
  imagectl_select_from_list "select version for $os" "${versions[@]}"
}

imagectl_prepare_remote_pipeline_context() {
  imagectl_load_jump_host_config
  imagectl_check_remote_connection >/dev/null
  imagectl_require_remote_repo_for_script
}

imagectl_run_discover_for_os() {
  local os="$1"
  if ! imagectl_os_is_implemented "$os"; then
    imagectl_die "os '$os' is not implemented yet"
  fi
  imagectl_log "run download/discover for os=$os"
  imagectl_run_phase_remote "$os" download
}

imagectl_manual_menu_once() {
  local os="$1"
  local version="$2"
  local action="$3"

  case "$action" in
    preflight|import|create|configure|clean|publish)
      if imagectl_phase_requires_version "$action"; then
        [[ -n "$version" ]] || imagectl_die "version is required for action '$action'"
      fi
      if [[ "$action" == "create" || "$action" == "configure" || "$action" == "publish" ]]; then
        imagectl_runtime_prepare_for_action "$action"
      fi
      imagectl_run_phase_remote "$os" "$action" "$version"
      ;;
    download)
      imagectl_run_phase_remote "$os" download
      ;;
    status)
      imagectl_require_remote_repo_for_script
      imagectl_run_remote_repo_cmd "git status --short --branch"
      ;;
    logs)
      imagectl_require_remote_repo_for_script
      imagectl_run_remote_repo_cmd "ls -1 logs | tail -n 30"
      ;;
    *)
      imagectl_die "unknown manual action: $action"
      ;;
  esac
}

imagectl_manual_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh pipeline manual
  scripts/control.sh script manual
  scripts/control.sh manual
  scripts/control.sh manual --os <name> --version <x.yz> --action <action>
EOF
}

imagectl_manual_prepare_selection() {
  local os="$1"
  local selected_version=""

  imagectl_run_discover_for_os "$os"
  selected_version="$(imagectl_select_version_from_manifest_remote_interactive "$os")"
  printf '%s' "$selected_version"
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

  imagectl_prepare_remote_pipeline_context

  if [[ -n "$action" ]]; then
    os="$(imagectl_require_supported_os "${os:-ubuntu}")"
    if ! imagectl_os_is_implemented "$os"; then
      imagectl_die "os '$os' is not implemented yet"
    fi
    if imagectl_phase_requires_version "$action"; then
      [[ -n "$version" ]] || imagectl_die "--version is required for action '$action'"
    fi
    imagectl_manual_menu_once "$os" "$version" "$action"
    return 0
  fi

  os="$(imagectl_select_os_interactive)"
  os="$(imagectl_require_supported_os "$os")"
  version="$(imagectl_manual_prepare_selection "$os")"

  while true; do
    local choice=""
    choice="$(imagectl_select_from_list "manual mode: os=$os version=$version" \
      "preflight" \
      "import" \
      "create" \
      "configure" \
      "clean" \
      "publish" \
      "status" \
      "logs" \
      "change-version" \
      "change-os" \
      "back")"
    case "$choice" in
      change-version)
        version="$(imagectl_select_version_from_manifest_remote_interactive "$os")"
        ;;
      change-os)
        os="$(imagectl_select_os_interactive)"
        os="$(imagectl_require_supported_os "$os")"
        version="$(imagectl_manual_prepare_selection "$os")"
        ;;
      back)
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

imagectl_auto_phase_list() {
  printf '%s\n' preflight import create configure clean publish
}

imagectl_auto_run_phase_sequence() {
  local os="$1"
  local version="$2"
  local fail_fast="${3:-yes}"
  local phases=()
  local phase=""

  mapfile -t phases < <(imagectl_auto_phase_list)
  for phase in "${phases[@]}"; do
    if ! imagectl_run_phase_remote "$os" "$phase" "$version"; then
      imagectl_log "phase failed: $phase (os=$os version=$version)"
      if [[ "$fail_fast" == "yes" ]]; then
        return 1
      fi
    fi
  done
}

imagectl_auto_by_os_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh pipeline auto-by-os --os <name> [--fail-fast yes|no]
  scripts/control.sh script auto-by-os --os <name> [--fail-fast yes|no]
EOF
}

imagectl_auto_by_os() {
  local os=""
  local fail_fast="yes"
  local versions=()
  local -a results=()
  local version=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --os) os="${2:-}"; shift 2 ;;
      --fail-fast) fail_fast="${2:-}"; shift 2 ;;
      -h|--help) imagectl_auto_by_os_usage; return 0 ;;
      *) imagectl_die "unknown auto-by-os argument: $1" ;;
    esac
  done

  imagectl_prepare_remote_pipeline_context

  if [[ -z "$os" ]]; then
    os="$(imagectl_select_os_interactive)"
  fi
  os="$(imagectl_require_supported_os "$os")"
  if ! imagectl_os_is_implemented "$os"; then
    imagectl_die "os '$os' is not implemented yet"
  fi

  imagectl_run_discover_for_os "$os"
  mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")
  imagectl_runtime_prepare_for_full_pipeline

  imagectl_log "auto-by-os start os=$os discovered_versions=${#versions[@]} fail_fast=$fail_fast"
  for version in "${versions[@]}"; do
    if imagectl_auto_run_phase_sequence "$os" "$version" "$fail_fast"; then
      results+=("$version:success")
    else
      results+=("$version:failed")
      if [[ "$fail_fast" == "yes" ]]; then
        break
      fi
    fi
  done

  imagectl_log "auto-by-os summary"
  printf '%s\n' "${results[@]}" | sed 's/^/  /'
}

imagectl_auto_by_os_version_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh pipeline auto-by-os-version --os <name> [--version <x.yz>] [--fail-fast yes|no]
  scripts/control.sh script auto --os <name> --version <x.yz> [--fail-fast yes|no]
  scripts/control.sh auto --os <name> --version <x.yz> [--fail-fast yes|no]
EOF
}

imagectl_auto_by_os_version() {
  local os=""
  local version=""
  local fail_fast="yes"
  local versions=()
  local found="no"
  local v=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --os) os="${2:-}"; shift 2 ;;
      --version) version="${2:-}"; shift 2 ;;
      --fail-fast) fail_fast="${2:-}"; shift 2 ;;
      --stop-before|--resume-from|--cleanup-mode)
        # kept for compatibility with previous interface; ignored in simplified flow
        shift 2
        ;;
      -h|--help) imagectl_auto_by_os_version_usage; return 0 ;;
      *) imagectl_die "unknown auto-by-os-version argument: $1" ;;
    esac
  done

  imagectl_prepare_remote_pipeline_context

  if [[ -z "$os" ]]; then
    os="$(imagectl_select_os_interactive)"
  fi
  os="$(imagectl_require_supported_os "$os")"
  if ! imagectl_os_is_implemented "$os"; then
    imagectl_die "os '$os' is not implemented yet"
  fi

  imagectl_run_discover_for_os "$os"
  mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")
  imagectl_runtime_prepare_for_full_pipeline

  if [[ -z "$version" ]]; then
    version="$(imagectl_select_from_list "select version for auto-by-os-version (os=$os)" "${versions[@]}")"
  else
    for v in "${versions[@]}"; do
      if [[ "$v" == "$version" ]]; then
        found="yes"
        break
      fi
    done
    [[ "$found" == "yes" ]] || imagectl_die "version '$version' was not discovered in manifest for os '$os'"
  fi

  imagectl_log "auto-by-os-version start os=$os version=$version fail_fast=$fail_fast"
  imagectl_auto_run_phase_sequence "$os" "$version" "$fail_fast"
  imagectl_log "auto-by-os-version done os=$os version=$version"
}

imagectl_pipeline_status() {
  imagectl_prepare_remote_pipeline_context
  imagectl_run_remote_repo_cmd "git status --short --branch && echo '--- logs ---' && ls -1 logs | tail -n 15"
}

imagectl_pipeline_logs() {
  imagectl_prepare_remote_pipeline_context
  imagectl_run_remote_repo_cmd "ls -1 logs | tail -n 30"
}

imagectl_ssh_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh ssh <connect|validate|info>
EOF
}

imagectl_ssh_dispatch() {
  local sub="${1:-}"
  imagectl_load_jump_host_config
  case "$sub" in
    connect)
      imagectl_log "opening SSH session to $(imagectl_jump_target)"
      imagectl_ssh_connect_interactive
      ;;
    validate)
      imagectl_check_remote_connection
      ;;
    info)
      imagectl_ssh_info
      ;;
    ""|-h|--help|help)
      imagectl_ssh_usage
      ;;
    *)
      imagectl_die "unknown ssh subcommand: $sub"
      ;;
  esac
}

imagectl_pipeline_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh pipeline <manual|auto-by-os|auto-by-os-version|status|logs> [args]

compatibility aliases:
  scripts/control.sh script <manual|auto|auto-by-os|auto-by-os-version|status|logs> [args]
  scripts/control.sh auto --os <name> --version <x.yz>
EOF
}

imagectl_pipeline_dispatch() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    manual) imagectl_manual "$@" ;;
    auto-by-os) imagectl_auto_by_os "$@" ;;
    auto-by-os-version) imagectl_auto_by_os_version "$@" ;;
    auto) imagectl_auto_by_os_version "$@" ;;
    status) imagectl_pipeline_status ;;
    logs) imagectl_pipeline_logs ;;
    ""|-h|--help|help) imagectl_pipeline_usage ;;
    *) imagectl_die "unknown pipeline subcommand: $sub" ;;
  esac
}

imagectl_script_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh script <manual|auto|auto-by-os|auto-by-os-version|status|logs> [args]

note: 'script' is kept as a compatibility alias for 'pipeline'.
EOF
}

imagectl_script_dispatch() {
  local sub="${1:-}"
  shift || true

  case "$sub" in
    manual|auto|auto-by-os|auto-by-os-version|status|logs)
      imagectl_pipeline_dispatch "$sub" "$@"
      ;;
    ""|-h|--help|help)
      imagectl_script_usage
      ;;
    *)
      imagectl_die "unknown script subcommand: $sub"
      ;;
  esac
}

imagectl_menu_ssh() {
  while true; do
    local choice=""
    choice="$(imagectl_select_from_list "SSH menu" "connect" "validate" "info" "back")"
    case "$choice" in
      connect) imagectl_ssh_dispatch connect ;;
      validate) imagectl_ssh_dispatch validate ;;
      info) imagectl_ssh_dispatch info ;;
      back) break ;;
    esac
  done
}

imagectl_menu_git() {
  while true; do
    local choice=""
    choice="$(imagectl_select_from_list "Git menu" \
      "bootstrap-remote-repo" \
      "sync-safe" \
      "sync-code-overwrite" \
      "sync-clean" \
      "status" \
      "branch-info" \
      "push" \
      "back")"
    case "$choice" in
      bootstrap-remote-repo) imagectl_git_dispatch bootstrap ;;
      sync-safe) imagectl_git_dispatch sync-safe ;;
      sync-code-overwrite) imagectl_git_dispatch sync-code-overwrite ;;
      sync-clean) imagectl_git_dispatch sync-clean ;;
      status) imagectl_git_dispatch status ;;
      branch-info) imagectl_git_dispatch branch ;;
      push) imagectl_git_dispatch push ;;
      back) break ;;
    esac
  done
}

imagectl_menu_pipeline() {
  while true; do
    local choice=""
    choice="$(imagectl_select_from_list "Pipeline menu" "Manual" "Auto by OS" "Auto by OS Version" "Status" "Logs" "Back")"
    case "$choice" in
      "Manual") imagectl_pipeline_dispatch manual ;;
      "Auto by OS") imagectl_pipeline_dispatch auto-by-os ;;
      "Auto by OS Version") imagectl_pipeline_dispatch auto-by-os-version ;;
      "Status") imagectl_pipeline_dispatch status ;;
      "Logs") imagectl_pipeline_dispatch logs ;;
      "Back") break ;;
    esac
  done
}

imagectl_interactive_menu() {
  while true; do
    local choice=""
    choice="$(imagectl_select_from_list "Main menu" "SSH" "Git" "Pipeline" "Exit")"
    case "$choice" in
      SSH) imagectl_menu_ssh ;;
      Git) imagectl_menu_git ;;
      Pipeline) imagectl_menu_pipeline ;;
      Exit) break ;;
    esac
  done
}

imagectl_control_main() {
  imagectl_require_repo_root
  local cmd="${1:-menu}"
  shift || true

  case "$cmd" in
    menu) imagectl_interactive_menu ;;
    help|-h|--help) imagectl_control_usage ;;
    ssh) imagectl_ssh_dispatch "$@" ;;
    git) imagectl_git_dispatch "$@" ;;
    pipeline) imagectl_pipeline_dispatch "$@" ;;
    script) imagectl_script_dispatch "$@" ;;
    sync) imagectl_sync "$@" ;;
    manual) imagectl_pipeline_dispatch manual "$@" ;;
    auto) imagectl_pipeline_dispatch auto "$@" ;;
    status) imagectl_pipeline_dispatch status ;;
    logs) imagectl_pipeline_dispatch logs ;;
    *)
      imagectl_control_usage
      imagectl_die "unknown command: $cmd"
      ;;
  esac
}
