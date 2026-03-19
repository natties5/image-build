#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_runtime_config_items() {
  cat <<'EOF'
deploy/local/guest-access.env
deploy/local/openstack.env
deploy/local/openrc.path
deploy/local/publish.env
deploy/local/clean.env
EOF
}

imagectl_runtime_required_local_files() {
  cat <<'EOF'
deploy/local/guest-access.env
EOF
}

imagectl_runtime_effective_root_password_local() {
  (
    set -Eeuo pipefail
    local repo_root="$IMAGECTL_REPO_ROOT"
    local f=""
    local ROOT_PASSWORD=""

    for f in \
      "$repo_root/config/guest/access.env" \
      "$repo_root/config/guest.env" \
      "$repo_root/deploy/local/guest-access.env"
    do
      if [[ -f "$f" ]]; then
        # shellcheck disable=SC1090
        source "$f"
      fi
    done
    printf '%s' "${ROOT_PASSWORD:-}"
  )
}

imagectl_runtime_validate_local_for_full_pipeline() {
  local file="$IMAGECTL_REPO_ROOT/deploy/local/guest-access.env"
  local root_password=""

  [[ -f "$file" ]] || imagectl_die "missing local runtime config file: $file (create it from deploy/guest-access.env.example)"
  root_password="$(imagectl_runtime_effective_root_password_local)"
  [[ -n "$root_password" ]] || imagectl_die "missing local runtime value ROOT_PASSWORD (expected in deploy/local/guest-access.env); fix local config before running auto pipeline"
}

imagectl_runtime_validate_local_for_action() {
  local action="$1"
  case "$action" in
    create|configure)
      imagectl_runtime_validate_local_for_full_pipeline
      ;;
    *)
      return 0
      ;;
  esac
}

imagectl_runtime_sync_to_remote() {
  local rel=""
  local src=""
  local synced=0

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src="$IMAGECTL_REPO_ROOT/$rel"
    if [[ -f "$src" ]]; then
      imagectl_upload_file_to_remote_repo "$src" "$rel"
      synced=$((synced + 1))
    fi
  done < <(imagectl_runtime_config_items)

  imagectl_log "runtime config sync done: files_synced=$synced (remote: $JUMP_HOST_REPO_PATH/deploy/local)"
}

imagectl_runtime_validate_remote_for_full_pipeline() {
  local rel=""
  local src=""
  local rel_q=""
  local guest_rel="deploy/local/guest-access.env"
  local guest_q=""

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src="$IMAGECTL_REPO_ROOT/$rel"
    if [[ -f "$src" ]]; then
      rel_q="$(printf '%q' "$rel")"
      imagectl_run_remote_repo_cmd "set -euo pipefail; f=$rel_q; [[ -f \"\$f\" ]] || { echo \"missing remote runtime config file: \$PWD/\$f (sync failed or file missing locally)\" >&2; exit 1; }"
    fi
  done < <(imagectl_runtime_config_items)

  guest_q="$(printf '%q' "$guest_rel")"
  imagectl_run_remote_repo_cmd "set -euo pipefail; \
f=$guest_q; \
[[ -f \"\$f\" ]] || { echo \"missing remote runtime config file: \$PWD/\$f\" >&2; exit 1; }; \
# shellcheck disable=SC1090 \
source \"\$f\"; \
[[ -n \"\${ROOT_PASSWORD:-}\" ]] || { echo \"missing remote runtime value ROOT_PASSWORD in \$PWD/\$f (set deploy/local/guest-access.env locally and rerun)\" >&2; exit 1; }"
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
  case "$action" in
    create|configure)
      imagectl_runtime_validate_remote_for_full_pipeline
      ;;
  esac
}
