#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_runtime_config_items() {
  cat <<'EOF'
settings/jumphost.env
settings/git.env
settings/openstack.env
settings/openrc.env
settings/credentials.env
EOF
}

imagectl_runtime_required_remote_files() {
  cat <<'EOF'
settings/openstack.env
settings/openrc.env
settings/credentials.env
EOF
}

imagectl_runtime_default_for_key() {
  local key="$1"
  case "$key" in
    EXPECTED_PROJECT_NAME) printf '%s' "natties_op" ;;
    OPENRC_FILE) printf '%s' "/root/openrc-nut" ;;
    ROOT_USER) printf '%s' "root" ;;
    ROOT_PASSWORD) printf '%s' "" ;;
    NETWORK_ID) printf '%s' "PUBLIC2956" ;;
    FLAVOR_ID) printf '%s' "2-2-0" ;;
    SECURITY_GROUP) printf '%s' "allow-any" ;;
    VOLUME_TYPE) printf '%s' "cinder" ;;
    VOLUME_SIZE_GB) printf '%s' "10" ;;
    *) printf '%s' "" ;;
  esac
}

imagectl_runtime_merge_sources_local() {
  local repo_root="$IMAGECTL_REPO_ROOT"
  local settings_dir="$repo_root/settings"
  local f

  # Load tracked config defaults (OS-agnostic policy)
  for f in \
    "$repo_root/config/guest/base.env" \
    "$repo_root/config/pipeline/publish.env" \
    "$repo_root/config/pipeline/clean.env"
  do
    # shellcheck disable=SC1090
    [[ -f "$f" ]] && source "$f"
  done

  # Load private settings (gitignored — primary source)
  for f in \
    "$settings_dir/jumphost.env" \
    "$settings_dir/git.env" \
    "$settings_dir/openstack.env" \
    "$settings_dir/openrc.env" \
    "$settings_dir/credentials.env"
  do
    # shellcheck disable=SC1090
    [[ -f "$f" ]] && source "$f"
  done

  # Fallback: deploy/local/ for backward compatibility
  for f in \
    "$repo_root/deploy/local/control.env" \
    "$repo_root/deploy/local/openstack.env" \
    "$repo_root/deploy/local/openrc.path" \
    "$repo_root/deploy/local/guest-access.env"
  do
    # shellcheck disable=SC1090
    [[ -f "$f" ]] && source "$f"
  done
}

imagectl_runtime_effective_local_value() {
  local key="$1"
  (
    set -Eeuo pipefail
    local v=""
    imagectl_runtime_merge_sources_local
    # shellcheck disable=SC2154
    v="${!key:-}"
    if [[ -z "$v" ]]; then
      v="$(imagectl_runtime_default_for_key "$key")"
    fi
    printf '%s' "$v"
  )
}

imagectl_runtime_emit_assignment() {
  local key="$1"
  local value="$2"
  printf '%s=%q\n' "$key" "$value"
}

imagectl_runtime_emit_openstack_overlay() {
  local value=""
  local key=""
  local keys=(
    PIPELINE_ROOT
    SUMMARY_FILE
    OPENSTACK_MANIFEST_DIR
    STATE_DIR
    LOG_DIR
    EXPECTED_PROJECT_NAME
    NETWORK_ID
    FLAVOR_ID
    VOLUME_TYPE
    VOLUME_SIZE_GB
    SECURITY_GROUP
    KEY_NAME
    FLOATING_NETWORK
    EXISTING_FLOATING_IP
    BASE_IMAGE_NAME_TEMPLATE
    VM_NAME_TEMPLATE
    VOLUME_NAME_TEMPLATE
    OUTPUT_DIR
    WAIT_SERVER_ACTIVE_SECS
    WAIT_VOLUME_SECS
  )

  for key in "${keys[@]}"; do
    value="$(imagectl_runtime_effective_local_value "$key")"
    imagectl_runtime_emit_assignment "$key" "$value"
  done
}

imagectl_runtime_emit_guest_access_overlay() {
  local value=""
  local key=""
  local keys=(
    ROOT_USER
    ROOT_PASSWORD
    SSH_PORT
    ROOT_AUTHORIZED_KEY
  )

  for key in "${keys[@]}"; do
    value="$(imagectl_runtime_effective_local_value "$key")"
    imagectl_runtime_emit_assignment "$key" "$value"
  done
}

imagectl_runtime_emit_openrc_overlay() {
  local value=""
  value="$(imagectl_runtime_effective_local_value "OPENRC_FILE")"
  imagectl_runtime_emit_assignment "OPENRC_FILE" "$value"
}

