#!/usr/bin/env bash
# lib/core_paths.sh
# Canonical path definitions for the image-build repository.

set -Eeuo pipefail

# Calculate robust ROOT_DIR based on the location of this script
export ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Core directories
export BIN_DIR="$ROOT_DIR/bin"
export LIB_DIR="$ROOT_DIR/lib"
export PHASES_DIR="$ROOT_DIR/phases"
export CONFIG_DIR="$ROOT_DIR/config"
export SETTINGS_DIR="$ROOT_DIR/settings"

# Transient and payload directories
export WORKSPACE_DIR="$ROOT_DIR/workspace"
export IMAGES_DIR="$WORKSPACE_DIR/images"
export RUNTIME_DIR="$ROOT_DIR/runtime"
export STATE_DIR="$RUNTIME_DIR/state"
export LOG_DIR="$ROOT_DIR/logs"
export MANIFESTS_DIR="$ROOT_DIR/manifests"

imagectl_init_core_paths() {
  # Legacy fallbacks mapped to canonical
  export PIPELINE_ROOT="${PIPELINE_ROOT:-$ROOT_DIR}"
  export UBUNTU_MANIFEST_DIR="${UBUNTU_MANIFEST_DIR:-$MANIFESTS_DIR/ubuntu}"
  export OPENSTACK_MANIFEST_DIR="${OPENSTACK_MANIFEST_DIR:-$MANIFESTS_DIR/openstack}"
  
  export LEGACY_MANIFEST_DIR="${LEGACY_MANIFEST_DIR:-$PIPELINE_ROOT/manifest}"
  export LEGACY_UBUNTU_MANIFEST_DIR="${LEGACY_UBUNTU_MANIFEST_DIR:-$LEGACY_MANIFEST_DIR/ubuntu}"
  export LEGACY_OPENSTACK_MANIFEST_DIR="${LEGACY_OPENSTACK_MANIFEST_DIR:-$LEGACY_MANIFEST_DIR/openstack}"
  
  export SUMMARY_FILE="${SUMMARY_FILE:-$UBUNTU_MANIFEST_DIR/ubuntu-auto-discover-summary.tsv}"
  export LEGACY_SUMMARY_FILE="${LEGACY_SUMMARY_FILE:-$LEGACY_UBUNTU_MANIFEST_DIR/ubuntu-auto-discover-summary.tsv}"
}

imagectl_ensure_core_dirs() {
  mkdir -p \
    "$SETTINGS_DIR" \
    "$WORKSPACE_DIR" \
    "$IMAGES_DIR" \
    "$RUNTIME_DIR" \
    "$STATE_DIR" \
    "$LOG_DIR" \
    "$MANIFESTS_DIR" \
    "$UBUNTU_MANIFEST_DIR" \
    "$OPENSTACK_MANIFEST_DIR" \
    "$LEGACY_MANIFEST_DIR" \
    "$LEGACY_UBUNTU_MANIFEST_DIR" \
    "$LEGACY_OPENSTACK_MANIFEST_DIR"
}

imagectl_auto_init_settings() {
  local example_file
  local target_file

  # Bootstrap settings from examples if they don't exist
  for example_file in "$SETTINGS_DIR"/*.example; do
    [[ -f "$example_file" ]] || continue
    target_file="${example_file%.example}"
    if [[ ! -f "$target_file" ]]; then
      cp "$example_file" "$target_file"
      echo "INFO: Initialized missing local setting: $target_file (from example)" >&2
    fi
  done
}

# Run initialization when sourced
imagectl_init_core_paths
