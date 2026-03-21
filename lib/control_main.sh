#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/os_helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_jump_host.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_sync.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_git.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/runtime_helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_status.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_pipeline.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/control_cleanup.sh"

# ── Usage ──────────────────────────────────────────────────────────────────────

imagectl_control_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh
  scripts/control.sh ssh <connect|validate|info>
  scripts/control.sh git <bootstrap|sync-safe|sync-code-overwrite|sync-clean|status|branch|push> [--yes]
  scripts/control.sh pipeline <manual|auto-by-os|auto-by-os-version|status|logs> [args]
  scripts/control.sh script  <manual|auto|auto-by-os|auto-by-os-version|status|logs> [args]
  scripts/control.sh manual [args]
  scripts/control.sh auto [args]
  scripts/control.sh sync [--mode safe|code-overwrite|clean] [--yes]
  scripts/control.sh status
  scripts/control.sh logs
EOF
}

# ── SSH dispatch ───────────────────────────────────────────────────────────────

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
    validate) imagectl_check_remote_connection ;;
    info)     imagectl_ssh_info ;;
    ""|-h|--help|help) imagectl_ssh_usage ;;
    *) imagectl_die "unknown ssh subcommand: $sub" ;;
  esac
}

# ── Menu: System (SSH + Git) ───────────────────────────────────────────────────

imagectl_menu_system() {
  while true; do
    local choice
    choice="$(imagectl_select_from_list "System (จัดการระบบ)" \
      "SSH Connect    (เปิด terminal → jump host)" \
      "SSH Validate   (ทดสอบ connection)" \
      "SSH Info       (ดูข้อมูล connection)" \
      "Git Bootstrap  (เตรียม repo บน jump host ครั้งแรก)" \
      "Git Sync       (sync code → jump host)" \
      "Git Status     (ดูสถานะ git)" \
      "Back           (กลับ)")"

    case "$choice" in
      "SSH Connect"*)   imagectl_ssh_dispatch connect   || imagectl_log "ssh connect failed" ;;
      "SSH Validate"*)  imagectl_ssh_dispatch validate  || imagectl_log "ssh validate failed" ;;
      "SSH Info"*)      imagectl_ssh_dispatch info      || imagectl_log "ssh info failed" ;;
      "Git Bootstrap"*) imagectl_git_dispatch bootstrap || imagectl_log "git bootstrap failed" ;;
      "Git Sync"*)      imagectl_git_dispatch sync-safe || imagectl_log "git sync failed" ;;
      "Git Status"*)    imagectl_git_dispatch status    || imagectl_log "git status failed" ;;
      "Back"*)          break ;;
    esac
  done
}

# ── Main interactive menu ──────────────────────────────────────────────────────

imagectl_interactive_menu() {
  # Show status dashboard on startup (graceful — never dies)
  imagectl_status_show

  while true; do
    local choice
    choice="$(imagectl_select_from_list "Main Menu" \
      "1. System  (จัดการระบบ)" \
      "2. Run     (รัน pipeline)" \
      "3. Resume  (ต่อจากที่ค้าง)" \
      "4. Cleanup (ลบ resource)" \
      "5. Status  (ดูสถานะละเอียด)" \
      "6. Exit    (ออก)")"

    case "$choice" in
      "1."*) imagectl_menu_system ;;
      "2."*) imagectl_menu_run ;;
      "3."*) imagectl_menu_resume ;;
      "4."*) imagectl_menu_cleanup ;;
      "5."*) imagectl_status_detailed ;;
      "6."*) break ;;
    esac
  done
}

# ── Entry point ────────────────────────────────────────────────────────────────

imagectl_control_main() {
  imagectl_require_repo_root
  local cmd="${1:-menu}"
  shift || true

  case "$cmd" in
    menu)               imagectl_interactive_menu ;;
    help|-h|--help)     imagectl_control_usage ;;
    ssh)                imagectl_ssh_dispatch "$@" ;;
    git)                imagectl_git_dispatch "$@" ;;
    pipeline)           imagectl_pipeline_dispatch "$@" ;;
    script)             imagectl_script_dispatch "$@" ;;
    sync)               imagectl_sync "$@" ;;
    manual)             imagectl_pipeline_dispatch manual "$@" ;;
    auto)               imagectl_pipeline_dispatch auto "$@" ;;
    status)             imagectl_pipeline_dispatch status ;;
    logs)               imagectl_pipeline_dispatch logs ;;
    *)
      imagectl_control_usage
      imagectl_die "unknown command: $cmd"
      ;;
  esac
}
