#!/usr/bin/env bash
# phases/publish_final.sh — Delete server, upload volume as final image, cleanup.
# TODO: implement — see /rebuild-project-doc/06_OPENSTACK_PIPELINE_DESIGN.md §Publish
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core_paths.sh"
source "${LIB_DIR}/common_utils.sh"
source "${LIB_DIR}/openstack_api.sh"
source "${LIB_DIR}/state_store.sh"

PHASE="publish"

# Stub: publish_final
# Usage: publish_final --os <name> --version <ver>
publish_final() {
  util_log_info "NOT IMPLEMENTED: publish_final $* — see 06_OPENSTACK_PIPELINE_DESIGN.md §Publish"
  return 0
}

main() {
  [[ $# -gt 0 ]] || { echo "Usage: $0 --os <name> --version <ver>" >&2; exit 2; }
  publish_final "$@"
}

main "$@"
