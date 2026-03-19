#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/layout.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/local_overrides.sh"
imagectl_init_layout "$REPO_ROOT"
imagectl_ensure_layout_dirs

OPENSTACK_ENV_FILE="${OPENSTACK_ENV_FILE:-$REPO_ROOT/config/openstack.env}"
OPENRC_PATH_FILE="${OPENRC_PATH_FILE:-$REPO_ROOT/config/openrc.path}"
PUBLISH_CONFIG_FILE="${PUBLISH_CONFIG_FILE:-$REPO_ROOT/config/publish.env}"

EXPECTED_PROJECT_NAME="${EXPECTED_PROJECT_NAME:-}"
EXPECTED_IMAGE_PREFIX="${EXPECTED_IMAGE_PREFIX:-ubuntu-}"
EXPECTED_SERVER_PREFIX="${EXPECTED_SERVER_PREFIX:-ubuntu-}"
EXPECTED_VOLUME_PREFIX="${EXPECTED_VOLUME_PREFIX:-ubuntu-}"

log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
warn(){ log "WARN: $*"; }
die(){ log "ERROR: $*"; exit 1; }

need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

need_cmd openstack
need_cmd awk
need_cmd sed
need_cmd head

[[ -f "$OPENSTACK_ENV_FILE" ]] || die "missing config: $OPENSTACK_ENV_FILE"
[[ -f "$OPENRC_PATH_FILE" ]] || die "missing config: $OPENRC_PATH_FILE"

# shellcheck disable=SC1090
source "$OPENSTACK_ENV_FILE"
# shellcheck disable=SC1090
source "$OPENRC_PATH_FILE"
imagectl_source_local_overrides "$REPO_ROOT"
imagectl_init_layout "$REPO_ROOT"

if [[ -z "$EXPECTED_PROJECT_NAME" ]]; then
  echo "EXPECTED_PROJECT_NAME is required (set in deploy/local/openstack.env or export in environment)" >&2
  exit 1
fi

[[ -n "${OPENRC_FILE:-}" ]] || die "OPENRC_FILE is empty in $OPENRC_PATH_FILE"
[[ -f "$OPENRC_FILE" ]] || die "openrc file not found: $OPENRC_FILE"

# shellcheck disable=SC1090
source "$OPENRC_FILE"

log "openrc sourced: $OPENRC_FILE"
openstack token issue >/dev/null

project_name="$(openstack project show -f value -c name "$OS_PROJECT_NAME" 2>/dev/null || true)"
project_id="$(openstack project show -f value -c id "$OS_PROJECT_NAME" 2>/dev/null || true)"
if [[ -z "$project_name" || -z "$project_id" ]]; then
  # fallback to token project id if name lookup failed
  project_id="$(openstack token issue -f value -c project_id 2>/dev/null || true)"
  project_name="$(openstack project show -f value -c name "$project_id" 2>/dev/null || true)"
fi

log "current project: name=${project_name:-unknown} id=${project_id:-unknown}"

if [[ "${project_name:-}" != "$EXPECTED_PROJECT_NAME" ]]; then
  die "project name mismatch: expected=$EXPECTED_PROJECT_NAME got=${project_name:-unknown}"
fi

PIPELINE_ROOT="${PIPELINE_ROOT:-$REPO_ROOT}"
OPENSTACK_MANIFEST_DIR="${OPENSTACK_MANIFEST_DIR:-$PIPELINE_ROOT/manifests/openstack}"
SUMMARY_FILE="$(imagectl_resolve_summary_for_read)"

DEFAULT_BASE_IMAGE_NAME_TEMPLATE="ubuntu-{version}-base-official"
DEFAULT_VM_NAME_TEMPLATE="ubuntu-{version}-ci-{ts}"
DEFAULT_VOLUME_NAME_TEMPLATE="{vm_name}-boot"

BASE_IMAGE_NAME_TEMPLATE="${BASE_IMAGE_NAME_TEMPLATE:-$DEFAULT_BASE_IMAGE_NAME_TEMPLATE}"
VM_NAME_TEMPLATE="${VM_NAME_TEMPLATE:-$DEFAULT_VM_NAME_TEMPLATE}"
VOLUME_NAME_TEMPLATE="${VOLUME_NAME_TEMPLATE:-$DEFAULT_VOLUME_NAME_TEMPLATE}"

FINAL_IMAGE_VISIBILITY="${FINAL_IMAGE_VISIBILITY:-private}"
ON_FINAL_EXISTS="${ON_FINAL_EXISTS:-recover}"
DELETE_SERVER_BEFORE_PUBLISH="${DELETE_SERVER_BEFORE_PUBLISH:-yes}"
DELETE_VOLUME_AFTER_PUBLISH="${DELETE_VOLUME_AFTER_PUBLISH:-yes}"
DELETE_BASE_IMAGE_AFTER_PUBLISH="${DELETE_BASE_IMAGE_AFTER_PUBLISH:-yes}"

