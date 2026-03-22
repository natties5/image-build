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

os_require_auth() {
  util_log_info "Checking OpenStack auth..."
  openstack_cmd token issue -f value -c id >/dev/null 2>&1 || {
    util_log_error "OpenStack auth failed — is openrc sourced?"
    return 4
  }
  util_log_info "OpenStack auth OK"
}

os_get_current_project_id() {
  openstack_cmd token issue -f value -c project_id 2>/dev/null
}

os_get_project_name() {
  openstack_cmd project show "$1" -f value -c name 2>/dev/null
}

os_validate_expected_project() {
  local expected="$1"
  local current; current="$(openstack_cmd project show "$(os_get_current_project_id)" -f value -c name 2>/dev/null || echo '')"
  if [[ "$current" != "$expected" ]]; then
    util_log_error "Project mismatch: expected=$expected current=$current"
    return 8
  fi
  util_log_info "Project validated: $current"
}

# ─── Lookup helpers (for Settings menu) ───────────────────────────────────────

os_list_projects()         { openstack_cmd project list -f value -c Name 2>/dev/null; }
os_list_networks()         { openstack_cmd network list -f value -c Name 2>/dev/null; }
os_list_flavors()          { openstack_cmd flavor list -f value -c Name 2>/dev/null; }
os_list_volume_types()     { openstack_cmd volume type list -f value -c Name 2>/dev/null; }
os_list_security_groups()  { openstack_cmd security group list -f value -c Name 2>/dev/null; }
os_list_floating_networks(){ openstack_cmd network list --external -f value -c Name 2>/dev/null; }

# ─── Image operations ─────────────────────────────────────────────────────────

# Find image ID by exact name — returns empty string if not found
# Usage: os_find_image_id_by_name <name>
os_find_image_id_by_name() {
  openstack_cmd image list --name "$1" -f value -c ID 2>/dev/null | head -1
}

# Return 0 if image exists (by name), 5 if not
# Usage: os_image_exists <name>
os_image_exists() {
  local id; id="$(os_find_image_id_by_name "$1")"
  [[ -n "$id" ]]
}

# Get current status of an image by ID
# Usage: os_get_image_status <image_id>
os_get_image_status() {
  openstack_cmd image show "$1" -f value -c status 2>/dev/null
}

# Create base image from a local file
# Usage: os_create_base_image <image_name> <local_path> <os_distro> <os_version> <visibility>
os_create_base_image() {
  local name="$1" path="$2" distro="$3" ver="$4" visibility="${5:-private}"
  util_log_info "Creating base image: $name from $path"
  openstack_cmd image create \
    --disk-format qcow2 \
    --container-format bare \
    --file "$path" \
    --property os_distro="$distro" \
    --property os_version="$ver" \
    --property pipeline_stage=base \
    "--${visibility}" \
    "$name" \
    -f value -c id 2>/dev/null
}

# Delete an image by ID
# Usage: os_delete_image <image_id>
os_delete_image() {
  util_log_info "Deleting image: $1"
  openstack_cmd image delete "$1" 2>/dev/null || true
}

os_set_image_tags() {
  util_log_info "NOT IMPLEMENTED: os_set_image_tags $*"
  return 0
}

os_set_image_properties() {
  util_log_info "NOT IMPLEMENTED: os_set_image_properties $*"
  return 0
}

# Poll until image reaches desired status
# Usage: os_wait_image_status <image_id> <desired_status> <timeout_sec> <interval_sec>
os_wait_image_status() {
  local image_id="$1" desired="$2" timeout_sec="$3" interval="${4:-10}"
  local elapsed=0
  util_log_info "Waiting for image $image_id to become $desired (timeout ${timeout_sec}s)"
  while (( elapsed < timeout_sec )); do
    local status; status="$(os_get_image_status "$image_id" 2>/dev/null || echo '')"
    if [[ "$status" == "$desired" ]]; then
      util_log_info "Image $image_id reached status: $desired"
      return 0
    fi
    if [[ "$status" == "killed" || "$status" == "deleted" ]]; then
      util_log_error "Image $image_id entered terminal bad status: $status"
      return 8
    fi
    if (( elapsed % 30 == 0 && elapsed > 0 )); then
      util_log_info "  waiting... status=${status} elapsed=${elapsed}s"
    fi
    sleep "$interval"
    elapsed=$(( elapsed + interval ))
  done
  local status; status="$(os_get_image_status "$image_id" 2>/dev/null || echo '')"
  util_log_error "Timeout waiting for image $image_id to reach $desired after ${timeout_sec}s (last: ${status})"
  return 7
}

