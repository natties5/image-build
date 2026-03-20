#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/layout.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/local_overrides.sh"
imagectl_init_layout "$REPO_ROOT"
OPENSTACK_ENV_FILE="${OPENSTACK_ENV_FILE:-$REPO_ROOT/config/runtime/openstack.env}"
[[ -f "$OPENSTACK_ENV_FILE" ]] || { echo "missing config: $OPENSTACK_ENV_FILE" >&2; exit 1; }
source "$OPENSTACK_ENV_FILE"
imagectl_source_local_overrides "$REPO_ROOT"
imagectl_init_layout "$REPO_ROOT"
PIPELINE_ROOT="${PIPELINE_ROOT:-$REPO_ROOT}"
SUMMARY_FILE="$(imagectl_resolve_summary_for_read)"
LOG_DIR="${LOG_DIR:-$PIPELINE_ROOT/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/05_create_vm_all.log"
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE" ; }
die(){ log "ERROR: $*"; exit 1; }
trap 'die "line=$LINENO cmd=$BASH_COMMAND"' ERR
[[ -f "$SUMMARY_FILE" ]] || die "summary file not found: $SUMMARY_FILE"
[[ -x "$SCRIPT_DIR/create_one.sh" ]] || die "script not executable: $SCRIPT_DIR/create_one.sh"
mapfile -t versions < <(awk -F '\t' 'NR>1 && $1 != "" && !seen[$1]++ {print $1}' "$SUMMARY_FILE")
[[ ${#versions[@]} -gt 0 ]] || die "no version rows found in $SUMMARY_FILE"
log "versions selected: ${versions[*]}"
for version in "${versions[@]}"; do
  log "create VM start version=$version"
  "$SCRIPT_DIR/create_one.sh" "$version"
  log "create VM done version=$version"
done
log "all VM creates completed"
