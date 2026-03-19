#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_sync_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh sync [--mode safe|code-overwrite|clean] [--backend remote-git|push-local] [--yes]

modes:
  safe            fetch + checkout + pull (non-destructive)
  code-overwrite  hard-reset tracked code to origin/<branch>
  clean           code-overwrite + safe runtime/work cleanup

backend:
  remote-git      run git operations on jump host repo (default)
  push-local      scaffold only (not implemented yet)
EOF
}

imagectl_sync_require_confirmation() {
  local mode="$1"
  local assume_yes="${2:-no}"
  if [[ "$mode" == "safe" ]]; then
    return 0
  fi
  if [[ "$assume_yes" == "yes" ]]; then
    return 0
  fi
  imagectl_is_tty || imagectl_die "destructive mode '$mode' requires --yes in non-interactive mode"
  imagectl_prompt_yes_no "confirm destructive sync mode: $mode" || imagectl_die "sync cancelled"
}

imagectl_run_sync_remote_git() {
  local mode="$1"
  local branch_q
  branch_q="$(printf '%q' "$JUMP_HOST_BRANCH")"

  case "$mode" in
    safe)
      imagectl_run_remote_repo_cmd "git fetch --prune origin && git checkout $branch_q && git pull --ff-only origin $branch_q"
      ;;
    code-overwrite)
      imagectl_run_remote_repo_cmd "git fetch --prune origin && git checkout $branch_q && git reset --hard origin/$JUMP_HOST_BRANCH"
      ;;
    clean)
      imagectl_run_remote_repo_cmd "git fetch --prune origin && git checkout $branch_q && git reset --hard origin/$JUMP_HOST_BRANCH && git clean -fd -e deploy/local -e deploy/local/** && rm -f logs/*.log && rm -rf cache/* tmp/* runtime/state/*"
      ;;
    *)
      imagectl_die "unsupported sync mode: $mode"
      ;;
  esac
}

imagectl_sync() {
  local mode="safe"
  local backend="remote-git"
  local assume_yes="no"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        mode="${2:-}"
        shift 2
        ;;
      --backend)
        backend="${2:-}"
        shift 2
        ;;
      --yes)
        assume_yes="yes"
        shift
        ;;
      -h|--help)
        imagectl_sync_usage
        return 0
        ;;
      *)
        imagectl_die "unknown sync argument: $1"
        ;;
    esac
  done

  case "$mode" in
    safe|code-overwrite|clean) ;;
    *) imagectl_die "invalid sync mode: $mode" ;;
  esac
  case "$backend" in
    remote-git|push-local) ;;
    *) imagectl_die "invalid sync backend: $backend" ;;
  esac

  imagectl_sync_require_confirmation "$mode" "$assume_yes"
  imagectl_load_jump_host_config

  if [[ "$backend" == "push-local" ]]; then
    imagectl_die "sync backend 'push-local' is scaffolded but not implemented yet"
  fi

  imagectl_log "sync start mode=$mode backend=$backend branch=$JUMP_HOST_BRANCH"
  imagectl_run_sync_remote_git "$mode"
  imagectl_log "sync done mode=$mode"
}