# ─── Volume operations ────────────────────────────────────────────────────────

# Find volume ID by name — returns empty string if not found
# Usage: os_find_volume_id_by_name <name>
os_find_volume_id_by_name() {
  openstack_cmd volume show "$1" -f value -c id 2>/dev/null || echo ''
}

# Return 0 if volume exists (by name)
# Usage: os_volume_exists <name>
os_volume_exists() {
  local id; id="$(os_find_volume_id_by_name "$1")"
  [[ -n "$id" ]]
}

# Get current status of a volume by ID
# Usage: os_get_volume_status <volume_id>
os_get_volume_status() {
  openstack_cmd volume show "$1" -f value -c status 2>/dev/null
}

# Create a bootable volume from an image
# Usage: os_create_volume_from_image <volume_name> <image_id> <size_gb> <volume_type>
os_create_volume_from_image() {
  local name="$1" image_id="$2" size="$3" vtype="$4"
  util_log_info "Creating volume: $name (${size}GB) from image $image_id"
  openstack_cmd volume create \
    --size "$size" \
    --type "$vtype" \
    --image "$image_id" \
    --bootable \
    "$name" \
    -f value -c id 2>/dev/null
}

# Delete a volume by ID
# Usage: os_delete_volume <volume_id>
os_delete_volume() {
  util_log_info "Deleting volume: $1"
  openstack_cmd volume delete "$1" 2>/dev/null || true
}

# Poll until volume reaches desired status
# Usage: os_wait_volume_status <volume_id> <desired_status> <timeout_sec> <interval_sec>
os_wait_volume_status() {
  local vol_id="$1" desired="$2" timeout_sec="$3" interval="${4:-10}"
  local elapsed=0
  util_log_info "Waiting for volume $vol_id to become $desired (timeout ${timeout_sec}s)"
  while (( elapsed < timeout_sec )); do
    local status; status="$(os_get_volume_status "$vol_id" 2>/dev/null || echo '')"
    if [[ "$status" == "$desired" ]]; then
      util_log_info "Volume $vol_id reached status: $desired"
      return 0
    fi
    if [[ "$status" == "error" || "$status" == "error_deleting" ]]; then
      util_log_error "Volume $vol_id entered error status: $status"
      return 8
    fi
    if (( elapsed % 30 == 0 && elapsed > 0 )); then
      util_log_info "  waiting... status=${status} elapsed=${elapsed}s"
    fi
    sleep "$interval"
    elapsed=$(( elapsed + interval ))
  done
  local status; status="$(os_get_volume_status "$vol_id" 2>/dev/null || echo '')"
  util_log_error "Timeout waiting for volume $vol_id to reach $desired after ${timeout_sec}s (last: ${status})"
  return 7
}

os_wait_volume_deletable() {
  os_wait_volume_status "$1" "available" "${2:-600}" "${3:-10}"
}

os_delete_volume_with_retry() {
  local vol_id="$1" attempts="${2:-3}" sleep_sec="${3:-10}"
  util_retry "$attempts" "$sleep_sec" os_delete_volume "$vol_id"
}

# ─── Server operations ────────────────────────────────────────────────────────

# Find server ID by name — returns empty string if not found
# Usage: os_find_server_id_by_name <name>
os_find_server_id_by_name() {
  openstack_cmd server show "$1" -f value -c id 2>/dev/null || echo ''
}

# Return 0 if server exists (by name)
# Usage: os_server_exists <name>
os_server_exists() {
  local id; id="$(os_find_server_id_by_name "$1")"
  [[ -n "$id" ]]
}

