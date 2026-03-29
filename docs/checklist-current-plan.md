# Sync Checklist (Phase 0–6) - Post Dynamic Discovery

Status indicators:
- `[ ]` Not passed / Not done
- `[x]` Passed
- `[~]` Partially done
- `[-]` Not applicable to this round

---

## Config Structure (Refactored)
- [x] `config/sync-config.json` contains only global/shared settings
- [x] `config/os/ubuntu.json` created with min_version, max_version (optional), selection_policy, aliases, architectures, sources, discovery
- [x] `config/os/debian.json` created with min_version, max_version (optional), selection_policy, aliases, architectures, sources, discovery
- [x] `config/os/rocky.json` created with min_version, architectures, sources, discovery
- [x] `config/os/almalinux.json` created with min_version, architectures, sources, discovery
- [x] `config/os/fedora.json` created with enabled=false, discovery configuration
- [x] Loader reads and merges split configs correctly
- [x] Backward compatibility preserved for CLI interface

---

## Version Policy Model
- [x] **min_version**: Required field, enforced in validation
- [x] **max_version**: Optional field (null or omitted), enforced only if present
- [x] **selection_policy**: Support "explicit" and "latest" modes
- [x] **release_channel**: Documented field for release classification
- [x] **enabled**: Boolean flag to enable/disable OS
- [x] Version bounds checking with proper error messages

---

## Phase 0: Input intake and normalization
- [x] Has main inputs os / version / arch
- [x] Can normalize os
- [x] Can normalize version alias
- [x] Can normalize architecture
- [x] Validates input edge cases (unsupported os/version/arch)
- [x] Rejects invalid combinations for all cases
- [x] Supports "auto" and "latest" as version selectors (Debian, Fedora when enabled)

---

## Phase 1: Policy loading and source mapping
- [x] Loads `config/sync-config.json` (global settings)
- [x] Loads `config/os/*.json` (per-OS settings)
- [x] Merges configs into runtime structure
- [x] Maps OS/version to source policy
- [x] Maps alias to canonical version
- [x] Has host allowlist
- [x] Coverage Ubuntu 20.04, 22.04, 24.04
- [x] Coverage Debian 12, 13
- [x] Coverage Rocky Linux 8, 9, 10
- [x] Coverage AlmaLinux 8, 9, 10
- [x] Coverage Fedora 39-43 (discovery only, downloads disabled)

---

## Phase 2: Source Discovery (Dynamic)
- [x] Has source listing URL in policy
- [x] **DYNAMIC DISCOVERY**: Fetches official listing from upstream
- [x] **DYNAMIC DISCOVERY**: Parses candidates from HTML directory listings
- [x] **DYNAMIC DISCOVERY**: Filters candidates by policy
- [x] **DYNAMIC DISCOVERY**: Selects candidates with strict policy compliance
- [x] Filters out checksum/metadata files (.CHECKSUM, .asc, .sig)
- [x] **DYNAMIC DISCOVERY**: Ubuntu discovery from cloud-images.ubuntu.com
- [x] **DYNAMIC DISCOVERY**: Debian discovery from cloud.debian.org
- [x] **DYNAMIC DISCOVERY**: Rocky Linux discovery from download.rockylinux.org
- [x] **DYNAMIC DISCOVERY**: AlmaLinux discovery from repo.almalinux.org
- [x] **DYNAMIC DISCOVERY**: Fedora discovery from dl.fedoraproject.org

---

## Phase 3: Version guard and checksum planning
- [x] Has selected filename from official listing
- [x] Parses checksum file
- [x] Freezes expected checksum into plan
- [x] Rejects ambiguity
- [x] **min_version guard**: rejects versions below minimum early
- [x] **max_version guard**: rejects versions above maximum (if set)
- [x] **min_version/max_version guard**: works with aliases
- [x] **checksum parser**: supports Ubuntu/Debian format (hash filename)
- [x] **checksum parser**: supports Rocky/AlmaLinux format (SHA256 (filename) = hash)
- [ ] Cross-check version with upstream metadata beyond filename/checksum

---

## Phase 4: Dry-run plan and state persistence
- [x] Creates `plan.json`
- [x] Creates `manifest.json`
- [x] Has `plan_id`
- [x] Persists state to `state/sync/plans/<plan_id>/`
- [x] Dry-run does not download
- [x] **version_selection metadata** in plan (for auto/latest mode)
- [x] **upstream_discovery metadata** in plan
- [x] **policy_filter metadata** in plan
- [x] **artifact_metadata** in plan (disk_format, preference_score)

