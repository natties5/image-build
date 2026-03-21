#!/usr/bin/env bash
# phases/import_base.sh — Import a local base image into OpenStack Glance.
# TODO: implement — see /rebuild-project-doc/06_OPENSTACK_PIPELINE_DESIGN.md §Import
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="import"

# Stub: import_base
# Usage: import_base --os <name> --version <ver>
import_base() {
  util_log_info "NOT IMPLEMENTED: import_base $* — see 06_OPENSTACK_PIPELINE_DESIGN.md §Import"
  return 0
}

main() {
  [[ $# -gt 0 ]] || { echo "Usage: $0 --os <name> --version <ver>" >&2; exit 2; }
  import_base "$@"
}

main "$@"
