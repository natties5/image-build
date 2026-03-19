#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/layout.sh"
imagectl_init_layout "$REPO_ROOT"
imagectl_ensure_layout_dirs

usage() {
  cat <<'EOF'
usage:
  bin/imagectl.sh preflight
  bin/imagectl.sh download [config-file]
  bin/imagectl.sh import [all|<version>]
  bin/imagectl.sh create [all|<version>]
  bin/imagectl.sh configure [all|<version-or-config-file>]
  bin/imagectl.sh clean [all|<version-or-config-file>]
  bin/imagectl.sh publish [all|<version-or-config-file>]
  bin/imagectl.sh all
EOF
}

run_phase() {
  local script="$1"
  shift
  bash "$REPO_ROOT/phases/$script" "$@"
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 1; }
shift || true

case "$cmd" in
  preflight)
    run_phase preflight.sh "$@"
    ;;
  download)
    run_phase download.sh "$@"
    ;;
  import)
    if [[ "${1:-all}" == "all" ]]; then
      run_phase import_all.sh
    else
      run_phase import_one.sh "$1"
    fi
    ;;
  create)
    if [[ "${1:-all}" == "all" ]]; then
      run_phase create_all.sh
    else
      run_phase create_one.sh "$1"
    fi
    ;;
  configure)
    if [[ "${1:-all}" == "all" ]]; then
      run_phase configure_all.sh
    else
      run_phase configure_one.sh "$1"
    fi
    ;;
  clean)
    if [[ "${1:-all}" == "all" ]]; then
      run_phase clean_all.sh
    else
      run_phase clean_one.sh "$1"
    fi
    ;;
  publish)
    if [[ "${1:-all}" == "all" ]]; then
      run_phase publish_all.sh
    else
      run_phase publish_one.sh "$1"
    fi
    ;;
  all)
    run_phase preflight.sh
    run_phase download.sh
    run_phase import_all.sh
    run_phase create_all.sh
    run_phase configure_all.sh
    run_phase clean_all.sh
    run_phase publish_all.sh
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
