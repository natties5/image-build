#!/usr/bin/env bash
# phases/configure_guest.sh — SSH into guest VM and apply OS configuration policy.
# TODO: implement — see /rebuild-project-doc/03_GUEST_OS_CONFIG_SYSTEM.md
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/config_store.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="configure"

# Stub: configure_guest
# Usage: configure_guest --os <name> --version <ver>
configure_guest() {
  util_log_info "NOT IMPLEMENTED: configure_guest $* — see 03_GUEST_OS_CONFIG_SYSTEM.md"
  return 0
}

main() {
  [[ $# -gt 0 ]] || { echo "Usage: $0 --os <name> --version <ver>" >&2; exit 2; }
  configure_guest "$@"
}

main "$@"
