# Sync Checklist (Phase 0–6)

สถานะที่ใช้:
- `[ ]` ยังไม่ผ่าน / ยังไม่ทำ
- `[x]` ผ่าน
- `[~]` มีบางส่วนแล้ว
- `[-]` ไม่เกี่ยวข้องกับรอบนี้

---

## Phase 0: Input intake and normalization
- [x] มี input หลัก os / version / arch
- [x] normalize os ได้
- [x] normalize version alias ได้
- [x] normalize architecture ได้
- [x] validate input edge cases (unsupported os/version/arch)
- [x] reject invalid combinations ครบทุกกรณี

## Phase 1: Policy loading and source mapping
- [x] โหลด `config/sync-config.json` ได้
- [x] map OS/version ไป source policy ได้
- [x] map alias ไป canonical version ได้
- [x] มี host allowlist
- [x] coverage Ubuntu 20.04, 22.04, 24.04
- [x] coverage Debian 12
- [x] coverage Debian 13

## Phase 2: Source discovery
- [x] มี source listing URL ใน policy
- [x] fetch official listing จริง
- [x] parse candidate จริง
- [x] filter candidate จริง
- [x] select candidate แบบ strict จริง

## Phase 3: Version guard and checksum planning
- [x] มี selected filename จาก official listing
- [x] parse checksum file จริง
- [x] freeze expected checksum ลง plan
- [x] reject ambiguity จริง
- [ ] cross-check version กับ upstream metadata อื่นนอกจาก filename/checksum

## Phase 4: Dry-run plan and state persistence
- [x] สร้าง `plan.json` ได้
- [x] สร้าง `manifest.json` ได้
- [x] มี `plan_id`
- [x] persist state ลง `state/sync/plans/<plan_id>/`
- [x] dry-run ยังไม่ download จริง

## Phase 5: Cache decision
- [x] มี cache identity จาก source/version/arch/checksum
- [x] detect HIT / MISS / INVALID แบบเบื้องต้น
- [x] bind cache กับ checksum/source/version/arch
- [x] stale cache detection (checksum_changed, source_url_changed, filename_changed)
- [x] STALE state in dry-run and execute

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

## Test Results

### Positive Tests (Execute - Smoke Pass)
- [x] debian 12 amd64 execute (verified download starts)
- [x] debian 13 amd64 execute (verified download starts, reached 6%)
- [x] ubuntu 20.04 amd64 execute (verified download starts)
- [x] ubuntu 24.04 amd64 execute (verified download starts)

### Positive Tests (Dry-run)
- [x] ubuntu 20.04 amd64 dry-run
- [x] ubuntu 22.04 amd64 dry-run
- [x] ubuntu 24.04 amd64 dry-run
- [x] ubuntu jammy alias dry-run
- [x] ubuntu focal alias dry-run
- [x] ubuntu noble alias dry-run
- [x] debian 12 amd64 dry-run
- [x] debian 13 amd64 dry-run
- [x] debian bookworm alias dry-run
- [x] debian trixie alias dry-run

### Cache Tests
- [x] cache hit (second run) - status: cached
- [x] cache miss (first run) - status: MISS
- [x] cache stale - checksum_changed detected
- [x] cache stale - source_url_changed detected
- [x] cache stale - auto cleanup and re-download

### Negative Tests
- [x] unsupported os (centos)
- [x] unsupported version (ubuntu 18.04)
- [x] unsupported arch (ppc64le)
- [x] missing plan-id
- [x] bad plan-id
- [x] candidate ambiguity (3/3 unit tests passed)

### Checksum Tests
- [x] checksum mismatch detection (fixture test)
- [x] checksum match allows file promotion (fixture test)
- [x] partial file cleanup on mismatch (fixture test)

### Error Handling
- [x] user-friendly error messages
- [x] supported OS list on invalid os error
- [x] hint to run dry-run first on plan not found
- [x] stale cache info messages

### Test Infrastructure
- [x] ambiguity test harness (tools/sync/fixtures/test_ambiguity.py)
- [x] checksum mismatch test harness (tools/sync/fixtures/test_checksum_mismatch.py)

---

## Remaining Gaps
- cross-check with extra upstream metadata
- full integration test with complete downloads (optional, Smoke Pass sufficient)
- stale cache detection for additional metadata changes (if needed)