---

## Phase 5: Cache decision
- [x] Has cache identity from source/version/arch/checksum
- [x] Detects HIT / MISS / INVALID
- [x] Binds cache to checksum/source/version/arch
- [x] Stale cache detection (checksum_changed, source_url_changed, filename_changed)
- [x] STALE state in dry-run and execute

---

## Phase 6: Controlled download
- [x] Blocks download if no dry-run with `--plan-id`
- [x] Downloads from `plan.json` only
- [x] Verifies checksum after download
- [x] Writes run.json
- [x] Writes logs.jsonl
- [x] Download progress MB/s and ETA
- [x] Cleanup `.partial` on fail/cancel
- [x] Retry policy (3 attempts with exponential backoff)
- [x] Timeout handling improvements (URLError, HTTPError, TimeoutError)

---

## Dynamic Discovery Tests

### Ubuntu Discovery
- [x] Discovers versions from cloud-images.ubuntu.com
- [x] Parses release directories (focal, jammy, noble)
- [x] Maps release names to versions correctly
- [x] Creates discovery_log with evidence

### Debian Discovery
- [x] Discovers versions from cloud.debian.org/images/cloud/
- [x] Parses release directories (bookworm, trixie)
- [x] Maps release names to versions correctly
- [x] Creates discovery_log with evidence
- [x] Filters unstable releases when configured

### Rocky Linux Discovery
- [x] Discovers versions from download.rockylinux.org/pub/rocky/
- [x] Parses version directories (8, 9, 10)
- [x] Creates discovery_log with evidence
- [x] Detects version 10 when available upstream

### AlmaLinux Discovery
- [x] Discovers versions from repo.almalinux.org/almalinux/
- [x] Parses version directories (8, 9, 10)
- [x] Creates discovery_log with evidence
- [x] Detects version 10 when available upstream
- [x] Excludes beta/testing directories

### Fedora Discovery
- [x] Discovers versions from dl.fedoraproject.org
- [x] Parses version directories (39-43)
- [x] Creates discovery_log with evidence
- [x] Respects min_discovery_version setting

---

## Artifact Preference Tests

### qcow2 Preference
- [x] Prefers qcow2 when both qcow2 and img available
- [x] Assigns higher preference_score to qcow2
- [x] Records disk_format correctly

### img Support
- [x] Accepts img format when qcow2 not available
- [x] Records disk_format as "raw" for img files
- [x] Assigns appropriate preference_score

### Metadata Tracking
- [x] Records artifact_extension in metadata
- [x] Records source_filename in metadata
- [x] Records artifact_type in metadata
- [x] Records preference_score in metadata
- [x] Records image_variant (cloud/generic) when detected

---

## Test Results (Post-Refactor)

### Config Structure Tests
- [x] Global config loads successfully
- [x] Per-OS configs (ubuntu, debian, rocky, almalinux, fedora) load successfully
- [x] Split config merge works in runtime
- [x] No breaking changes to existing functionality
- [x] Discovery configuration present in all OS configs

### Version Policy Tests
- [x] min_version enforcement works
- [x] max_version enforcement works (when set)
- [x] max_version optional (works when null or omitted)
- [x] selection_policy "explicit" works
- [x] selection_policy "latest" works
- [x] enabled flag respected

### Ubuntu Tests (Explicit Mode)
- [x] ubuntu 20.04 amd64 dry-run
- [x] ubuntu 22.04 amd64 dry-run
- [x] ubuntu 24.04 amd64 dry-run
- [x] ubuntu focal alias dry-run
- [x] ubuntu jammy alias dry-run
- [x] ubuntu noble alias dry-run
- [x] **Discovery**: Detects versions from upstream

### Debian Tests (Explicit Mode)
- [x] debian 12 amd64 dry-run
- [x] debian 13 amd64 dry-run
- [x] debian bookworm alias dry-run
- [x] debian trixie alias dry-run
- [x] **Discovery**: Detects versions from upstream

### Debian Tests (Auto/Latest Mode)
- [x] debian auto amd64 dry-run - selects latest valid version
- [x] debian latest amd64 dry-run - selects latest valid version
- [x] version_selection metadata present in plan
- [x] discovery_log shows valid candidates
- [x] selection_reason explains the choice
- [x] upstream_discovery metadata present