imagectl_runtime_create_overlay_file() {
  local rel="$1"
  local local_src="$IMAGECTL_REPO_ROOT/$rel"
  local tmp_file

  tmp_file="$(mktemp)"
  case "$rel" in
    settings/*.env)
      # Settings files are uploaded as-is (they are the source of truth)
      [[ -f "$local_src" ]] && cat "$local_src" > "$tmp_file"
      ;;
    deploy/local/openstack.env)
      imagectl_runtime_emit_openstack_overlay > "$tmp_file"
      ;;
    deploy/local/openrc.path)
      imagectl_runtime_emit_openrc_overlay > "$tmp_file"
      ;;
    deploy/local/guest-access.env)
      imagectl_runtime_emit_guest_access_overlay > "$tmp_file"
      ;;
    deploy/local/publish.env)
      local tracked_src="$IMAGECTL_REPO_ROOT/config/pipeline/publish.env"
      if [[ -f "$local_src" ]]; then
        cat "$local_src" > "$tmp_file"
      elif [[ -f "$tracked_src" ]]; then
        cat "$tracked_src" > "$tmp_file"
      fi
      ;;
    deploy/local/clean.env)
      local tracked_src="$IMAGECTL_REPO_ROOT/config/pipeline/clean.env"
      if [[ -f "$local_src" ]]; then
        cat "$local_src" > "$tmp_file"
      elif [[ -f "$tracked_src" ]]; then
        cat "$tracked_src" > "$tmp_file"
      fi
      ;;
    *)
      rm -f "$tmp_file"
      imagectl_die "unsupported runtime overlay file: $rel"
      ;;
  esac

  printf '%s' "$tmp_file"
}

imagectl_runtime_required_keys_for_mutating() {
  cat <<'EOF'
EXPECTED_PROJECT_NAME
OPENRC_FILE
ROOT_USER
ROOT_PASSWORD
NETWORK_ID
FLAVOR_ID
SECURITY_GROUP
VOLUME_TYPE
VOLUME_SIZE_GB
EOF
}

imagectl_runtime_validate_required_local_base_files() {
  local file
  for file in \
    "$IMAGECTL_REPO_ROOT/settings/openstack.env" \
    "$IMAGECTL_REPO_ROOT/settings/openrc.env" \
    "$IMAGECTL_REPO_ROOT/settings/credentials.env"
  do
    [[ -f "$file" ]] || imagectl_die "missing settings file: $file  (copy from ${file}.example and fill in values)"
  done
}

imagectl_runtime_validate_local_values_for_mutating() {
  local key=""
  local value=""
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    value="$(imagectl_runtime_effective_local_value "$key")"
    [[ -n "$value" ]] || imagectl_die "missing runtime value: $key (set in settings/openstack.env or settings/credentials.env)"
  done < <(imagectl_runtime_required_keys_for_mutating)
}

imagectl_runtime_validate_local_for_full_pipeline() {
  imagectl_runtime_validate_required_local_base_files
  imagectl_runtime_validate_local_values_for_mutating
}

imagectl_runtime_validate_local_for_action() {
  local action="$1"
  case "$action" in
    import|create|configure|clean|publish)
      imagectl_runtime_validate_local_for_full_pipeline
      ;;
    *)
      return 0
      ;;
  esac
}

imagectl_runtime_sync_to_remote() {
  local rel=""
  local tmp_file=""
  local synced=0

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    case "$rel" in
      deploy/local/ssh_config|deploy/local/ssh/*)
        imagectl_die "refusing to sync forbidden local file: $rel"
        ;;
    esac
    tmp_file="$(imagectl_runtime_create_overlay_file "$rel")"
    if [[ -s "$tmp_file" ]]; then
      imagectl_upload_file_to_remote_repo "$tmp_file" "$rel"
      synced=$((synced + 1))
    fi
    rm -f "$tmp_file"
  done < <(imagectl_runtime_config_items)

  imagectl_log "runtime config sync done: files_synced=$synced (remote: $JUMP_HOST_REPO_PATH/settings/; ssh keys/config are never synced)"
}

imagectl_runtime_validate_remote_values_for_mutating() {
  local rel=""
  local rel_q=""
  local key=""
  local key_q=""

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    rel_q="$(printf '%q' "$rel")"
    imagectl_run_remote_repo_cmd "set -euo pipefail; f=$rel_q; [[ -f \"\$f\" ]] || { echo \"missing remote runtime config file: \$PWD/\$f\" >&2; exit 1; }"
  done < <(imagectl_runtime_required_remote_files)

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    key_q="$(printf '%q' "$key")"
    imagectl_run_remote_repo_cmd "set -euo pipefail; \
[[ -f settings/openstack.env ]]   && source settings/openstack.env; \
[[ -f settings/openrc.env ]]      && source settings/openrc.env; \
[[ -f settings/credentials.env ]] && source settings/credentials.env; \
k=$key_q; \
v=\${!k:-}; \
[[ -n \"\$v\" ]] || { echo \"missing remote runtime value: \$k (set in settings/openstack.env or settings/credentials.env)\" >&2; exit 1; }"
  done < <(imagectl_runtime_required_keys_for_mutating)
}

imagectl_runtime_validate_remote_for_full_pipeline() {
  imagectl_runtime_validate_remote_values_for_mutating
}

imagectl_runtime_validate_remote_for_action() {
  local action="$1"
  case "$action" in
    import|create|configure|clean|publish)
      imagectl_runtime_validate_remote_values_for_mutating
      ;;
    *)
      return 0
      ;;
  esac
}

imagectl_runtime_prepare_for_full_pipeline() {
  imagectl_runtime_validate_local_for_full_pipeline
  imagectl_runtime_sync_to_remote
  imagectl_runtime_validate_remote_for_full_pipeline
}

imagectl_runtime_prepare_for_action() {
  local action="$1"
  imagectl_runtime_validate_local_for_action "$action"
  imagectl_runtime_sync_to_remote
  imagectl_runtime_validate_remote_for_action "$action"
}