# Get current status of a server by ID or name
# Usage: os_get_server_status <server_id_or_name>
os_get_server_status() {
  openstack_cmd server show "$1" -f value -c status 2>/dev/null
}

# Create a server booting from an existing volume
# Usage: os_create_server_from_volume <server_name> <flavor> <network_id_or_name> <secgroup> <volume_id>
os_create_server_from_volume() {
  local name="$1" flavor="$2" network="$3" secgroup="$4" vol_id="$5"
  util_log_info "Creating server: $name (flavor=$flavor network=$network)"
  openstack_cmd server create \
    --flavor "$flavor" \
    --volume "$vol_id" \
    --network "$network" \
    --security-group "$secgroup" \
    --property pipeline_stage=build \
    "$name" \
    -f value -c id 2>/dev/null
}

# Delete a server by ID or name
# Usage: os_delete_server <server_id_or_name>
os_delete_server() {
  util_log_info "Deleting server: $1"
  openstack_cmd server delete "$1" 2>/dev/null || true
}

os_start_server() {
  openstack_cmd server start "$1" 2>/dev/null
}

os_stop_server() {
  openstack_cmd server stop "$1" 2>/dev/null
}

# Poll until server reaches desired status
# Usage: os_wait_server_status <server_id_or_name> <desired_status> <timeout_sec> <interval_sec>
os_wait_server_status() {
  local server="$1" desired="$2" timeout_sec="$3" interval="${4:-10}"
  local elapsed=0
  util_log_info "Waiting for server $server to become $desired (timeout ${timeout_sec}s)"
  while (( elapsed < timeout_sec )); do
    local status; status="$(os_get_server_status "$server" 2>/dev/null || echo 'DELETED')"
    # When waiting for DELETED, no output = success
    if [[ "$desired" == "DELETED" && (-z "$status" || "$status" == "DELETED") ]]; then
      util_log_info "Server $server is gone (DELETED)"
      return 0
    fi
    if [[ "$status" == "$desired" ]]; then
      util_log_info "Server $server reached status: $desired"
      return 0
    fi
    if [[ "$status" == "ERROR" && "$desired" != "ERROR" ]]; then
      util_log_error "Server $server entered ERROR status"
      return 8
    fi
    if (( elapsed % 30 == 0 && elapsed > 0 )); then
      util_log_info "  waiting... status=${status} elapsed=${elapsed}s"
    fi
    sleep "$interval"
    elapsed=$(( elapsed + interval ))
  done
  local status; status="$(os_get_server_status "$server" 2>/dev/null || echo '')"
  util_log_error "Timeout waiting for server $server to reach $desired after ${timeout_sec}s (last: ${status})"
  return 7
}

# Wait for server to be fully deleted (not just in DELETED state)
# Usage: os_wait_server_deleted <server_id_or_name> <timeout_sec> <interval_sec>
os_wait_server_deleted() {
  local server="$1" timeout_sec="${2:-300}" interval="${3:-10}"
  local elapsed=0
  util_log_info "Waiting for server $server to be deleted (timeout ${timeout_sec}s)"
  while (( elapsed < timeout_sec )); do
    if ! openstack_cmd server show "$server" >/dev/null 2>&1; then
      util_log_info "Server $server is gone"
      return 0
    fi
    local status; status="$(os_get_server_status "$server" 2>/dev/null || echo 'DELETED')"
    if (( elapsed % 30 == 0 && elapsed > 0 )); then
      util_log_info "  waiting for deletion... status=${status} elapsed=${elapsed}s"
    fi
    sleep "$interval"
    elapsed=$(( elapsed + interval ))
  done
  util_log_error "Timeout waiting for server $server to be deleted after ${timeout_sec}s"
  return 7
}

# Get server IP address (first fixed IP from any network)
# Usage: os_get_server_addresses <server_id_or_name>
os_get_server_addresses() {
  openstack_cmd server show "$1" -f value -c addresses 2>/dev/null
}