### Rocky Linux Tests
- [x] rocky 8 amd64 dry-run
- [x] rocky 9 amd64 dry-run
- [x] rocky 10 amd64 dry-run
- [x] rocky 7 amd64 rejected (below min_version)
- [x] **Discovery**: Detects versions from upstream
- [x] **Discovery**: Detects version 10 when available

### AlmaLinux Tests
- [x] almalinux 8 amd64 dry-run
- [x] almalinux 9 amd64 dry-run
- [x] almalinux 10 amd64 dry-run
- [x] almalinux 7 amd64 rejected (below min_version)
- [x] **Discovery**: Detects versions from upstream
- [x] **Discovery**: Detects version 10 when available
- [x] **Discovery**: Excludes beta/testing directories

### Fedora Tests (Discovery Only)
- [x] Fedora discovery works via dl.fedoraproject.org
- [x] Detects versions 39-43
- [x] Respects min_discovery_version setting
- [x] **Disabled**: Downloads disabled pending path verification
- [x] **Documentation**: Clear disclaimer in config

### Version Bounds Tests
- [x] **Reject**: ubuntu 18.04 amd64 (below min_version 20.04)
- [x] **Reject**: debian 11 amd64 (below min_version 12)
- [x] **Reject**: rocky 7 amd64 (below min_version 8)
- [x] **Reject**: almalinux 7 amd64 (below min_version 8)
- [x] **Accept**: All supported versions at or above min_version

### Positive Tests (Execute)
- [x] execute with valid plan-id works (cached path tested)
- [x] execute respects plan.json
- [x] execute verifies checksum

### Cache Tests
- [x] cache hit (second run) - status: cached
- [x] cache miss (first run) - status: MISS
- [x] cache stale - checksum_changed detected
- [x] cache stale - source_url_changed detected
- [x] cache stale - auto cleanup and re-download

### Negative Tests
- [x] unsupported os (centos)
- [x] unsupported version (all OS families)
- [x] unsupported arch (ppc64le)
- [x] missing plan-id
- [x] bad plan-id
- [x] candidate ambiguity (resolved via deduplication)

### Checksum Tests
- [x] checksum mismatch detection (fixture test)
- [x] checksum match allows file promotion (fixture test)
- [x] partial file cleanup on mismatch (fixture test)
- [x] Rocky/AlmaLinux SHA256 format parsing

### Error Handling
- [x] user-friendly error messages
- [x] supported OS list on invalid os error
- [x] min_version rejection message is clear
- [x] max_version rejection message is clear (if set)
- [x] hint to run dry-run first on plan not found
- [x] stale cache info messages
- [x] discovery failure messages

### Test Infrastructure
- [x] ambiguity test harness (tools/sync/fixtures/test_ambiguity.py)
- [x] checksum mismatch test harness (tools/sync/fixtures/test_checksum_mismatch.py)

---

## Central Image Menu (New)

### Menu Structure
- [x] Central menu created in neutral path `tools/image/`
- [x] Menu commands: sync, pull, status, setting, clean
- [x] Does NOT replace existing sync backend
- [x] Acts as neutral front-end for current sync subsystem

### image sync Menu
- [x] Interactive OS selection (all, ubuntu, debian, rocky, almalinux, fedora)
- [x] Sync all enabled OS and supported versions
- [x] No real download (dry-run only)
- [x] Shows summary per OS/version: new, unchanged, failed, stale, ready
- [x] Can be called non-interactively: `image sync ubuntu`
- [x] **NEW**: Shows discovery results from upstream

### image pull Menu
- [x] Shows message if no plans available
- [x] Interactive OS selection from existing plans only
- [x] Can select version within OS from existing plans only
- [x] Shows confirmation summary before execution
- [x] Executes plan-driven downloads
- [x] Can be called non-interactively: `image pull ubuntu`

### image status Menu
- [x] Shows table with OS, Version, Status, Cache, Plan ID
- [x] Status values: not planned, planned, ready, stale, failed
- [x] Read-only operation
- [x] Shows totals at bottom
- [x] **NEW**: Shows enabled/disabled status

### image setting Menu
- [x] Main menu: Show Status, Setting OS
- [x] Show Status displays all OS config in table
- [x] Setting OS allows interactive configuration
- [x] Pressing Enter keeps current value
- [x] Config saved to `config/os/<os>.json`
- [x] Configurable: min_version, max_version, selection_policy, default_arch, enabled

