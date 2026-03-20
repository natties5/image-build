#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_remote_repo_state() {
  local repo_q
  repo_q="$(printf '%q' "$JUMP_HOST_REPO_PATH")"
  imagectl_run_remote_cmd "set -euo pipefail; p=$repo_q; \
if [[ ! -e \"\$p\" ]]; then echo missing; \
elif [[ -d \"\$p/.git\" ]]; then echo git_repo; \
elif [[ -d \"\$p\" ]]; then if [[ -z \"\$(ls -A \"\$p\")\" ]]; then echo empty_dir; else echo non_repo_non_empty; fi; \
else echo path_not_directory; fi"
}

imagectl_remote_repo_parent() {
  dirname -- "$JUMP_HOST_REPO_PATH"
}

imagectl_bootstrap_remote_repo() {
  local state
  local repo_q
  local parent_q
  local branch_q
  local repo_url_q

  state="$(imagectl_remote_repo_state)"
  repo_q="$(printf '%q' "$JUMP_HOST_REPO_PATH")"
  parent_q="$(printf '%q' "$(imagectl_remote_repo_parent)")"
  branch_q="$(printf '%q' "$JUMP_HOST_BRANCH")"
  repo_url_q="$(printf '%q' "$JUMP_HOST_REPO_URL")"

  case "$state" in
    missing)
      imagectl_log "remote path missing; bootstrap clone to $JUMP_HOST_REPO_PATH"
      imagectl_run_remote_cmd "set -euo pipefail; mkdir -p $parent_q; git clone $repo_url_q $repo_q"
      ;;
    empty_dir)
      imagectl_log "remote path exists but empty; bootstrap clone to $JUMP_HOST_REPO_PATH"
      imagectl_run_remote_cmd "set -euo pipefail; git clone $repo_url_q $repo_q"
      ;;
    git_repo)
      imagectl_log "remote repo exists; updating branch checkout"
      ;;
    non_repo_non_empty)
      imagectl_die "remote path exists and contains non-repo files: $JUMP_HOST_REPO_PATH (refusing to modify)"
      ;;
    path_not_directory)
      imagectl_die "remote path exists but is not a directory: $JUMP_HOST_REPO_PATH"
      ;;
    *)
      imagectl_die "unexpected remote repo state: $state"
      ;;
  esac

  imagectl_run_remote_repo_cmd "git fetch --prune origin && git checkout $branch_q && git pull --ff-only origin $branch_q"
  imagectl_log "bootstrap complete: $JUMP_HOST_REPO_PATH ($JUMP_HOST_BRANCH)"
}

imagectl_require_remote_repo_for_script() {
  local state
  state="$(imagectl_remote_repo_state)"
  if [[ "$state" == "git_repo" ]]; then
    return 0
  fi

  imagectl_log "remote repo is not ready (state=$state)"
  if imagectl_is_tty; then
    if imagectl_prompt_yes_no "bootstrap remote repo now?"; then
      imagectl_bootstrap_remote_repo
      return 0
    fi
  fi
  imagectl_die "remote repo not ready; run: scripts/control.sh git bootstrap"
}

imagectl_git_status() {
  imagectl_require_remote_repo_for_script
  imagectl_run_remote_repo_cmd "git status --short --branch"
}

imagectl_git_branch_info() {
  imagectl_require_remote_repo_for_script
  imagectl_run_remote_repo_cmd "git branch -vv && echo '---' && git remote -v"
}

imagectl_git_push() {
  local assume_yes="${1:-no}"
  imagectl_require_remote_repo_for_script
  if [[ "$assume_yes" != "yes" ]]; then
    if ! imagectl_is_tty; then
      imagectl_die "git push requires --yes in non-interactive mode"
    fi
    imagectl_prompt_yes_no "push current branch to origin?" || imagectl_die "push cancelled"
  fi
  imagectl_run_remote_repo_cmd "current=\$(git rev-parse --abbrev-ref HEAD); git push origin \"\$current\""
}

imagectl_git_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh git <bootstrap|sync-safe|sync-code-overwrite|sync-clean|status|branch|push> [--yes]
EOF
}

imagectl_git_dispatch() {
  local sub="${1:-}"
  local assume_yes="no"
  local -a sync_args=()
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) assume_yes="yes"; shift ;;
      -h|--help) imagectl_git_usage; return 0 ;;
      *) imagectl_die "unknown git argument: $1" ;;
    esac
  done

  imagectl_load_jump_host_config
  imagectl_check_remote_connection >/dev/null

  case "$sub" in
    bootstrap) imagectl_bootstrap_remote_repo ;;
    sync-safe)
      imagectl_sync --mode safe
      ;;
    sync-code-overwrite)
      [[ "$assume_yes" == "yes" ]] && sync_args+=(--yes)
      imagectl_sync --mode code-overwrite "${sync_args[@]}"
      ;;
    sync-clean)
      [[ "$assume_yes" == "yes" ]] && sync_args+=(--yes)
      imagectl_sync --mode clean "${sync_args[@]}"
      ;;
    status) imagectl_git_status ;;
    branch) imagectl_git_branch_info ;;
    push) imagectl_git_push "$assume_yes" ;;
    ""|-h|--help|help) imagectl_git_usage ;;
    *) imagectl_die "unknown git subcommand: $sub" ;;
  esac
}
