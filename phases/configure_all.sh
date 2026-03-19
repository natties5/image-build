#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/layout.sh"
imagectl_init_layout "$REPO_ROOT"
SUMMARY_FILE="$(imagectl_resolve_summary_for_read)"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/08_config_all.log"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

trap 'die "line=$LINENO cmd=$BASH_COMMAND"' ERR

[[ -f "$SUMMARY_FILE" ]] || die "summary file not found: $SUMMARY_FILE"
[[ -x "$SCRIPT_DIR/configure_one.sh" ]] || die "script not executable: $SCRIPT_DIR/configure_one.sh"

mapfile -t versions < <(awk -F '\t' 'NR>1 && $1 != "" && !seen[$1]++ {print $1}' "$SUMMARY_FILE")
[[ ${#versions[@]} -gt 0 ]] || die "no version rows found in $SUMMARY_FILE"

log "versions selected: ${versions[*]}"

for version in "${versions[@]}"; do
  log "config start version=$version"
  "$SCRIPT_DIR/configure_one.sh" "$version"
  log "config done version=$version"
done

log "all config completed"
