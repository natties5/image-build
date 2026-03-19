#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_default_repo_url() {
  local origin_url=""
  origin_url="$(git -C "$IMAGECTL_REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  printf '%s' "$origin_url"
}

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

  JUMP_SSH_CONFIG_FILE="${JUMP_SSH_CONFIG_FILE:-$IMAGECTL_REPO_ROOT/deploy/local/ssh_config}"
  JUMP_SSH_KEY_FILE="${JUMP_SSH_KEY_FILE:-$IMAGECTL_REPO_ROOT/deploy/local/ssh/id_jump}"
  JUMP_HOST_ALIAS="${JUMP_HOST_ALIAS:-}"
  JUMP_HOST_USER="${JUMP_HOST_USER:-}"
  JUMP_HOST_ADDR="${JUMP_HOST_ADDR:-}"
  JUMP_HOST_PORT="${JUMP_HOST_PORT:-22}"
  JUMP_HOST_REPO_PATH="${JUMP_HOST_REPO_PATH:-}"
  JUMP_HOST_BRANCH="${JUMP_HOST_BRANCH:-main}"
  JUMP_HOST_REPO_URL="${JUMP_HOST_REPO_URL:-$(imagectl_default_repo_url)}"
  JUMP_MODE_DEFAULT="${JUMP_MODE_DEFAULT:-manual}"
  EXPECTED_PROJECT_NAME="${EXPECTED_PROJECT_NAME:-}"

  [[ -n "$JUMP_HOST_REPO_PATH" ]] || imagectl_die "JUMP_HOST_REPO_PATH is empty. Set deploy/local/control.env"
  [[ -n "$JUMP_HOST_BRANCH" ]] || imagectl_die "JUMP_HOST_BRANCH is empty. Set deploy/local/control.env"
  [[ -n "$JUMP_HOST_REPO_URL" ]] || imagectl_die "JUMP_HOST_REPO_URL is empty and origin remote was not found"

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
  local mode="${1:-noninteractive}"
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
  opts+=(-o StrictHostKeyChecking=accept-new)
  if [[ "$mode" == "noninteractive" ]]; then
    opts+=(-o BatchMode=yes)
  fi
  printf '%s\n' "${opts[@]}"
}

imagectl_run_remote_cmd() {
  local cmd="$1"
  local target
  local -a opts
  local quoted_cmd

  target="$(imagectl_jump_target)"
  mapfile -t opts < <(imagectl_jump_ssh_opts noninteractive)
  quoted_cmd="$(printf '%q' "$cmd")"
  ssh "${opts[@]}" "$target" "bash -lc $quoted_cmd"
}

imagectl_run_remote_repo_cmd() {
  local repo_cmd="$1"
  local repo_q
  repo_q="$(printf '%q' "$JUMP_HOST_REPO_PATH")"
  imagectl_run_remote_cmd "set -euo pipefail; cd $repo_q; $repo_cmd"
}

imagectl_upload_file_to_remote_repo() {
  local local_file="$1"
  local remote_rel="$2"
  local remote_dir=""
  local repo_q=""
  local dir_q=""
  local rel_q=""
  local cmd=""
  local target=""
  local -a opts
  local quoted_cmd=""

  [[ -f "$local_file" ]] || imagectl_die "local file not found for upload: $local_file"
  remote_dir="$(dirname -- "$remote_rel")"
  repo_q="$(printf '%q' "$JUMP_HOST_REPO_PATH")"
  dir_q="$(printf '%q' "$remote_dir")"
  rel_q="$(printf '%q' "$remote_rel")"
  cmd="set -euo pipefail; cd $repo_q; mkdir -p $dir_q; cat > $rel_q"
  quoted_cmd="$(printf '%q' "$cmd")"

  target="$(imagectl_jump_target)"
  mapfile -t opts < <(imagectl_jump_ssh_opts noninteractive)
  ssh "${opts[@]}" "$target" "bash -lc $quoted_cmd" < "$local_file"
}

imagectl_check_remote_connection() {
  imagectl_need_cmd ssh
  imagectl_run_remote_cmd "echo jump-host-ok"
}

imagectl_ssh_connect_interactive() {
  local target
  local -a opts
  target="$(imagectl_jump_target)"
  mapfile -t opts < <(imagectl_jump_ssh_opts interactive)
  ssh "${opts[@]}" "$target"
}

imagectl_ssh_info() {
  local target
  target="$(imagectl_jump_target)"
  cat <<EOF
target=$target
alias=${JUMP_HOST_ALIAS:-<none>}
host=${JUMP_HOST_ADDR:-<via-alias>}
user=${JUMP_HOST_USER:-<via-alias>}
port=${JUMP_HOST_PORT}
repo_path=${JUMP_HOST_REPO_PATH}
repo_branch=${JUMP_HOST_BRANCH}
repo_url=${JUMP_HOST_REPO_URL}
ssh_config_file=${JUMP_SSH_CONFIG_FILE}
ssh_key_file=${JUMP_SSH_KEY_FILE:-<not-set>}
EOF
}
