# Sync Checklist (Phase 0–6)

สถานะที่ใช้:
- `[ ]` ยังไม่ผ่าน / ยังไม่ทำ
- `[x]` ผ่าน
- `[~]` มีบางส่วนแล้ว
- `[-]` ไม่เกี่ยวข้องกับรอบนี้

---

## Config Structure (Refactored)
- [x] `config/sync-config.json` contains only global/shared settings
- [x] `config/os/ubuntu.json` created with min_version, max_version (optional), selection_policy, aliases, architectures, sources
- [x] `config/os/debian.json` created with min_version, max_version (optional), selection_policy, aliases, architectures, sources
- [x] `config/os/rocky.json` created with min_version, architectures, sources
- [x] `config/os/almalinux.json` created with min_version, architectures, sources
- [x] Loader reads and merges split configs correctly
- [x] Backward compatibility preserved for CLI interface

---

## Version Policy Model
- [x] **min_version**: Required field, enforced in validation
- [x] **max_version**: Optional field (null or omitted), enforced only if present
- [x] **selection_policy**: Support "explicit" and "latest" modes
- [x] **release_channel**: Documented field for release classification
- [x] Version bounds checking with proper error messages

---

## Phase 0: Input intake and normalization
- [x] มี input หลัก os / version / arch
- [x] normalize os ได้
- [x] normalize version alias ได้
- [x] normalize architecture ได้
- [x] validate input edge cases (unsupported os/version/arch)
- [x] reject invalid combinations ครบทุกกรณี
- [x] support "auto" and "latest" as version selectors (Debian)

---

## Phase 1: Policy loading and source mapping
- [x] โหลด `config/sync-config.json` ได้ (global settings)
- [x] โหลด `config/os/*.json` ได้ (per-OS settings)
- [x] merge configs เข้า runtime structure ได้
- [x] map OS/version ไป source policy ได้
- [x] map alias ไป canonical version ได้
- [x] มี host allowlist
- [x] coverage Ubuntu 20.04, 22.04, 24.04
- [x] coverage Debian 12, 13
- [x] coverage Rocky Linux 8, 9
- [x] coverage AlmaLinux 8, 9

---

## Phase 2: Source discovery
- [x] มี source listing URL ใน policy
- [x] fetch official listing จริง
- [x] parse candidate จริง
- [x] filter candidate จริง
- [x] select candidate แบบ strict จริง
- [x] filter out checksum/metadata files (.CHECKSUM, .asc, .sig)

---

## Phase 3: Version guard and checksum planning
- [x] มี selected filename จาก official listing
- [x] parse checksum file จริง
- [x] freeze expected checksum ลง plan
- [x] reject ambiguity จริง
- [x] **min_version guard**: reject versions below minimum early
- [x] **max_version guard**: reject versions above maximum (if set)
- [x] **min_version/max_version guard**: works with aliases
- [x] **checksum parser**: support Ubuntu/Debian format (hash filename)
- [x] **checksum parser**: support Rocky/AlmaLinux format (SHA256 (filename) = hash)
- [ ] cross-check version กับ upstream metadata อื่นนอกจาก filename/checksum

---

## Phase 4: Dry-run plan and state persistence
- [x] สร้าง `plan.json` ได้
- [x] สร้าง `manifest.json` ได้
- [x] มี `plan_id`
- [x] persist state ลง `state/sync/plans/<plan_id>/`
- [x] dry-run ยังไม่ download จริง
- [x] **version_selection metadata** in plan (for auto/latest mode)

---

## Phase 5: Cache decision
- [x] มี cache identity จาก source/version/arch/checksum
- [x] detect HIT / MISS / INVALID แบบเบื้องต้น
- [x] bind cache กับ checksum/source/version/arch
- [x] stale cache detection (checksum_changed, source_url_changed, filename_changed)
- [x] STALE state in dry-run and execute

---

## Phase 6: Controlled download
- [x] block download ถ้ายังไม่มี dry-run ด้วย `--plan-id`
- [x] download จาก `plan.json` เท่านั้น
- [x] verify checksum หลังโหลด
- [x] write run.json
- [x] write logs.jsonl
- [x] download progress MB/s และ ETA
- [x] cleanup `.partial` เมื่อ fail/cancel
- [x] retry policy (3 attempts with exponential backoff)
- [x] timeout handling improvements (URLError, HTTPError, TimeoutError)

