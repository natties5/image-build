# 08 — Helper Libraries Design

เอกสารนี้เป็น design spec ของ helper libraries หลัก

- `lib/common_utils.sh`
- `lib/openstack_api.sh`

จุดประสงค์คือไม่ให้ logic polling / timeout / retry / openstack command / logging กระจายซ้ำเต็มทุก phase

---

## 1. Naming conventions

### Common utilities
Prefixes:
- `util_`
- `state_`
- `ssh_`
- `json_`
- `template_`

### OpenStack wrappers
Prefix:
- `os_`

---

## 2. Return code standard

Recommended meaning:
- `0` success / true
- `1` generic failure / false
- `2` invalid argument
- `3` missing dependency
- `4` auth/environment not ready
- `5` resource not found
- `6` resource already exists / conflict
- `7` timeout
- `8` bad status / state transition failure
- `9` SSH/remote execution failure
- `10` parse failure
- `11` retry exhausted
- `12` cleanup warning / non-fatal cleanup issue

---

## 3. `lib/common_utils.sh`

### Logging / error
- `util_log_info <message>`
- `util_log_warn <message>`
- `util_log_error <message>`
- `util_die <message> [return_code]`
- `util_init_log_file <path>`
- `util_enable_error_trap`
- `util_trap_handler <exit_code> <line_no> <command>`

### Dependency
- `util_require_cmd <cmd>`
- `util_require_cmds <cmd1> <cmd2> ...`

### File/path
- `util_ensure_dir <dir>`
- `util_ensure_parent_dir <file>`
- `util_safe_copy <src> <dst>`
- `util_safe_move <src> <dst>`
- `util_file_exists_nonempty <path>`

### Retry/timeout/poll
- `util_retry <attempts> <sleep> <command...>`
- `util_with_timeout <seconds> <command...>`
- `util_poll_until <timeout> <interval> <description> <command...>`

### Template/string helpers
- `template_render <template> key=value ...`
- `template_require_tokens <template> <token1> <token2> ...`
- `util_extract_first_ipv4 <raw_string>`
- `util_csv_to_lines <csv_string>`

### SSH/SCP helpers
- `ssh_run <host> <port> <user> <auth_mode> <auth_value> <remote_command>`
- `scp_put <host> <port> <user> <auth_mode> <auth_value> <local> <remote>`
- `scp_get <host> <port> <user> <auth_mode> <auth_value> <remote> <local>`
- `ssh_wait_ready <host> <port> <user> <auth_mode> <auth_value> <timeout> <interval>`

### State / JSON
- `state_flag_path <phase> <os_family> <os_version> <state_name>`
- `state_write_flag <phase> <os_family> <os_version> <state_name>`
- `state_clear_flag <phase> <os_family> <os_version> <state_name>`
- `state_mark_ready <phase> <os_family> <os_version>`
- `state_mark_failed <phase> <os_family> <os_version>`
- `state_mark_partial <phase> <os_family> <os_version>`
- `json_escape <raw_string>`
- `json_write_file <path> <content>`
- `state_write_runtime_json <phase> <os_family> <os_version> <json_path_or_content>`

---

## 4. `lib/openstack_api.sh`

### Auth / environment
- `os_require_auth`
- `os_get_current_project_id`
- `os_get_project_name <project_ref>`
- `os_validate_expected_project <expected_project_name>`

### Lookup for menus
- `os_list_projects`
- `os_list_networks`
- `os_list_flavors`
- `os_list_volume_types`
- `os_list_security_groups`
- `os_list_floating_networks`

### Image
- `os_find_image_id_by_name <name>`
- `os_image_exists <image_ref>`
- `os_get_image_status <image_id>`
- `os_create_base_image <image_name> <local_path> <disk_format> <visibility> ...`
- `os_delete_image <image_id>`
- `os_set_image_tags <image_id> <csv_tags>`
- `os_set_image_properties <image_id> key=value ...`
- `os_wait_image_status <image_id> <desired> <timeout> <interval>`

### Volume
- `os_find_volume_id_by_name <name>`
- `os_volume_exists <volume_ref>`
- `os_get_volume_status <volume_id>`
- `os_create_volume_from_image <volume_name> <image_id> <size_gb> <volume_type>`
- `os_delete_volume <volume_id>`
- `os_wait_volume_status <volume_id> <desired> <timeout> <interval>`
- `os_wait_volume_deletable <volume_id> <timeout> <interval>`
- `os_delete_volume_with_retry <volume_id> <attempts> <retry_sleep>`

### Server
- `os_find_server_id_by_name <name>`
- `os_server_exists <server_ref>`
- `os_get_server_status <server_id>`
- `os_create_server_from_volume <server_name> <flavor_id> <network_id> <security_group> <volume_id> <user_data_file> [key_name]`
- `os_delete_server <server_id>`
- `os_start_server <server_id>`
- `os_stop_server <server_id>`
- `os_wait_server_status <server_id> <desired> <timeout> <interval>`
- `os_get_server_addresses <server_id>`
- `os_get_server_login_ip <server_id> [preferred_floating_ip]`

### Floating IP
- `os_allocate_floating_ip <network>`
- `os_attach_floating_ip <server_id> <floating_ip>`

### Final image publish
- `os_upload_volume_to_image <volume_id> <final_image_name> <disk_format> <container_format> <force_flag>`
- `os_find_or_wait_image_id_by_name <image_name> <timeout> <interval>`
- `os_apply_final_image_metadata <image_id> <visibility> <tags_csv> <os_family> <os_version> <source_server_id> <source_volume_id> <source_base_image_id>`
- `os_final_image_exists_active <final_image_name>`
- `os_recover_existing_final_image <final_image_name> <timeout> <interval>`

---

## 5. Which phase uses what

### Import
- require commands
- auth check
- image exists/find/create/wait/tags/properties

### Create
- create volume
- wait volume
- create server
- wait server
- floating IP
- login IP

### Configure / Clean
- ssh/scp helpers
- timeout helpers
- server status checks where needed

### Publish
- final image exists/recover
- delete server
- wait volume available
- upload volume to image
- wait image active
- cleanup volume/image

---

## 6. What NOT to put here

### Not in `openstack_api.sh`
- menu logic
- config merge logic
- guest OLS logic
- locale/timezone policy
- file structure/path rules

### Not in `common_utils.sh`
- raw OpenStack workflow orchestration
- distro-specific guest policy
- business logic of one single phase

---

## 7. Why this split is correct

Because it gives:
- smaller phase files
- consistent timeout/retry behavior
- reusable status checks
- easier testing
- easier AI reasoning
- less duplicated shell code
