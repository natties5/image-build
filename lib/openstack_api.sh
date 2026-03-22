#!/usr/bin/env bash
# lib/openstack_api.sh — OpenStack CLI wrappers for all pipeline phases.
# Source after core_paths.sh and common_utils.sh.
set -Eeuo pipefail

# ─── Return code constants ─────────────────────────────────────────────────────
# 0  success
# 1  generic failure
# 4  auth/environment not ready
# 5  resource not found
# 6  resource already exists/conflict
# 7  timeout
# 8  bad status / state transition failure

# ─── Central openstack wrapper ────────────────────────────────────────────────
# Always call openstack through this function — never call openstack directly.
# Automatically prepends --insecure when OS_INSECURE=true or OPENSTACK_INSECURE=true.
openstack_cmd() {
  local args=()
  # Method A: OS_INSECURE env var (set in openrc or session)
  # Method B: OPENSTACK_INSECURE env var
  if [[ "${OS_INSECURE:-}" == "true" ]] || \
     [[ "${OPENSTACK_INSECURE:-}" == "true" ]]; then
    args+=("--insecure")
  fi
  openstack "${args[@]}" "$@"
}

# ─── Convenience wrappers (used by all phases) ────────────────────────────────
os_token_issue()      { openstack_cmd token issue "$@"; }
os_project_list()     { openstack_cmd project list -f json "$@"; }
os_network_list()     { openstack_cmd network list -f json "$@"; }
os_flavor_list()      { openstack_cmd flavor list -f json "$@"; }
os_volume_type_list() { openstack_cmd volume type list -f json "$@"; }
os_secgroup_list()    { openstack_cmd security group list -f json "$@"; }
os_router_list()      { openstack_cmd router list -f json "$@"; }

# ─── Auth / environment ───────────────────────────────────────────────────────

# Verify OpenStack auth is available (openrc sourced, token works)
os_require_auth() {
  util_log_info "NOT IMPLEMENTED: os_require_auth"
  return 0
}

os_get_current_project_id() {
  util_log_info "NOT IMPLEMENTED: os_get_current_project_id"
  return 0
}

os_get_project_name() {
  util_log_info "NOT IMPLEMENTED: os_get_project_name $*"
  return 0
}

os_validate_expected_project() {
  util_log_info "NOT IMPLEMENTED: os_validate_expected_project $*"
  return 0
}

# ─── Lookup helpers (for Settings menu) ───────────────────────────────────────

os_list_projects() {
  util_log_info "NOT IMPLEMENTED: os_list_projects"
  return 0
}

os_list_networks() {
  util_log_info "NOT IMPLEMENTED: os_list_networks"
  return 0
}

os_list_flavors() {
  util_log_info "NOT IMPLEMENTED: os_list_flavors"
  return 0
}

os_list_volume_types() {
  util_log_info "NOT IMPLEMENTED: os_list_volume_types"
  return 0
}

os_list_security_groups() {
  util_log_info "NOT IMPLEMENTED: os_list_security_groups"
  return 0
}

os_list_floating_networks() {
  util_log_info "NOT IMPLEMENTED: os_list_floating_networks"
  return 0
}

# ─── Image operations ─────────────────────────────────────────────────────────

# Find image ID by name (returns empty string if not found)
os_find_image_id_by_name() {
  # TODO: implement — see 06_OPENSTACK_PIPELINE_DESIGN.md §Import
  util_log_info "NOT IMPLEMENTED: os_find_image_id_by_name $*"
  return 0
}

os_image_exists() {
  util_log_info "NOT IMPLEMENTED: os_image_exists $*"
  return 0
}

os_get_image_status() {
  util_log_info "NOT IMPLEMENTED: os_get_image_status $*"
  return 0
}

os_create_base_image() {
  util_log_info "NOT IMPLEMENTED: os_create_base_image $*"
  return 0
}

os_delete_image() {
  util_log_info "NOT IMPLEMENTED: os_delete_image $*"
  return 0
}

