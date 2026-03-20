#!/usr/bin/env bash
set -Eeuo pipefail

# ── Remote resource helpers ───────────────────────────────────────────────────

# Read resource IDs for an OS+version from remote state files.
# Outputs lines: "type=id"  (id may be empty if not found)
imagectl_cleanup_get_resources() {
  local os="$1" version="$2"
  imagectl_run_remote_repo_cmd "$(cat <<REMOTESCRIPT
set -euo pipefail
os='$os'; ver='$version'
sd="runtime/state/\$os/\$ver"

get_val() {
  local f="\$sd/\$1" k="\$2"
  [[ -f "\$f" ]] && grep -m1 "^\$k=" "\$f" | cut -d= -f2- || true
}

printf "base_image=%s\n" "\$(get_val last-import.env    BASE_IMAGE_ID)"
printf "server=%s\n"     "\$(get_val last-vm.env        SERVER_ID)"
printf "volume=%s\n"     "\$(get_val last-vm.env        VOLUME_ID)"
printf "final_image=%s\n" "\$(get_val last-publish.env  FINAL_IMAGE_ID)"
REMOTESCRIPT
)" 2>/dev/null || true
}

# ── Preview ───────────────────────────────────────────────────────────────────

imagectl_cleanup_preview_version() {
  local os="$1" version="$2"
  local resources type id status

  resources="$(imagectl_cleanup_get_resources "$os" "$version")"

  printf '\n┌────────────────────────────────────────────────────────────┐\n'
  printf '│  จะลบ (Will delete): %-38s│\n' "$os $version"
  printf '├────────────────────────────────────────────────────────────┤\n'

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    type="${line%%=*}"
    id="${line#*=}"
    if [[ -n "$id" ]]; then
      status="[พบ / found]"
    else
      id="<not found>"
      status="[ไม่พบ / skip]"
    fi
    printf '│  %-16s %-32s %-8s│\n' "$type" "$id" "$status"
  done <<< "$resources"

  printf '└────────────────────────────────────────────────────────────┘\n'
}

# ── Execute cleanup ───────────────────────────────────────────────────────────

# Delete all resources for an OS+version on the remote (graceful — skip missing).
imagectl_cleanup_do_version() {
  local os="$1" version="$2"
  imagectl_log "cleanup: os=$os version=$version"

  imagectl_run_remote_repo_cmd "$(cat <<REMOTESCRIPT
set -euo pipefail

# Source openrc (graceful)
openrc_file="\$(grep -m1 '^OPENRC_FILE=' deploy/local/openrc.path 2>/dev/null | cut -d= -f2- || true)"
[[ -n "\$openrc_file" && -f "\$openrc_file" ]] && source "\$openrc_file" || true

os='$os'; ver='$version'
sd="runtime/state/\$os/\$ver"

get_val() {
  local f="\$sd/\$1" k="\$2"
  [[ -f "\$f" ]] && grep -m1 "^\$k=" "\$f" | cut -d= -f2- || true
}

base_image_id="\$(get_val last-import.env   BASE_IMAGE_ID)"
server_id="\$(    get_val last-vm.env       SERVER_ID)"
volume_id="\$(    get_val last-vm.env       VOLUME_ID)"
final_image_id="\$(get_val last-publish.env FINAL_IMAGE_ID)"

try_delete() {
  local label="\$1" cmd="\$2" id="\$3"
  if [[ -z "\$id" ]]; then
    printf "  %-16s → skip (no ID in state)\n" "\$label"
    return 0
  fi
  printf "  %-16s %s → " "\$label" "\$id"
  if eval "\$cmd '\$id'" 2>/dev/null; then
    printf "deleted\n"
  else
    printf "not found or already deleted\n"
  fi
}

# Delete in safe order: server first, then volume, then images
try_delete "server"      "openstack server delete --wait" "\$server_id"
try_delete "volume"      "openstack volume delete"        "\$volume_id"
try_delete "base_image"  "openstack image delete"         "\$base_image_id"
try_delete "final_image" "openstack image delete"         "\$final_image_id"

printf "  cleanup done: %s %s\n" "\$os" "\$ver"
REMOTESCRIPT
)" || true
}