---

## Test Results (Post-Refactor)

### Config Structure Tests
- [x] Global config loads successfully
- [x] Per-OS configs (ubuntu, debian, rocky, almalinux) load successfully
- [x] Split config merge works in runtime
- [x] No breaking changes to existing functionality

### Version Policy Tests
- [x] min_version enforcement works
- [x] max_version enforcement works (when set)
- [x] max_version optional (works when null or omitted)
- [x] selection_policy "explicit" works
- [x] selection_policy "latest" works

### Ubuntu Tests (Explicit Mode)
- [x] ubuntu 20.04 amd64 dry-run
- [x] ubuntu 22.04 amd64 dry-run
- [x] ubuntu 24.04 amd64 dry-run
- [x] ubuntu focal alias dry-run
- [x] ubuntu jammy alias dry-run
- [x] ubuntu noble alias dry-run

### Debian Tests (Explicit Mode)
- [x] debian 12 amd64 dry-run
- [x] debian 13 amd64 dry-run
- [x] debian bookworm alias dry-run
- [x] debian trixie alias dry-run

### Debian Tests (Auto/Latest Mode)
- [x] debian auto amd64 dry-run - selects latest valid version
- [x] debian latest amd64 dry-run - selects latest valid version
- [x] version_selection metadata present in plan
- [x] discovery_log shows valid candidates
- [x] selection_reason explains the choice

### Rocky Linux Tests
- [x] rocky 8 amd64 dry-run
- [x] rocky 9 amd64 dry-run
- [x] rocky 7 amd64 rejected (below min_version)

### AlmaLinux Tests
- [x] almalinux 8 amd64 dry-run
- [x] almalinux 9 amd64 dry-run
- [x] almalinux 7 amd64 rejected (below min_version)

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
- [x] candidate ambiguity (3/3 unit tests passed)

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
- [x] Interactive OS selection (all, ubuntu, debian, rocky, almalinux)
- [x] Sync all enabled OS and supported versions
- [x] No real download (dry-run only)
- [x] Shows summary per OS/version: new, unchanged, failed, stale, ready
- [x] Can be called non-interactively: `image sync ubuntu`

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

### image setting Menu
- [x] Main menu: Show Status, Setting OS
- [x] Show Status displays all OS config in table
- [x] Setting OS allows interactive configuration
- [x] Pressing Enter keeps current value
- [x] Config saved to `config/os/<os>.json`
- [x] Configurable: min_version, max_version, selection_policy, default_arch, enabled

### image clean Menu
- [x] Interactive OS selection (all, ubuntu, debian, rocky, almalinux)
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

### Integration with Sync Backend
- [x] Menu imports and uses existing sync_image.py functions
- [x] load_config() reused from sync backend
- [x] build_plan() reused for sync command
- [x] execute_from_plan() reused for pull command
- [x] canonical_os/version/arch reused for validation

---

## Files Changed

### New Files (Central Image Menu)
- `tools/image/image_cli.py` - Central CLI entry point with sync, pull, status, setting, clean commands
- `image` - Shell wrapper script for convenient execution

### New Files (Config)
- `config/os/ubuntu.json` - Ubuntu-specific config
- `config/os/debian.json` - Debian-specific config
- `config/os/rocky.json` - Rocky Linux config
- `config/os/almalinux.json` - AlmaLinux config

### Modified Files
- `config/sync-config.json` - Simplified to global settings only
- `tools/sync/sync_image.py` - Major updates:
  - Optional max_version support
  - selection_policy support
  - Debian auto/latest discovery
  - Version selection metadata
  - Enhanced checksum parser
  - Improved candidate selection
- `docs/current-plan.md` - Updated with central image menu documentation
- `docs/checklist-current-plan.md` - Updated with test results and menu tests

---

## Known Limitations & Future Work
- **Fedora**: Official download site has Anubis bot protection preventing automated access
  - Workaround: Use alternative mirrors or manual download
  - Status: Config structure prepared but not enabled due to bot protection
- **Auto/Latest Mode**: Currently only implemented for Debian
  - Ubuntu, Rocky, AlmaLinux remain explicit-only
  - Can be extended in future rounds
- cross-check with extra upstream metadata
- full integration tests with complete downlo