os_set_image_tags() {
  util_log_info "NOT IMPLEMENTED: os_set_image_tags $*"
  return 0
}

os_set_image_properties() {
  util_log_info "NOT IMPLEMENTED: os_set_image_properties $*"
  return 0
}

# Wait for image to reach desired status with polling
os_wait_image_status() {
  util_log_info "NOT IMPLEMENTED: os_wait_image_status $*"
  return 0
}

# ─── Volume operations ────────────────────────────────────────────────────────

os_find_volume_id_by_name() {
  util_log_info "NOT IMPLEMENTED: os_find_volume_id_by_name $*"
  return 0
}

os_volume_exists() {
  util_log_info "NOT IMPLEMENTED: os_volume_exists $*"
  return 0
}

os_get_volume_status() {
  util_log_info "NOT IMPLEMENTED: os_get_volume_status $*"
  return 0
}

os_create_volume_from_image() {
  util_log_info "NOT IMPLEMENTED: os_create_volume_from_image $*"
  return 0
}

os_delete_volume() {
  util_log_info "NOT IMPLEMENTED: os_delete_volume $*"
  return 0
}

os_wait_volume_status() {
  util_log_info "NOT IMPLEMENTED: os_wait_volume_status $*"
  return 0
}

os_wait_volume_deletable() {
  util_log_info "NOT IMPLEMENTED: os_wait_volume_deletable $*"
  return 0
}

os_delete_volume_with_retry() {
  util_log_info "NOT IMPLEMENTED: os_delete_volume_with_retry $*"
  return 0
}

# ─── Server operations ────────────────────────────────────────────────────────

os_find_server_id_by_name() {
  util_log_info "NOT IMPLEMENTED: os_find_server_id_by_name $*"
  return 0
}

os_server_exists() {
  util_log_info "NOT IMPLEMENTED: os_server_exists $*"
  return 0
}

os_get_server_status() {
  util_log_info "NOT IMPLEMENTED: os_get_server_status $*"
  return 0
}

os_create_server_from_volume() {
  util_log_info "NOT IMPLEMENTED: os_create_server_from_volume $*"
  return 0
}

os_delete_server() {
  util_log_info "NOT IMPLEMENTED: os_delete_server $*"
  return 0
}

os_start_server() {
  util_log_info "NOT IMPLEMENTED: os_start_server $*"
  return 0
}

os_stop_server() {
  util_log_info "NOT IMPLEMENTED: os_stop_server $*"
  return 0
}

os_wait_server_status() {
  util_log_info "NOT IMPLEMENTED: os_wait_server_status $*"
  return 0
}

os_get_server_addresses() {
  util_log_info "NOT IMPLEMENTED: os_get_server_addresses $*"
  return 0
}

os_get_server_login_ip() {
  util_log_info "NOT IMPLEMENTED: os_get_server_login_ip $*"
  return 0
}

# ─── Floating IP operations ───────────────────────────────────────────────────

os_allocate_floating_ip() {
  util_log_info "NOT IMPLEMENTED: os_allocate_floating_ip $*"
  return 0
}

os_attach_floating_ip() {
  util_log_info "NOT IMPLEMENTED: os_attach_floating_ip $*"
  return 0
}

# ─── Final image publish operations ───────────────────────────────────────────

os_upload_volume_to_image() {
  util_log_info "NOT IMPLEMENTED: os_upload_volume_to_image $*"
  return 0
}

os_find_or_wait_image_id_by_name() {
  util_log_info "NOT IMPLEMENTED: os_find_or_wait_image_id_by_name $*"
  return 0
}

os_apply_final_image_metadata() {
  util_log_info "NOT IMPLEMENTED: os_apply_final_image_metadata $*"
  return 0
}

os_final_image_exists_active() {
  util_log_info "NOT IMPLEMENTED: os_final_image_exists_active $*"
  return 0
}

os_recover_existing_final_image() {
  util_log_info "NOT IMPLEMENTED: os_recover_existing_final_image $*"
  return 0
}
