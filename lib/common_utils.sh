#!/usr/bin/env bash
# lib/common_utils.sh — Logging, retry, timeout, state, SSH, JSON helpers.
# Source this after core_paths.sh in every phase.
set -Eeuo pipefail

# ─── Logging ──────────────────────────────────────────────────────────────────
_LOG_FILE=""

# Initialize log file (truncates existing file, creates parent dirs)
# Usage: util_init_log_file <path>
util_init_log_file() {
  _LOG_FILE="$1"
  local dir; dir="$(dirname "$_LOG_FILE")"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  : > "$_LOG_FILE"
}

_util_log() {
  local level="$1" msg="$2"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u)"
  local line="[${ts}] [${level}] ${msg}"
  echo "$line" >&2
  [[ -n "$_LOG_FILE" ]] && echo "$line" >> "$_LOG_FILE" || true
}

util_log_info()  { _util_log "INFO"  "$*"; }
util_log_warn()  { _util_log "WARN"  "$*"; }
util_log_error() { _util_log "ERROR" "$*"; }

# Log a fatal error and exit
# Usage: util_die <message> [exit_code]
util_die() {
  local msg="${1:-Fatal error}" code="${2:-1}"
  util_log_error "FATAL: ${msg}"
  exit "$code"
}

# ─── Dependency checks ────────────────────────────────────────────────────────
util_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || util_die "Required command not found: $1" 3
}

util_require_cmds() {
  local cmd; for cmd in "$@"; do util_require_cmd "$cmd"; done
}

# ─── File / directory helpers ─────────────────────────────────────────────────
util_ensure_dir() {
  [[ -d "$1" ]] || mkdir -p "$1"
}

util_ensure_parent_dir() {
  util_ensure_dir "$(dirname "$1")"
}

util_file_exists_nonempty() {
  [[ -f "$1" && -s "$1" ]]
}

# ─── Retry / timeout / polling ────────────────────────────────────────────────
# Retry a command up to <attempts> times with <sleep_sec> between attempts.
# Returns 0 on success, 11 (retry exhausted) on all failures.
# Usage: util_retry <attempts> <sleep_sec> <command...>
util_retry() {
  local attempts="$1" sleep_sec="$2"; shift 2
  local i=0
  while (( i < attempts )); do
    "$@" && return 0
    (( i++ )) || true
    util_log_warn "Attempt ${i}/${attempts} failed for: $*. Retrying in ${sleep_sec}s..."
    sleep "$sleep_sec"
  done
  util_log_error "All ${attempts} attempts failed: $*"
  return 11
}

# Run a command with an overall timeout (uses system 'timeout' if available).
# Usage: util_with_timeout <seconds> <command...>
util_with_timeout() {
  local seconds="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

# Poll a command until it succeeds or a timeout is reached.
# Returns 0 on success, 7 on timeout.
# Usage: util_poll_until <max_seconds> <interval_sec> <description> <command...>
util_poll_until() {
  local max_seconds="$1" interval="$2" description="$3"; shift 3
  local elapsed=0
  util_log_info "Polling: ${description} (timeout ${max_seconds}s)"
  while (( elapsed < max_seconds )); do
    "$@" && return 0
    sleep "$interval"
    elapsed=$(( elapsed + interval ))
    util_log_info "Still waiting: ${description} [${elapsed}/${max_seconds}s]"
  done
  util_log_error "Polling timeout after ${max_seconds}s: ${description}"
  return 7
}

# ─── State / flag file helpers ────────────────────────────────────────────────
state_write_flag() {
  util_ensure_parent_dir "$1"
  touch "$1"
}

state_clear_flag() { rm -f "$1"; }

state_flag_exists() { [[ -f "$1" ]]; }

# ─── SSH / SCP helpers ────────────────────────────────────────────────────────
# Build SSH base option array (stored in _SSH_OPTS global)
_ssh_build_opts() {
  local port="$1" auth_mode="$2" auth_value="$3"
  _SSH_OPTS=(-p "$port"
    -o StrictHostKeyChecking=no
    -o ConnectTimeout=10
    -o BatchMode=no)
  if [[ "$auth_mode" == "key" ]]; then
    _SSH_OPTS+=(-i "$auth_value" -o PasswordAuthentication=no)
  fi
}

# Run a remote command via SSH
# Usage: ssh_run <host> <port> <user> <auth_mode:password|key> <auth_value> <remote_command>
ssh_run() {
  local host="$1" port="$2" user="$3" auth_mode="$4" auth_value="$5"
  shift 5
  _ssh_build_opts "$port" "$auth_mode" "$auth_value"
  if [[ "$auth_mode" == "password" ]]; then
    util_require_cmd sshpass
    sshpass -p "$auth_value" ssh "${_SSH_OPTS[@]}" "${user}@${host}" "$@"
  else
    ssh "${_SSH_OPTS[@]}" "${user}@${host}" "$@"
  fi
}

# Copy file to remote host
# Usage: scp_put <host> <port> <user> <auth_mode> <auth_value> <local_path> <remote_path>
scp_put() {
  local host="$1" port="$2" user="$3" auth_mode="$4" auth_value="$5"
  local local_path="$6" remote_path="$7"
  _ssh_build_opts "$port" "$auth_mode" "$auth_value"
  if [[ "$auth_mode" == "password" ]]; then
    util_require_cmd sshpass
    sshpass -p "$auth_value" scp "${_SSH_OPTS[@]}" "$local_path" "${user}@${host}:${remote_path}"
  else
    scp "${_SSH_OPTS[@]}" "$local_path" "${user}@${host}:${remote_path}"
  fi
}

# Wait until SSH is ready (guest has booted and SSH daemon is accepting connections)
# Usage: ssh_wait_ready <host> <port> <user> <auth_mode> <auth_value> <timeout_sec> [interval_sec]
ssh_wait_ready() {
  local host="$1" port="$2" user="$3" auth_mode="$4" auth_value="$5"
  local timeout_sec="${6:-120}" interval="${7:-10}"
  util_poll_until "$timeout_sec" "$interval" "SSH ready at ${host}:${port}" \
    ssh_run "$host" "$port" "$user" "$auth_mode" "$auth_value" "true"
}

# ─── JSON helpers ─────────────────────────────────────────────────────────────
# Escape a string for embedding in a JSON value (double-quotes, backslashes, newlines)
json_escape() {
  printf '%s' "$1" | \
    sed 's/\\/\\\\/g; s/"/\\"/g' | \
    awk '{printf "%s\\n", $0}' | \
    sed 's/\\n$//'
}

# Write content to a JSON file (creates parent dirs)
json_write_file() {
  local path="$1" content="$2"
  util_ensure_parent_dir "$path"
  printf '%s\n' "$content" > "$path"
}
