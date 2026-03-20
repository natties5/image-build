#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_init_layout() {
  local repo_root="$1"
  PIPELINE_ROOT="${PIPELINE_ROOT:-$repo_root}"

  MANIFESTS_DIR="${MANIFESTS_DIR:-$PIPELINE_ROOT/manifests}"
  LEGACY_MANIFEST_DIR="${LEGACY_MANIFEST_DIR:-$PIPELINE_ROOT/manifest}"

  UBUNTU_MANIFEST_DIR="${UBUNTU_MANIFEST_DIR:-$MANIFESTS_DIR/ubuntu}"
  OPENSTACK_MANIFEST_DIR="${OPENSTACK_MANIFEST_DIR:-$MANIFESTS_DIR/openstack}"

  LEGACY_UBUNTU_MANIFEST_DIR="${LEGACY_UBUNTU_MANIFEST_DIR:-$LEGACY_MANIFEST_DIR/ubuntu}"
  LEGACY_OPENSTACK_MANIFEST_DIR="${LEGACY_OPENSTACK_MANIFEST_DIR:-$LEGACY_MANIFEST_DIR/openstack}"

  SUMMARY_FILE="${SUMMARY_FILE:-$UBUNTU_MANIFEST_DIR/ubuntu-auto-discover-summary.tsv}"
  LEGACY_SUMMARY_FILE="${LEGACY_SUMMARY_FILE:-$LEGACY_UBUNTU_MANIFEST_DIR/ubuntu-auto-discover-summary.tsv}"
}

imagectl_ensure_layout_dirs() {
  mkdir -p \
    "$MANIFESTS_DIR" \
    "$UBUNTU_MANIFEST_DIR" \
    "$OPENSTACK_MANIFEST_DIR" \
    "$LEGACY_MANIFEST_DIR" \
    "$LEGACY_UBUNTU_MANIFEST_DIR" \
    "$LEGACY_OPENSTACK_MANIFEST_DIR"
}

imagectl_resolve_summary_for_read() {
  if [[ -f "$SUMMARY_FILE" ]]; then
    printf '%s' "$SUMMARY_FILE"
    return 0
  fi
  if [[ -f "$LEGACY_SUMMARY_FILE" ]]; then
    printf '%s' "$LEGACY_SUMMARY_FILE"
    return 0
  fi
  printf '%s' "$SUMMARY_FILE"
}

imagectl_sync_file_to_legacy() {
  local src="$1"
  local dst="$2"
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname -- "$dst")"
  cp -f "$src" "$dst"
}