### image clean Menu
- [x] Interactive OS selection (all, ubuntu, debian, rocky, almalinux, fedora)
- [x] clean all: requires typing 'YES' for confirmation
- [x] clean <os>: can choose all versions or select version
- [x] Shows what will be removed before confirmation
- [x] Removes plans, cache, and downloaded images for selected scope
- [x] After clean, status reflects removal correctly

### Menu Tests
- [x] Menu existence tests (all 5 menus accessible)
- [x] Sync all creates plans for all OS
- [x] Sync single OS creates plans only for that OS
- [x] Pull with no plans shows safe message
- [x] Pull from plans executes downloads
- [x] Status shows correct information after sync
- [x] Setting shows current config table
- [x] Setting OS change persists
- [x] Enter keeps existing value in settings
- [x] Clean all requires YES confirmation
- [x] Clean OS removes only that OS
- [x] Clean version removes only that version

### Logic Flow Tests
- [x] setting -> sync -> status
- [x] sync -> pull -> status
- [x] sync -> clean -> status
- [x] sync (no new) -> status shows unchanged
- [x] pull without plans -> safe no-selection behavior
- [x] clean selected version -> only that target removed
- [x] **NEW**: discovery -> sync -> status shows new versions

### Integration with Sync Backend
- [x] Menu imports and uses existing sync_image.py functions
- [x] load_config() reused from sync backend
- [x] build_plan() reused for sync command
- [x] execute_from_plan() reused for pull command
- [x] canonical_os/version/arch reused for validation
- [x] **NEW**: discover_upstream_versions() used for dynamic discovery

---

## Files Changed

### New Files (Central Image Menu)
- `tools/image/image_cli.py` - Central CLI entry point with sync, pull, status, setting, clean commands

### New Files (Config)
- `config/os/ubuntu.json` - Ubuntu-specific config with discovery
- `config/os/debian.json` - Debian-specific config with discovery
- `config/os/rocky.json` - Rocky Linux config with discovery (versions 8, 9, 10)
- `config/os/almalinux.json` - AlmaLinux config with discovery (versions 8, 9, 10)
- `config/os/fedora.json` - Fedora config with discovery (disabled by default)

### Modified Files
- `config/sync-config.json` - Simplified to global settings only
- `tools/sync/sync_image.py` - Major enhancements:
  - Dynamic upstream version discovery functions
  - Artifact preference selection
  - Comprehensive metadata tracking
  - Discovery evidence logging
  - Duplicate candidate deduplication
- `docs/current-plan.md` - Updated with dynamic discovery and artifact preference
- `docs/checklist-current-plan.md` - Updated with new test results

---

## Domain Structure Refactor Tests - Strict Migration

### Root Cleaned
- [x] Root no longer contains `config/` (moved to `image/config/`)
- [x] Root no longer contains `state/` (moved to `image/runtime/state/`)
- [x] Root no longer contains `cache/` (moved to `image/runtime/cache/`)
- [x] Root no longer contains `logs/` (moved to `image/runtime/logs/`)
- [x] Root no longer contains `reports/` (moved to `image/runtime/reports/`)
- [x] Repository root is clean and domain-oriented

### Image Domain Structure
- [x] `image/` owns all image-related code
- [x] `image/backend/` created and contains `sync_image.py`
- [x] `image/config/` created and contains all image config
- [x] `image/config/os/` created with all OS configs
- [x] `image/runtime/` created with all runtime subdirectories
- [x] `image/runtime/state/` contains plans
- [x] `image/runtime/cache/` contains downloaded images
- [x] `image/runtime/logs/` contains sync logs
- [x] `image/runtime/reports/` contains generated reports

### Backend Migration
- [x] Backend moved from `tools/sync/sync_image.py` to `image/backend/sync_image.py`
- [x] Backend path references updated to new config/runtime locations
- [x] Config paths updated to `image/config/`
- [x] Runtime paths updated to `image/runtime/`
- [x] Compatibility shim created at `tools/sync/sync_image.py`

### Service Layer Updates
- [x] `image/adapters/sync_backend.py` updated to point to new backend location
- [x] `image/services/setting_service.py` updated to use `image/config/os/`
- [x] `image/services/clean_service.py` updated to use `image/runtime/` defaults
- [x] All services can load config from new location
- [x] All services can access runtime data from new location

### Config Migration
- [x] `config/sync-config.json` moved to `image/config/sync-config.json`
- [x] `config/os/*.json` moved to `image/config/os/*.json`
- [x] Config paths in backend updated
- [x] Config paths in services updated
- [x] Config root references updated to `image/config/`

