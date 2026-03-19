#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_now() {
  date '+%F %T'
}

imagectl_log() {
  printf '[%s] %s\n' "$(imagectl_now)" "$*"
}

imagectl_die() {
  imagectl_log "ERROR: $*"
  exit 1
}

imagectl_need_cmd() {
  command -v "$1" >/dev/null 2>&1 || imagectl_die "missing command: $1"
}

imagectl_require_repo_root() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  IMAGECTL_REPO_ROOT="${IMAGECTL_REPO_ROOT:-$(cd -- "$script_dir/.." && pwd)}"
}

imagectl_is_tty() {
  [[ -t 0 && -t 1 ]]
}

imagectl_prompt_yes_no() {
  local prompt="$1"
  local answer=""
  while true; do
    read -r -p "$prompt [y/N]: " answer
    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no|"") return 1 ;;
      *) printf 'please answer y or n\n' ;;
    esac
  done
}

imagectl_select_from_list() {
  local prompt="$1"
  shift
  local options=("$@")
  local count="${#options[@]}"
  local i
  [[ "$count" -gt 0 ]] || return 1

  printf '%s\n' "$prompt" >&2
  for ((i=0; i<count; i++)); do
    printf '  %d) %s\n' "$((i + 1))" "${options[$i]}" >&2
  done

  local picked=""
  while true; do
    read -r -p "choose [1-$count]: " picked >&2
    if [[ "$picked" =~ ^[0-9]+$ ]] && ((picked >= 1 && picked <= count)); then
      printf '%s' "${options[$((picked - 1))]}"
      return 0
    fi
    printf 'invalid selection\n' >&2
  done
}
