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
