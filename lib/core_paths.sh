#!/usr/bin/env bash
# lib/core_paths.sh — Single source of truth for all project paths.
# Every phase MUST source this file before using any path variable.
set -Eeuo pipefail

# Resolve repo root from this file's location (lib/ → parent)
_CORE_PATHS_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT_DIR
ROOT_DIR="$(cd "${_CORE_PATHS_SELF}/.." && pwd)"

# ─── Top-level directories ────────────────────────────────────────────────────
export SCRIPTS_DIR="${ROOT_DIR}/scripts"
export LIB_DIR="${ROOT_DIR}/lib"
export PHASES_DIR="${ROOT_DIR}/phases"
export CONFIG_DIR="${ROOT_DIR}/config"
export SETTINGS_DIR="${ROOT_DIR}/settings"
export WORKSPACE_DIR="${ROOT_DIR}/workspace"
export IMAGES_DIR="${WORKSPACE_DIR}/images"
export RUNTIME_DIR="${ROOT_DIR}/runtime"
export STATE_DIR="${RUNTIME_DIR}/state"
export LOG_DIR="${RUNTIME_DIR}/logs"

# ─── Phase state subdirectories ───────────────────────────────────────────────
export STATE_SYNC_DIR="${STATE_DIR}/sync"
export STATE_IMPORT_DIR="${STATE_DIR}/import"
export STATE_CREATE_DIR="${STATE_DIR}/create"
export STATE_CONFIGURE_DIR="${STATE_DIR}/configure"
export STATE_CLEAN_DIR="${STATE_DIR}/clean"
export STATE_PUBLISH_DIR="${STATE_DIR}/publish"

# ─── Phase log subdirectories ─────────────────────────────────────────────────
export LOG_SYNC_DIR="${LOG_DIR}/sync"
export LOG_IMPORT_DIR="${LOG_DIR}/import"
export LOG_CREATE_DIR="${LOG_DIR}/create"
export LOG_CONFIGURE_DIR="${LOG_DIR}/configure"
export LOG_CLEAN_DIR="${LOG_DIR}/clean"
export LOG_PUBLISH_DIR="${LOG_DIR}/publish"

# ─── Config directories ───────────────────────────────────────────────────────
export OS_CONFIG_DIR="${CONFIG_DIR}/os"
export GUEST_CONFIG_DIR="${CONFIG_DIR}/guest"
export DEFAULTS_ENV="${CONFIG_DIR}/defaults.env"

# ─── Settings files (untracked — user-created from templates) ─────────────────
export OPENSTACK_ENV="${SETTINGS_DIR}/openstack.env"
export GUEST_ACCESS_ENV="${SETTINGS_DIR}/guest-access.env"

# ─── Path helpers ─────────────────────────────────────────────────────────────

# Return canonical state JSON path: runtime/state/<phase>/<os>-<ver>.json
# Usage: core_state_json <phase> <os_family> <os_version>
core_state_json() {
  echo "${STATE_DIR}/${1}/${2}-${3}.json"
}

# Return canonical log file path: runtime/logs/<phase>/<os>-<ver>.log
# Usage: core_log_path <phase> <os_family> <os_version>
core_log_path() {
  echo "${LOG_DIR}/${1}/${2}-${3}.log"
}

# Return canonical flag-file path: runtime/state/<phase>/<os>-<ver>.<flag>
# Usage: core_flag_path <phase> <os_family> <os_version> <flag_name>
core_flag_path() {
  echo "${STATE_DIR}/${1}/${2}-${3}.${4}"
}

# Return canonical local image path
# Usage: core_image_path <os_family> <os_version> <filename>
core_image_path() {
  echo "${IMAGES_DIR}/${1}/${2}/${3}"
}

# Ensure all required runtime directories exist (idempotent)
core_ensure_runtime_dirs() {
  local d
  for d in \
    "${STATE_SYNC_DIR}" "${STATE_IMPORT_DIR}" "${STATE_CREATE_DIR}" \
    "${STATE_CONFIGURE_DIR}" "${STATE_CLEAN_DIR}" "${STATE_PUBLISH_DIR}" \
    "${LOG_SYNC_DIR}" "${LOG_IMPORT_DIR}" "${LOG_CREATE_DIR}" \
    "${LOG_CONFIGURE_DIR}" "${LOG_CLEAN_DIR}" "${LOG_PUBLISH_DIR}" \
    "${IMAGES_DIR}/ubuntu" "${IMAGES_DIR}/debian" "${IMAGES_DIR}/rocky" \
    "${IMAGES_DIR}/almalinux" "${IMAGES_DIR}/fedora"; do
    [[ -d "$d" ]] || mkdir -p "$d"
  done
}
