# Auto-Discover Upstream Versions — Implementation Summary

Date: 2026-03-23
Branch: fix/fresh-clone-and-paths

---

## Files Changed

- `lib/common_utils.sh` — added `_sync_discover_upstream_versions()` + `_sync_update_tracked_versions()`
- `scripts/control.sh` — updated `_menu_sync_all_dry_run()` + `_menu_sync_os_dry_run()`
- `config/os/ubuntu/sync.env` — MIN_VERSION=24.04, TRACKED_VERSIONS updated, AUTO_DISCOVER=1, LTS_ONLY=1
- `config/os/debian/sync.env` — MIN_VERSION=13, TRACKED_VERSIONS=13, AUTO_DISCOVER=1, LTS_ONLY=0
- `config/os/rocky/sync.env` — MIN_VERSION=8, TRACKED_VERSIONS="8 9", AUTO_DISCOVER=1, LTS_ONLY=0
- `config/os/almalinux/sync.env` — MIN_VERSION=8, TRACKED_VERSIONS="8 9", AUTO_DISCOVER=1, LTS_ONLY=0
- `config/os/fedora/sync.env` — MIN_VERSION=41, TRACKED_VERSIONS=41, AUTO_DISCOVER=1, LTS_ONLY=0

---

## Test Results

| Test | Command | Result | Notes |
|------|---------|--------|-------|
| T1 — discover ubuntu LTS | `_sync_discover_upstream_versions ubuntu` | PASS | Output: 24.04 25.04 (both xx.04, both >= 24.04) |
| T2 — discover rocky | `_sync_discover_upstream_versions rocky` | PASS | Output: 8 9 10 |
| T3 — discover almalinux | `_sync_discover_upstream_versions almalinux` | PASS | Output: 8 9 10 |
| T4 — discover debian | `_sync_discover_upstream_versions debian` | PASS | Output: 13 14 (trixie=13, forky=14) |
| T5 — discover fedora | `_sync_discover_upstream_versions fedora` | PASS | Output: 41 42 43 |
| T6 — update tracked versions | `_sync_update_tracked_versions ubuntu` | PASS | 24.04 [tracked], 25.04 [NEW]; TRACKED_VERSIONS auto-updated to "24.04 25.04" |
| T7 — sync.env values | grep all 5 sync.env files | PASS | All have correct MIN_VERSION, TRACKED_VERSIONS, AUTO_DISCOVER, LTS_ONLY |
| T8 — dry-run still works | `sync_download.sh --os ubuntu --dry-run` | PASS | Completed for both 24.04 and 25.04 |
| T9 — existing functions | `_sync_list_versions_for_os ubuntu` | PASS | Returns version list with [status] tags as before |
| T10 — ShellCheck | `shellcheck lib/common_utils.sh scripts/control.sh` | N/A | shellcheck not installed on Windows test host |

---

## Discovered Versions per OS (at time of test: 2026-03-23)

| OS | Upstream URL Scanned | Discovered Versions (>= MIN) | LTS Filter |
|----|---------------------|------------------------------|------------|
| ubuntu | cloud-images.ubuntu.com/releases/ | 24.04, 25.04 | xx.04 only (LTS_ONLY=1) |
| debian | cloud.debian.org/images/cloud/ | 13 (trixie), 14 (forky) | none (LTS_ONLY=0) |
| rocky | dl.rockylinux.org/pub/rocky/ | 8, 9, 10 | none (major only) |
| almalinux | repo.almalinux.org/almalinux/ | 8, 9, 10 | none (major only) |
| fedora | dl.fedoraproject.org/pub/fedora/linux/releases/ | 41, 42, 43 | none (major >= 41) |

---

## Auto-Update Behavior Verified

When `_sync_update_tracked_versions ubuntu` ran:
- Found 25.04 as [NEW] (not in TRACKED_VERSIONS="24.04")
- Automatically updated `config/os/ubuntu/sync.env`:
  - Before: `TRACKED_VERSIONS="24.04"`
  - After:  `TRACKED_VERSIONS="24.04 25.04"`
- `sync_download.sh --os ubuntu --dry-run` then correctly processed BOTH versions

---

## Implementation Notes

### _sync_discover_upstream_versions(os)
- Sources sync.env to read AUTO_DISCOVER, MIN_VERSION, LTS_ONLY
- Returns silently (return 0) if AUTO_DISCOVER != "1"
- Per-OS logic:
  - ubuntu: scans cloud-images.ubuntu.com/releases/, filters xx.04 if LTS_ONLY=1
  - debian: scans cloud.debian.org/images/cloud/, uses codename→version map
  - rocky: scans dl.rockylinux.org/pub/rocky/, major integer versions only
  - almalinux: scans repo.almalinux.org/almalinux/, major integer versions only
  - fedora: scans dl.fedoraproject.org/pub/fedora/linux/releases/, major >= MIN_VERSION

### _sync_update_tracked_versions(os)
- Calls _sync_discover_upstream_versions internally
- Compares discovered vs TRACKED_VERSIONS in sync.env
- Prints VERSION [tracked] or VERSION [NEW] for each discovered version
- Auto-updates TRACKED_VERSIONS in sync.env via sed -i when new versions found

### control.sh changes
- `_menu_sync_all_dry_run`: discovers all OS first, shows [tracked]/[NEW], then runs dry-run
- `_menu_sync_os_dry_run`: discovers selected OS, shows upstream versions, then dry-run

---

## HARD RULES Compliance

- phases/sync_download.sh: NOT modified
- Existing functions in common_utils.sh: NOT modified (only appended new functions)
- AUTO_DISCOVER=0: silently skips discovery (return 0 path verified)
- Ubuntu LTS filter: ^[0-9]+\.04$ regex only
- Debian codename→version: uses declare -A map
- Branch: stayed on fix/fresh-clone-and-paths throughout
