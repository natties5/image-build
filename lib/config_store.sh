#!/usr/bin/env bash
# lib/config_store.sh — Load and merge config files for OS/version pairs.
# TODO: implement all functions — see /rebuild-project-doc/05_CONFIG_SCHEMA_REFERENCE.md
set -Eeuo pipefail

# Load guest config for an OS+version pair (merges default.env then <version>.env)
# Sets all CONFIG_* and OS_* variables in calling scope via source.
# Usage: config_load_guest <os_family> <os_version>
config_load_guest() {
  local os_family="$1" os_version="$2"
  local default_env="${GUEST_CONFIG_DIR}/${os_family}/default.env"
  local version_env="${GUEST_CONFIG_DIR}/${os_family}/${os_version}.env"

  if [[ -f "$default_env" ]]; then
    # shellcheck source=/dev/null
    source "$default_env"
    util_log_info "Loaded guest default config: $default_env"
  else
    util_log_warn "No default guest config found: $default_env"
  fi

  if [[ -f "$version_env" ]]; then
    # shellcheck source=/dev/null
    source "$version_env"
    util_log_info "Loaded guest version config: $version_env"
  else
    util_log_warn "No version guest config found: $version_env"
  fi
}

# Load OpenStack settings (settings/openstack.env)
# Usage: config_load_openstack
config_load_openstack() {
  # TODO: implement — see /rebuild-project-doc/05_CONFIG_SCHEMA_REFERENCE.md
  util_log_info "NOT IMPLEMENTED: config_load_openstack"
  return 0
}

# Load guest access settings (settings/guest-access.env)
# Usage: config_load_guest_access
config_load_guest_access() {
  # TODO: implement — see /rebuild-project-doc/05_CONFIG_SCHEMA_REFERENCE.md
  util_log_info "NOT IMPLEMENTED: config_load_guest_access"
  return 0
}

# Validate that required variables are set (non-empty)
# Usage: config_require_vars VAR1 VAR2 ...
config_require_vars() {
  local var
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      util_die "Required config variable not set: ${var}"
    fi
  done
}

# Write effective config snapshot to a JSON file
# Usage: config_write_effective_json <output_path> <os_family> <os_version>
config_write_effective_json() {
  # TODO: implement — see /rebuild-project-doc/05_CONFIG_SCHEMA_REFERENCE.md §6
  util_log_info "NOT IMPLEMENTED: config_write_effective_json $*"
  return 0
}

# Auto-promote <version>.env to default.env after successful pipeline.
# Rules:
#   1. publish.ready must exist (pipeline passed completely)
#   2. version must be >= current default version (no downgrade)
#   3. default.env must already exist
# Usage: _auto_promote_guest_config <os_family> <os_name> <version>
# Example: _auto_promote_guest_config debian ubuntu 24.04
_auto_promote_guest_config() {
  local os_family="$1"
  local os_name="$2"
  local version="$3"

  local version_env="${GUEST_CONFIG_DIR}/${os_name}/${version}.env"
  local default_env="${GUEST_CONFIG_DIR}/${os_name}/default.env"
  local publish_ready="${STATE_DIR}/publish/${os_name}-${version}.ready"

  util_log_info "auto-promote check: os=${os_name} version=${version}"

  # Rule 1: publish.ready must exist
  if [[ ! -f "$publish_ready" ]]; then
    util_log_info "  promote skipped: publish.ready not found for ${os_name}-${version}"
    return 0
  fi

  # Rule 2: version.env must exist
  if [[ ! -f "$version_env" ]]; then
    util_log_warn "  promote skipped: version config not found: $version_env"
    return 0
  fi

  # Rule 3: default.env must exist
  if [[ ! -f "$default_env" ]]; then
    util_log_warn "  promote skipped: default.env not found: $default_env"
    return 0
  fi

  # Rule 4: compare version vs current default version
  # Read current default version from GUEST_OS_VERSION field
  local current_default_ver=""
  current_default_ver=$(grep -m1 '^GUEST_OS_VERSION=' "$default_env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' | tr -d "'" | tr -d ' ') || true

  if [[ -z "$current_default_ver" ]]; then
    util_log_warn "  promote skipped: cannot read GUEST_OS_VERSION from $default_env"
    return 0
  fi

  # Compare using sort -V (version sort)
  local newer
  newer=$(printf '%s\n%s\n' "$current_default_ver" "$version" \
    | sort -V | tail -1)

  if [[ "$newer" == "$current_default_ver" && "$version" != "$current_default_ver" ]]; then
    # current default is newer → do not promote
    util_log_info "  promote skipped: ${version} < default ${current_default_ver} (no downgrade)"
    return 0
  fi

  # All rules passed → promote
  util_log_info "  promoting: ${os_name} ${version} → default.env"
  util_log_info "  (replacing default version: ${current_default_ver} → ${version})"

  cp "$version_env" "$default_env"

  # Git commit the promotion
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  cd "$repo_root"

  # git diff ไม่เห็น untracked file → ใช้ git status --porcelain แทน
  if git status --porcelain "$default_env" 2>/dev/null | grep -q .; then
    # มีการเปลี่ยนแปลง (modified หรือ untracked) → commit
    git add "$default_env"
    git \
      -c user.email="pipeline@image-build.local" \
      -c user.name="image-build pipeline" \
      commit \
      -m "auto-promote: ${os_name} ${version} → default.env

Pipeline passed completely (publish.ready exists).
Previous default version: ${current_default_ver}
New default version: ${version}
Promoted by: _auto_promote_guest_config" \
      --no-verify 2>/dev/null \
      || util_log_warn "  promote: git commit failed (not a git repo, or other error)"
    util_log_info "  promote committed: ${os_name} ${version} → default.env"
  else
    util_log_info "  promote: default.env unchanged — no commit needed"
  fi

  return 0
}