# Get the login IP for a server (first IPv4 from addresses)
# Usage: os_get_server_login_ip <server_id_or_name>
os_get_server_login_ip() {
  local raw_addr; raw_addr="$(os_get_server_addresses "$1" 2>/dev/null || echo '')"
  # Extract first IPv4 from raw addresses string
  echo "$raw_addr" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# ─── Floating IP operations ───────────────────────────────────────────────────

os_allocate_floating_ip() {
  openstack_cmd floating ip create "$1" -f value -c floating_ip_address 2>/dev/null
}

os_attach_floating_ip() {
  openstack_cmd server add floating ip "$1" "$2" 2>/dev/null
}

# ─── Final image publish operations ───────────────────────────────────────────

# Upload a volume as a new Glance image
# Note: --property and --private are not supported with --volume on most OpenStack versions.
# We create the image first, then set properties and visibility in a second step.
# Usage: os_upload_volume_to_image <volume_id> <image_name> <os_distro> <os_version>
os_upload_volume_to_image() {
  local vol_id="$1" name="$2" distro="$3" ver="$4"
  util_log_info "Uploading volume $vol_id as image: $name"
  # Step 1: create image from volume (no --property or --private here)
  local img_id
  img_id="$(openstack_cmd image create \
    --disk-format qcow2 \
    --container-format bare \
    --volume "$vol_id" \
    "$name" \
    -f value -c id 2>/dev/null)" || true
  if [[ -z "$img_id" ]]; then
    util_log_warn "image create returned empty id — searching by name..."
    img_id="$(os_find_image_id_by_name "$name" 2>/dev/null || echo '')"
  fi
  if [[ -z "$img_id" ]]; then
    util_log_error "os_upload_volume_to_image: failed to get image ID"
    return 1
  fi
  util_log_info "Image created from volume: $img_id — setting metadata..."
  # Step 2: set properties and visibility
  openstack_cmd image set \
    --property os_distro="$distro" \
    --property os_version="$ver" \
    --property pipeline_stage=complete \
    --private \
    "$img_id" 2>/dev/null || true
  echo "$img_id"
}

# Find image ID by name, polling until it appears (for volume-upload which creates asynchronously)
# Usage: os_find_or_wait_image_id_by_name <name> <timeout_sec> <interval_sec>
os_find_or_wait_image_id_by_name() {
  local name="$1" timeout_sec="${2:-300}" interval="${3:-10}"
  local elapsed=0
  while (( elapsed < timeout_sec )); do
    local id; id="$(os_find_image_id_by_name "$name" 2>/dev/null || echo '')"
    if [[ -n "$id" ]]; then
      echo "$id"
      return 0
    fi
    sleep "$interval"
    elapsed=$(( elapsed + interval ))
  done
  util_log_error "Timeout waiting for image '$name' to appear in Glance after ${timeout_sec}s"
  return 7
}

os_apply_final_image_metadata() {
  util_log_info "NOT IMPLEMENTED: os_apply_final_image_metadata $*"
  return 0
}

# Return 0 (and print image ID) if final image exists and is active
# Usage: os_final_image_exists_active <image_name>
os_final_image_exists_active() {
  local name="$1"
  local id; id="$(os_find_image_id_by_name "$name" 2>/dev/null || echo '')"
  [[ -z "$id" ]] && return 5
  local status; status="$(os_get_image_status "$id" 2>/dev/null || echo '')"
  if [[ "$status" == "active" ]]; then
    echo "$id"
    return 0
  fi
  return 1
}

# Recover an existing final image (find its ID, wait for active)
# Usage: os_recover_existing_final_image <image_name> <timeout_sec> <interval_sec>
os_recover_existing_final_image() {
  local name="$1" timeout_sec="${2:-600}" interval="${3:-10}"
  local id; id="$(os_find_image_id_by_name "$name" 2>/dev/null || echo '')"
  [[ -z "$id" ]] && { util_log_error "recover: image '$name' not found"; return 5; }
  os_wait_image_status "$id" "active" "$timeout_sec" "$interval" || return $?
  echo "$id"
}
