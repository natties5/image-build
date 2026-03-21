#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_source_if_exists() {
  local file="$1"
  if [[ -f "$file" ]]; then
    # shellcheck disable=SC1090
    source "$file"
  fi
}

imagectl_source_local_overrides() {
  local repo_root="$1"

  # Load settings/ first (primary source — gitignored)
  imagectl_source_if_exists "$repo_root/settings/openstack.env"
  imagectl_source_if_exists "$repo_root/settings/openrc.env"
  imagectl_source_if_exists "$repo_root/settings/credentials.env"

  # Fallback: deploy/local/ for backward compatibility
  imagectl_source_if_exists "$repo_root/deploy/local/openstack.env"
  imagectl_source_if_exists "$repo_root/deploy/local/openrc.path"
  imagectl_source_if_exists "$repo_root/deploy/local/guest-access.env"
  imagectl_source_if_exists "$repo_root/deploy/local/publish.env"
  imagectl_source_if_exists "$repo_root/deploy/local/clean.env"
}