if [[ -f "$PUBLISH_CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PUBLISH_CONFIG_FILE"
fi

validate_prefix() {
  local name="$1" expected_prefix="$2" label="$3"
  if [[ "$name" != "$expected_prefix"* ]]; then
    die "prefix check failed for $label: expected_prefix=$expected_prefix name=$name"
  fi
}

template_has_token() {
  local tpl="$1" token="$2"
  [[ "$tpl" == *"$token"* ]]
}

validate_templates() {
  local ok=yes

  if ! template_has_token "$BASE_IMAGE_NAME_TEMPLATE" "{version}"; then
    warn "BASE_IMAGE_NAME_TEMPLATE malformed: '$BASE_IMAGE_NAME_TEMPLATE' -> using default '$DEFAULT_BASE_IMAGE_NAME_TEMPLATE'"
    BASE_IMAGE_NAME_TEMPLATE="$DEFAULT_BASE_IMAGE_NAME_TEMPLATE"
    ok=no
  fi

  if ! template_has_token "$VM_NAME_TEMPLATE" "{version}" || ! template_has_token "$VM_NAME_TEMPLATE" "{ts}"; then
    warn "VM_NAME_TEMPLATE malformed: '$VM_NAME_TEMPLATE' -> using default '$DEFAULT_VM_NAME_TEMPLATE'"
    VM_NAME_TEMPLATE="$DEFAULT_VM_NAME_TEMPLATE"
    ok=no
  fi

  if ! template_has_token "$VOLUME_NAME_TEMPLATE" "{vm_name}"; then
    warn "VOLUME_NAME_TEMPLATE malformed: '$VOLUME_NAME_TEMPLATE' -> using default '$DEFAULT_VOLUME_NAME_TEMPLATE'"
    VOLUME_NAME_TEMPLATE="$DEFAULT_VOLUME_NAME_TEMPLATE"
    ok=no
  fi

  [[ "$ok" == yes ]]
}

log "validating naming prefixes"
validate_templates || true

example_version="24.04"
version_slug="${example_version//./-}"
example_base_image="${BASE_IMAGE_NAME_TEMPLATE//\{version\}/$example_version}"
example_vm_name="${VM_NAME_TEMPLATE//\{version\}/$version_slug}"
example_vm_name="${example_vm_name//\{ts\}/00000000000000}"
example_volume_name="${VOLUME_NAME_TEMPLATE//\{vm_name\}/$example_vm_name}"
today_yyyymmdd="$(date +%Y%m%d)"
example_final_image="ubuntu-${example_version}-complete-${today_yyyymmdd}"

validate_prefix "$example_base_image" "$EXPECTED_IMAGE_PREFIX" "base image"
validate_prefix "$example_final_image" "$EXPECTED_IMAGE_PREFIX" "final image"
validate_prefix "$example_vm_name" "$EXPECTED_SERVER_PREFIX" "server"
validate_prefix "$example_volume_name" "$EXPECTED_VOLUME_PREFIX" "volume"

log "prefix checks passed"

log "candidate resources (by version)"
if [[ -z "$SUMMARY_FILE" ]]; then
  die "SUMMARY_FILE is empty; set SUMMARY_FILE or run download step to generate it"
fi
if [[ -f "$SUMMARY_FILE" ]]; then
  mapfile -t versions < <(awk -F '\t' 'NR>1 && $1 != "" && !seen[$1]++ {print $1}' "$SUMMARY_FILE")
  for version in "${versions[@]}"; do
    version_slug="${version//./-}"
    base_image="${BASE_IMAGE_NAME_TEMPLATE//\{version\}/$version}"
    vm_name="${VM_NAME_TEMPLATE//\{version\}/$version_slug}"
    vm_name="${vm_name//\{ts\}/<ts>}"
    volume_name="${VOLUME_NAME_TEMPLATE//\{vm_name\}/$vm_name}"
    final_image="ubuntu-${version}-complete-${today_yyyymmdd}"
    printf '%s\n' "version=$version"
    printf '%s\n' "  base_image=$base_image"
    printf '%s\n' "  server=$vm_name"
    printf '%s\n' "  volume=$volume_name"
    printf '%s\n' "  final_image=$final_image"
  done
else
  die "summary file not found: $SUMMARY_FILE (run download step to generate it)"
fi

log "deletion policy (from publish config)"
log "DELETE_SERVER_BEFORE_PUBLISH=$DELETE_SERVER_BEFORE_PUBLISH"
log "DELETE_VOLUME_AFTER_PUBLISH=$DELETE_VOLUME_AFTER_PUBLISH"
log "DELETE_BASE_IMAGE_AFTER_PUBLISH=$DELETE_BASE_IMAGE_AFTER_PUBLISH"
log "FINAL_IMAGE_VISIBILITY=$FINAL_IMAGE_VISIBILITY"
log "ON_FINAL_EXISTS=$ON_FINAL_EXISTS"

log "listing existing resources with expected prefixes (read-only)"
log "images:"
openstack image list --name "$EXPECTED_IMAGE_PREFIX" -f value -c Name -c ID | sed 's/^/  /' || true
log "servers:"
openstack server list --name "$EXPECTED_SERVER_PREFIX" -f value -c Name -c ID | sed 's/^/  /' || true
log "volumes:"
openstack volume list --name "$EXPECTED_VOLUME_PREFIX" -f value -c Name -c ID | sed 's/^/  /' || true

log "preflight OK"
