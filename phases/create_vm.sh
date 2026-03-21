#!/usr/bin/env bash
# phases/create_vm.sh — Create boot volume and VM from imported base image.
# TODO: implement — see /rebuild-project-doc/06_OPENSTACK_PIPELINE_DESIGN.md §Create
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="create"

# Stub: create_vm
# Usage: create_vm --os <name> --version <ver>
create_vm() {
  util_log_info "NOT IMPLEMENTED: create_vm $* — see 06_OPENSTACK_PIPELINE_DESIGN.md §Create"
  return 0
}

main() {
  [[ $# -gt 0 ]] || { echo "Usage: $0 --os <name> --version <ver>" >&2; exit 2; }
  create_vm "$@"
}

main "$@"
