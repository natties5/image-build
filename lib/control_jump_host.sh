#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_load_jump_host_config() {
  local tracked_file="$IMAGECTL_REPO_ROOT/deploy/control.env.example"
  local local_file="$IMAGECTL_REPO_ROOT/deploy/local/control.env"

  [[ -f "$tracked_file" ]] || imagectl_die "missing template config: $tracked_file"
  # shellcheck disable=SC1090
  source "$tracked_file"

  if [[ -f "$local_file" ]]; then
    # shellcheck disable=SC1090
    source "$local_file"
  fi

  JUMP_SSH_CONFIG_FILE="${JUMP_SSH_CONFIG_FILE:-$IMAGECTL_REPO_ROOT/deploy/local/ssh/config}"
  JUMP_SSH_KEY_FILE="${JUMP_SSH_KEY_FILE:-$IMAGECTL_REPO_ROOT/deploy/local/ssh/id_jump}"
  JUMP_HOST_ALIAS="${JUMP_HOST_ALIAS:-}"
  JUMP_HOST_USER="${JUMP_HOST_USER:-}"
  JUMP_HOST_ADDR="${JUMP_HOST_ADDR:-}"
  JUMP_HOST_PORT="${JUMP_HOST_PORT:-22}"
  JUMP_HOST_REPO_PATH="${JUMP_HOST_REPO_PATH:-}"
  JUMP_HOST_BRANCH="${JUMP_HOST_BRANCH:-main}"
  JUMP_MODE_DEFAULT="${JUMP_MODE_DEFAULT:-manual}"

  [[ -n "$JUMP_HOST_REPO_PATH" ]] || imagectl_die "JUMP_HOST_REPO_PATH is empty. Set deploy/local/control.env"
  [[ -n "$JUMP_HOST_BRANCH" ]] || imagectl_die "JUMP_HOST_BRANCH is empty. Set deploy/local/control.env"

  if [[ -z "$JUMP_HOST_ALIAS" ]]; then
    [[ -n "$JUMP_HOST_USER" ]] || imagectl_die "JUMP_HOST_USER is empty and JUMP_HOST_ALIAS is not set"
    [[ -n "$JUMP_HOST_ADDR" ]] || imagectl_die "JUMP_HOST_ADDR is empty and JUMP_HOST_ALIAS is not set"
  fi
}

imagectl_jump_target() {
  if [[ -n "${JUMP_HOST_ALIAS:-}" ]]; then
    printf '%s' "$JUMP_HOST_ALIAS"
  else
    printf '%s' "${JUMP_HOST_USER}@${JUMP_HOST_ADDR}"
  fi
}

imagectl_jump_ssh_opts() {
  local opts=()
  if [[ -f "$JUMP_SSH_CONFIG_FILE" ]]; then
    opts+=(-F "$JUMP_SSH_CONFIG_FILE")
  fi
  if [[ -n "${JUMP_HOST_PORT:-}" ]]; then
    opts+=(-p "$JUMP_HOST_PORT")
  fi
  if [[ -f "$JUMP_SSH_KEY_FILE" ]]; then
    opts+=(-i "$JUMP_SSH_KEY_FILE")
  fi
  opts+=(-o BatchMode=yes)
  opts+=(-o StrictHostKeyChecking=accept-new)
  printf '%s\n' "${opts[@]}"
}

imagectl_run_remote_cmd() {
  local cmd="$1"
  local target
  local -a opts
  local quoted_cmd

  target="$(imagectl_jump_target)"
  mapfile -t opts < <(imagectl_jump_ssh_opts)
  quoted_cmd="$(printf '%q' "$cmd")"
  ssh "${opts[@]}" "$target" "bash -lc $quoted_cmd"
}

imagectl_run_remote_repo_cmd() {
  local repo_cmd="$1"
  local repo_q
  repo_q="$(printf '%q' "$JUMP_HOST_REPO_PATH")"
  imagectl_run_remote_cmd "set -euo pipefail; cd $repo_q; $repo_cmd"
}

imagectl_check_remote_connection() {
  imagectl_need_cmd ssh
  imagectl_run_remote_cmd "echo jump-host-ok"
}