### Path Tests
- [x] `state_root` in config points to `image/runtime/state`
- [x] `cache_root` in config points to `image/runtime/cache`
- [x] `log_root` in config points to `image/runtime/logs`
- [x] `report_root` in config points to `image/runtime/reports`
- [x] All path resolution works correctly from repo root

### Compatibility
- [x] Compatibility shim at `tools/sync/sync_image.py` works
- [x] Old imports still work via compatibility shim
- [x] Existing plans are accessible from new location
- [x] Config README at root explains migration

### Documentation
- [x] Architecture docs updated with strict structure
- [x] What moved section documented
- [x] New path locations documented
- [x] Compatibility shims documented

---

## Domain Structure Refactor Tests - Previous Round

### New Structure
- [x] `center/` directory created
- [x] `image/` directory created
- [x] `openstack/` directory created
- [x] `guest_config/` directory created
- [x] `image_cli.py` entry point created
- [x] `docs/repo-structure.md` documentation created

### Center Domain
- [x] `center/menu.py` created with main menu
- [x] `center/router.py` created with domain routing
- [x] `center/state.py` created with state management
- [x] Central menu displays Image/OpenStack/Guest Config/Exit options

### Image Domain
- [x] `image/menu.py` created with image commands
- [x] `image/services/sync_service.py` created
- [x] `image/services/pull_service.py` created
- [x] `image/services/status_service.py` created
- [x] `image/services/setting_service.py` created
- [x] `image/services/clean_service.py` created
- [x] `image/adapters/sync_backend.py` created as bridge

### Placeholder Domains
- [x] `openstack/menu.py` created (placeholder)
- [x] `openstack/README.md` created
- [x] `guest_config/menu.py` created (placeholder)
- [x] `guest_config/README.md` created

### Routing Tests
- [x] Central menu starts without errors
- [x] Routing to Image domain works
- [x] Routing to OpenStack placeholder works
- [x] Routing to Guest Config placeholder works
- [x] Return to central menu works from all domains

### Integration Tests
- [x] Backend bridge loads existing sync backend
- [x] Backend bridge functions work correctly
- [x] Image domain services can load config
- [x] Image domain services can access plans

### Documentation Tests
- [x] `docs/current-plan.md` updated with new structure
- [x] `docs/checklist-current-plan.md` updated
- [x] `docs/repo-structure.md` created
- [x] `doc/` directory created and synced

---

## Known Limitations & Future Work

### Fedora Status
- **Discovery**: Working correctly via dl.fedoraproject.org
- **Download paths**: Require verification before enabling
- **Current status**: Disabled by default with clear documentation
- **Workaround**: Enable after validating image URLs and checksum locations
- **Evidence**: Discovery metadata shows versions 39-43 correctly detected

### Auto/Latest Mode
- **Debian**: Fully supported
- **Fedora**: Supported in config (when enabled)
- **Ubuntu**: Explicit mode only (intentional for LTS stability)
- **Rocky/AlmaLinux**: Explicit mode only (intentional for enterprise stability)
- **Future**: Can be extended to other OS families if desired

### Remaining Gaps
- Cross-check with extra upstream metadata beyond directory listings
- Full integration tests with complete downloads (Smoke Pass sufficient for most cases)
- Fedora enablement (requires path verification)
- GUI/web interface for easier management
- Automated periodic sync scheduling

---

## Summary

### What Works
- Dynamic upstream version discovery for all OS families
- Policy-driven version filtering (min/max bounds)
- Artifact preference (qcow2 > img > others)
- Comprehensive metadata tracking
- Full discovery evidence logging
- Ubuntu 20.04/22.04/24.04 with upstream detection
- Debian 12/13 with explicit + auto/latest modes
- Rocky Linux 8/9/10 with upstream detection
- AlmaLinux 8/9/10 with upstream detection (stable only)
- Fedora discovery working (downloads disabled pending verification)

### What's New
- **Dynamic Discovery**: Automatically detects new versions from upstream
- **Artifact Preference**: Intelligently selects best format
- **Metadata Tracking**: Records disk_format, artifact_type, preference_score
- **Evidence Logging**: Full audit trail of discovery and selection
- **Version 10 Support**: Rocky and AlmaLinux now include version 10
- **Fedora Foundation**: Discovery implemented, ready for enablement
