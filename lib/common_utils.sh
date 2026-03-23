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

# ─── Sync UI helpers ──────────────────────────────────────────────────────────
# Returns space-separated list of supported OS names
_sync_list_oses() {
  echo "ubuntu debian fedora almalinux rocky"
}

# Print numbered OS list, read user choice, echo selected OS name to stdout.
# Prompts and errors go to stderr so this works in command substitution.
_sync_select_os() {
  local oses
  read -ra oses <<< "$(_sync_list_oses)"
  echo "  Select OS:" >&2
  local i=1 o
  for o in "${oses[@]}"; do
    printf "    %d) %s\n" "$i" "$o" >&2
    (( i++ )) || true
  done
  printf "  Select [1-%d]: " "${#oses[@]}" >&2
  local choice; read -r choice || return 1
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "  Invalid selection." >&2; return 1
  fi
  local idx=$(( choice - 1 ))
  if [[ $idx -lt 0 ]] || [[ $idx -ge ${#oses[@]} ]]; then
    echo "  Invalid selection." >&2; return 1
  fi
  echo "${oses[$idx]}"
}

# Print "VERSION [STATUS]" lines for an OS, sorted descending by version.
# Sources: runtime/state/sync/<os>-*.json + config/os/<os>/sync.env TRACKED_VERSIONS
_sync_list_versions_for_os() {
  local os="$1"
  declare -A ver_status
  local f
  for f in "${STATE_SYNC_DIR}/${os}"-*.json; do
    [[ -f "$f" ]] || continue
    local ver
    ver=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null \
      | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1) || true
    [[ -n "$ver" ]] || continue
    if [[ -f "${STATE_SYNC_DIR}/${os}-${ver}.ready" ]]; then
      ver_status["$ver"]="[downloaded]"
    elif [[ -f "${STATE_SYNC_DIR}/${os}-${ver}.dryrun-ok" ]]; then
      ver_status["$ver"]="[dry-run ok]"
    elif [[ -f "${STATE_SYNC_DIR}/${os}-${ver}.failed" ]]; then
      ver_status["$ver"]="[failed]"
    else
      ver_status["$ver"]="[not yet]"
    fi
  done
  local config_file="${OS_CONFIG_DIR}/${os}/sync.env"
  if [[ -f "$config_file" ]]; then
    local tracked
    tracked=$(grep '^TRACKED_VERSIONS=' "$config_file" 2>/dev/null \
      | cut -d= -f2- | tr -d '"') || tracked=""
    local v
    for v in $tracked; do
      if [[ -z "${ver_status[$v]+_}" ]]; then
        ver_status["$v"]="[not yet]"
      fi
    done
  fi
  local ver
  for ver in $(printf '%s\n' "${!ver_status[@]}" | sort -Vr); do
    echo "${ver} ${ver_status[$ver]}"
  done
}

# Print numbered version list for an OS, read user choice, echo version to stdout.
# Prompts and errors go to stderr so this works in command substitution.
_sync_select_version() {
  local os="$1"
  local versions=()
  local line
  while IFS= read -r line; do
    versions+=("$line")
  done < <(_sync_list_versions_for_os "$os")
  if [[ ${#versions[@]} -eq 0 ]]; then
    echo "  No versions found for ${os}." >&2; return 1
  fi
  echo "  Select version for ${os}:" >&2
  local i=1
  for line in "${versions[@]}"; do
    printf "    %d) %s\n" "$i" "$line" >&2
    (( i++ )) || true
  done
  printf "  Select [1-%d]: " "${#versions[@]}" >&2
  local choice; read -r choice || return 1
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "  Invalid selection." >&2; return 1
  fi
  local idx=$(( choice - 1 ))
  if [[ $idx -lt 0 ]] || [[ $idx -ge ${#versions[@]} ]]; then
    echo "  Invalid selection." >&2; return 1
  fi
  echo "${versions[$idx]%% *}"
}

# ─── Python detection ─────────────────────────────────────────────────────────
# Find a working Python interpreter (avoids Windows MS Store stub).
# Returns the command name via stdout; returns empty string if none found.
_detect_python() {
  # Honour PYTHON3 if already set and working (e.g. by _setup_windows_python_path)
  if [[ -n "${PYTHON3:-}" ]]; then
    if "${PYTHON3}" -c "import sys; sys.exit(0)" 2>/dev/null; then
      printf '%s' "${PYTHON3}"
      return
    fi
  fi
  local py="" c
  for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1; then
      # Actually execute — Windows "python3" may exist but open the Store
      if "$c" -c "import sys; sys.exit(0)" 2>/dev/null; then
        py="$c"
        break
      fi
    fi
  done
  printf '%s' "$py"
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

# ─── Build state helpers ───────────────────────────────────────────────────────

# Returns list of "os version status" lines where status is:
#   ready        → runtime/state/sync/<os>-<ver>.ready exists
#   dryrun-only  → only .dryrun-ok exists (not downloaded)
# Skips entries with neither flag.
_build_list_ready() {
  local os_list="ubuntu debian fedora almalinux rocky"
  local os ver base f status
  for os in $os_list; do
    for f in "${STATE_SYNC_DIR}/${os}"-*.json; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f" .json)"
      ver="${base#${os}-}"
      if [[ -f "${STATE_SYNC_DIR}/${base}.ready" ]]; then
        echo "$os $ver ready"
      elif [[ -f "${STATE_SYNC_DIR}/${base}.dryrun-ok" ]]; then
        echo "$os $ver dryrun-only"
      fi
    done
  done
}

# Returns latest version (sort -V) for a given OS that has .ready
_build_latest_ready_version() {
  local os="$1"
  _build_list_ready | awk -v o="$os" '$1==o && $3=="ready" {print $2}' \
    | sort -V | tail -1
}

# Returns all versions for a given OS that have .ready
_build_all_ready_versions() {
  local os="$1"
  _build_list_ready | awk -v o="$os" '$1==o && $3=="ready" {print $2}' \
    | sort -V
}

# Discover available versions from upstream for a given OS.
# Reads AUTO_DISCOVER, MIN_VERSION, LTS_ONLY from sync.env.
# Returns newline-separated list of versions found >= MIN_VERSION.
# Usage: _sync_discover_upstream_versions <os>
_sync_discover_upstream_versions() {
  local os="$1"
  local cfg="${OS_CONFIG_DIR}/${os}/sync.env"
  [[ -f "$cfg" ]] || return 1

  # Load needed vars from sync.env
  local AUTO_DISCOVER="" MIN_VERSION="" LTS_ONLY="" INDEX_URL_TEMPLATE=""
  # shellcheck source=/dev/null
  source "$cfg" 2>/dev/null || return 1

  [[ "${AUTO_DISCOVER:-0}" == "1" ]] || return 0

  local base_url versions=()

  case "$os" in
    ubuntu)
      # Scan https://cloud-images.ubuntu.com/releases/
      base_url="https://cloud-images.ubuntu.com/releases/"
      local html
      html=$(curl -s --max-time 15 "$base_url" 2>/dev/null) || return 1
      # Extract version-like folders: 18.04/ 20.04/ 22.04/ 24.04/ 24.10/
      while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        # LTS filter: xx.04 only
        if [[ "${LTS_ONLY:-0}" == "1" ]]; then
          [[ "$ver" =~ ^[0-9]+\.04$ ]] || continue
        fi
        # MIN_VERSION filter
        if printf '%s\n%s\n' "$MIN_VERSION" "$ver" \
            | sort -V | tail -1 | grep -q "^${ver}$" || \
           [[ "$ver" == "$MIN_VERSION" ]]; then
          versions+=("$ver")
        fi
      done < <(echo "$html" \
        | grep -oE 'href="[0-9]+\.[0-9]+/?[0-9]*/?[0-9]*/"' \
        | sed 's|href="||;s|/\?"||;s|/"||' \
        | sort -uV)
      ;;

    debian)
      # Scan https://cloud.debian.org/images/cloud/
      base_url="https://cloud.debian.org/images/cloud/"
      local html
      html=$(curl -s --max-time 15 "$base_url" 2>/dev/null) || return 1
      # Codename → version map (extend as new releases come)
      declare -A codename_to_ver=(
        [bookworm]=12
        [trixie]=13
        [forky]=14
        [sid]=999
      )
      while IFS= read -r codename; do
        [[ -z "$codename" ]] && continue
        [[ "$codename" == "sid" ]] && continue  # skip unstable
        local ver="${codename_to_ver[$codename]:-}"
        [[ -z "$ver" ]] && continue
        # MIN_VERSION filter
        if printf '%s\n%s\n' "$MIN_VERSION" "$ver" \
            | sort -V | tail -1 | grep -q "^${ver}$" || \
           [[ "$ver" == "$MIN_VERSION" ]]; then
          # Verify cloud images exist for this codename
          local check_url="https://cloud.debian.org/images/cloud/${codename}/latest/"
          local http_code
          http_code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$check_url" 2>/dev/null)
          [[ "$http_code" == "200" ]] || continue
          versions+=("$ver")
        fi
      done < <(echo "$html" \
        | grep -oE 'href="[a-z]+/"' \
        | sed 's|href="||;s|/"||' \
        | grep -vE '^(daily|archive|cdimage|OpenStack|[0-9])' \
        | sort -u)
      ;;

    rocky)
      # Scan https://dl.rockylinux.org/pub/rocky/
      base_url="https://dl.rockylinux.org/pub/rocky/"
      local html
      html=$(curl -s --max-time 15 "$base_url" 2>/dev/null) || return 1
      while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        # Only major versions (8, 9, 10) not sub-paths
        [[ "$ver" =~ ^[0-9]+$ ]] || continue
        if printf '%s\n%s\n' "$MIN_VERSION" "$ver" \
            | sort -V | tail -1 | grep -q "^${ver}$" || \
           [[ "$ver" == "$MIN_VERSION" ]]; then
          versions+=("$ver")
        fi
      done < <(echo "$html" \
        | grep -oE 'href="[0-9]+/"' \
        | sed 's|href="||;s|/"||' \
        | sort -uV)
      ;;

    almalinux)
      # Scan https://repo.almalinux.org/almalinux/
      base_url="https://repo.almalinux.org/almalinux/"
      local html
      html=$(curl -s --max-time 15 "$base_url" 2>/dev/null) || return 1
      while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        [[ "$ver" =~ ^[0-9]+$ ]] || continue
        if printf '%s\n%s\n' "$MIN_VERSION" "$ver" \
            | sort -V | tail -1 | grep -q "^${ver}$" || \
           [[ "$ver" == "$MIN_VERSION" ]]; then
          versions+=("$ver")
        fi
      done < <(echo "$html" \
        | grep -oE 'href="[0-9]+/"' \
        | sed 's|href="||;s|/"||' \
        | sort -uV)
      ;;

    fedora)
      # Scan https://dl.fedoraproject.org/pub/fedora/linux/releases/
      base_url="https://dl.fedoraproject.org/pub/fedora/linux/releases/"
      local html
      html=$(curl -s --max-time 15 "$base_url" 2>/dev/null) || return 1
      while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        [[ "$ver" =~ ^[0-9]+$ ]] || continue
        if printf '%s\n%s\n' "$MIN_VERSION" "$ver" \
            | sort -V | tail -1 | grep -q "^${ver}$" || \
           [[ "$ver" == "$MIN_VERSION" ]]; then
          # Only include versions that exist in archives (sync_download.sh uses archive URL)
          local arch_check="https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/${ver}/Cloud/x86_64/images/"
          local http_code
          http_code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$arch_check" 2>/dev/null)
          [[ "$http_code" == "200" ]] || continue
          versions+=("$ver")
        fi
      done < <(echo "$html" \
        | grep -oE 'href="[0-9]+/"' \
        | sed 's|href="||;s|/"||' \
        | sort -uV)
      ;;

    *)
      return 1
      ;;
  esac

  printf '%s\n' "${versions[@]}" | sort -uV
}

# Compare discovered versions vs TRACKED_VERSIONS in sync.env.
# If new versions found → update TRACKED_VERSIONS in sync.env.
# Returns: lines of "VERSION [NEW]" or "VERSION [tracked]"
# Usage: _sync_update_tracked_versions <os>
_sync_update_tracked_versions() {
  local os="$1"
  local cfg="${OS_CONFIG_DIR}/${os}/sync.env"
  [[ -f "$cfg" ]] || return 1

  # Read current TRACKED_VERSIONS
  local current_tracked
  current_tracked=$(grep '^TRACKED_VERSIONS=' "$cfg" 2>/dev/null \
    | cut -d= -f2- | tr -d '"') || current_tracked=""

  # Discover upstream
  local discovered
  discovered=$(_sync_discover_upstream_versions "$os") || discovered=""

  if [[ -z "$discovered" ]]; then
    echo "  (discovery failed or AUTO_DISCOVER=0)" >&2
    return 0
  fi

  local new_versions=()
  local ver
  while IFS= read -r ver; do
    [[ -z "$ver" ]] && continue
    # Check if already in TRACKED_VERSIONS
    if ! echo " $current_tracked " | grep -q " $ver "; then
      new_versions+=("$ver")
    fi
  done <<< "$discovered"

  # Print all discovered with [NEW] or [tracked] tag
  while IFS= read -r ver; do
    [[ -z "$ver" ]] && continue
    if echo " $current_tracked " | grep -q " $ver "; then
      echo "${ver} [tracked]"
    else
      echo "${ver} [NEW]"
    fi
  done <<< "$discovered"

  # If new versions found → update TRACKED_VERSIONS in sync.env
  if [[ ${#new_versions[@]} -gt 0 ]]; then
    # Build new TRACKED_VERSIONS = current + new, sorted
    local all_versions
    all_versions=$(printf '%s\n' $current_tracked "${new_versions[@]}" \
      | sort -uV | tr '\n' ' ' | sed 's/ $//')
    # Update sync.env in-place
    sed -i "s|^TRACKED_VERSIONS=.*|TRACKED_VERSIONS=\"${all_versions}\"|" "$cfg"
    echo "  [auto-discover] updated TRACKED_VERSIONS for $os: $all_versions" >&2
  fi
}
