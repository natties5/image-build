#!/usr/bin/env bash
# phases/clean_guest.sh — Final guest clean: clear caches, reset IDs, poweroff.
# TODO: implement — see /rebuild-project-doc/03_GUEST_OS_CONFIG_SYSTEM.md §Final Clean
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/config_store.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="clean"

# Stub: clean_guest
# Usage: clean_guest --os <name> --version <ver>
clean_guest() {
  util_log_info "NOT IMPLEMENTED: clean_guest $* — see 03_GUEST_OS_CONFIG_SYSTEM.md §Final Clean"
  return 0
}

main() {
  [[ $# -gt 0 ]] || { echo "Usage: $0 --os <name> --version <ver>" >&2; exit 2; }
  clean_guest "$@"
}

main "$@"
