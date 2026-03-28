# Sync Checklist (Phase 0–6)

สถานะที่ใช้:
- `[ ]` ยังไม่ผ่าน / ยังไม่ทำ
- `[x]` ผ่าน
- `[~]` มีบางส่วนแล้ว
- `[-]` ไม่เกี่ยวข้องกับรอบนี้

---

## Config Structure (Refactored)
- [x] `config/sync-config.json` contains only global/shared settings
- [x] `config/os/ubuntu.json` created with min_version, aliases, architectures, sources
- [x] `config/os/debian.json` created with min_version, aliases, architectures, sources
- [x] `config/os/rocky.json` created with min_version, architectures, sources
- [x] `config/os/almalinux.json` created with min_version, architectures, sources
- [x] Loader reads and merges split configs correctly
- [x] Backward compatibility preserved for CLI interface

---

## Phase 0: Input intake and normalization
- [x] มี input หลัก os / version / arch
- [x] normalize os ได้
- [x] normalize version alias ได้
- [x] normalize architecture ได้
- [x] validate input edge cases (unsupported os/version/arch)
- [x] reject invalid combinations ครบทุกกรณี

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
- [x] **min_version guard**: works with aliases
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

### Ubuntu Tests (Dry-run)
- [x] ubuntu 20.04 amd64 dry-run
- [x] ubuntu 22.04 amd64 dry-run
- [x] ubuntu 24.04 amd64 dry-run
- [x] ubuntu focal alias dry-run
- [x] ubuntu jammy alias dry-run
- [x] ubuntu noble alias dry-run

### Debian Tests (Dry-run)
- [x] debian 12 amd64 dry-run
- [x] debian 13 amd64 dry-run
- [x] debian bookworm alias dry-run
- [x] debian trixie alias dry-run

### Rocky Linux Tests
- [x] rocky 8 amd64 dry-run
- [x] rocky 9 amd64 dry-run
- [x] rocky 7 amd64 rejected (below min_version)
- [~] rocky execute smoke-pass (started, timeout expected for large download)

### AlmaLinux Tests
- [x] almalinux 8 amd64 dry-run
- [x] almalinux 9 amd64 dry-run
- [x] almalinux 7 amd64 rejected (below min_version)
- [~] almalinux execute smoke-pass (not tested, similar to Rocky)

### min_version Guard Tests
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
- [x] hint to run dry-run first on plan not found
- [x] stale cache info messages

### Test Infrastructure
- [x] ambiguity test harness (tools/sync/fixtures/test_ambiguity.py)
- [x] checksum mismatch test harness (tools/sync/fixtures/test_checksum_mismatch.py)

---

## Files Changed (Refactor + New OS Support)

### New Files
- `config/os/ubuntu.json` - Ubuntu-specific config with min_version
- `config/os/debian.json` - Debian-specific config with min_version
- `config/os/rocky.json` - Rocky Linux config with min_version
- `config/os/almalinux.json` - AlmaLinux config with min_version

### Modified Files
- `config/sync-config.json` - Simplified to global settings only
- `tools/sync/sync_image.py` - Updated loader, enhanced checksum parser, improved candidate selection
- `docs/current-plan.md` - Updated to reflect new config structure and OS coverage
- `docs/checklist-current-plan.md` - Updated with new tests and structure

---

## Known Limitations & Future Work
- **Fedora**: Official download site has Anubis bot protection preventing automated access
  - Workaround: Use alternative mirrors or manual download
  - Status: Config structure prepared but not enabled due to bot protection
- cross-check with extra upstream metadata
- full integration tests with complete downloads (Smoke Pass sufficient for most cases)
- stale cache detection for additional metadata changes (if needed)