# ── Interactive cleanup helpers ───────────────────────────────────────────────

_imagectl_cleanup_select_version() {
  local os="$1"
  local versions=()
  mapfile -t versions < <(imagectl_status_versions_for_os "$os")
  if [[ "${#versions[@]}" -eq 0 ]]; then
    imagectl_die "no versions configured for os=$os (check config/os/$os/)"
  fi
  imagectl_select_from_list "Select version (เลือก version) for $os" "${versions[@]}"
}

# ── Public menu actions ───────────────────────────────────────────────────────

imagectl_cleanup_by_version() {
  imagectl_prepare_remote_pipeline_context

  local os version
  os="$(imagectl_select_os_interactive)"
  os="$(imagectl_require_supported_os "$os")"
  version="$(_imagectl_cleanup_select_version "$os")"

  imagectl_cleanup_preview_version "$os" "$version"
  printf '\n'

  if ! imagectl_prompt_yes_no "ยืนยันการลบ / Confirm delete $os $version?"; then
    imagectl_log "cleanup cancelled"
    return 0
  fi

  imagectl_cleanup_do_version "$os" "$version"
}

imagectl_cleanup_by_os() {
  imagectl_prepare_remote_pipeline_context

  local os versions=() version
  os="$(imagectl_select_os_interactive)"
  os="$(imagectl_require_supported_os "$os")"
  mapfile -t versions < <(imagectl_status_versions_for_os "$os")

  if [[ "${#versions[@]}" -eq 0 ]]; then
    imagectl_log "no versions configured for os=$os"
    return 0
  fi

  for version in "${versions[@]}"; do
    imagectl_cleanup_preview_version "$os" "$version"
  done
  printf '\n'

  if ! imagectl_prompt_yes_no "ยืนยันการลบทั้งหมด / Confirm delete ALL versions of $os?"; then
    imagectl_log "cleanup cancelled"
    return 0
  fi

  for version in "${versions[@]}"; do
    imagectl_cleanup_do_version "$os" "$version"
  done
}

imagectl_cleanup_all() {
  imagectl_prepare_remote_pipeline_context

  local oses=() os versions=() version
  mapfile -t oses < <(imagectl_list_supported_oses)

  printf '\nจะลบทุก OS ทุก version (Will delete ALL OS ALL versions):\n'
  for os in "${oses[@]}"; do
    mapfile -t versions < <(imagectl_status_versions_for_os "$os")
    [[ "${#versions[@]}" -gt 0 ]] || continue
    for version in "${versions[@]}"; do
      imagectl_cleanup_preview_version "$os" "$version"
    done
  done
  printf '\n'

  if ! imagectl_prompt_yes_no "คุณแน่ใจ? / Are you sure? This will DELETE ALL resources (yes/no)"; then
    imagectl_log "cleanup cancelled"
    return 0
  fi
  if ! imagectl_prompt_yes_no "ยืนยันอีกครั้ง / Confirm again — cannot be undone (yes/no)"; then
    imagectl_log "cleanup cancelled"
    return 0
  fi

  for os in "${oses[@]}"; do
    mapfile -t versions < <(imagectl_status_versions_for_os "$os")
    [[ "${#versions[@]}" -gt 0 ]] || continue
    for version in "${versions[@]}"; do
      imagectl_cleanup_do_version "$os" "$version"
    done
  done
}

# ── Menu ─────────────────────────────────────────────────────────────────────

imagectl_menu_cleanup() {
  while true; do
    local choice
    choice="$(imagectl_select_from_list "Cleanup (ลบ resource ใน OpenStack)" \
      "By Version   (เลือก OS + version)" \
      "By OS        (เลือก OS → ลบทุก version)" \
      "Clean All    (ลบทุกอย่างทุก OS)" \
      "Back         (กลับ)")"

    case "$choice" in
      "By Version"*) imagectl_cleanup_by_version ;;
      "By OS"*)      imagectl_cleanup_by_os ;;
      "Clean All"*)  imagectl_cleanup_all ;;
      "Back"*)       break ;;
    esac
  done
}
