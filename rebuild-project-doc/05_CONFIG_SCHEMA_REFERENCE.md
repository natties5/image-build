# 05 - Config Schema Reference (Current Keys)

Last updated: 2026-03-25

## 1) sync.env Core Keys
Used by `phases/sync_download.sh`:
- `OS_FAMILY`, `MIN_VERSION`, `TRACKED_VERSIONS`
- `AUTO_DISCOVER`, `LTS_ONLY` (menu helper logic)
- `DISCOVERY_MODE`, `LATEST_LOGIC`
- `INDEX_URL_TEMPLATE`, optional `INDEX_URL_FALLBACK`
- `CHECKSUM_FILE`, `HASH_ALGO`
- `ARCH_PRIORITY`, `FORMAT_PRIORITY`, `IMAGE_REGEX`
- optional `CODENAME_MAP` (Debian)

## 2) guest default/version keys (configure_guest)
Common identity and behavior:
- `GUEST_OS_FAMILY`, `GUEST_OS_NAME`, `GUEST_OS_VERSION`
- `GUEST_REPO_DRIVER` (`apt`, `dnf-repo`, etc.)
- `GUEST_UPDATE_COMMAND`, `GUEST_UPGRADE_COMMAND`, `GUEST_INSTALL_COMMAND`
- `GUEST_REQUIRED_PACKAGES`, `GUEST_ENABLE_SERVICES`, `GUEST_DISABLE_SERVICES`
- `GUEST_REBOOT_AFTER_UPGRADE`, `GUEST_REBOOT_TIMEOUT_SEC`
- `GUEST_SET_TIMEZONE`, `GUEST_TIMEZONE`, `GUEST_SET_LOCALE`, `GUEST_LOCALE`

Repo/vault behavior keys:
- `GUEST_REPO_BACKUP_DIR`
- `GUEST_REPO_BASELINE_UPDATE_COMMAND`
- `GUEST_REPO_VALIDATION_COMMAND`
- `GUEST_ENABLE_VAULT_FALLBACK`
- `GUEST_VAULT_URL`
- `GUEST_VAULT_VALIDATION_COMMAND`

Cleanup keys used in `clean_guest.sh`:
- `GUEST_CLEAN_*` family
- `GUEST_HISTORY_FILES`, `GUEST_TMP_PATHS`, `GUEST_LOG_PATHS`, `GUEST_MACHINE_ID_FILES`
- `GUEST_CLOUD_INIT_CLEAN_BEFORE_CAPTURE`, `GUEST_FSTRIM_BEFORE_SHUTDOWN`, `GUEST_FINAL_SHUTDOWN`

## 3) Notes on Legacy Keys
Some old keys may still exist in certain env files for historical compatibility.
Current active configure flow should be interpreted by the keys above and script behavior in `configure_guest.sh`.

## 4) Runtime JSON Fields to Expect
Sync JSON (key examples):
- `status`, `mode`, `filename`, `download_url`, `checksum`, `checksum_source`

Configure JSON (key examples):
- `repo_mode_used`, `repo_mode_reason`
- `official_degraded`, `vault_attempted`, `vault_reachable`, `vault_used`
- `steps_completed`

Publish JSON (key examples):
- `final_image_name`, `final_image_id`, cleanup booleans
