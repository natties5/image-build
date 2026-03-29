# Sync Image Plan (Phase 0–6 Only)

## Scope
ระบบนี้โฟกัสเฉพาะ phase 0–6 ของงาน sync image:

- Phase 0: input intake and normalization
- Phase 1: policy loading and source mapping
- Phase 2: source discovery from official listing
- Phase 3: version guard and checksum planning
- Phase 4: dry-run plan and state persistence
- Phase 5: cache decision
- Phase 6: controlled download from plan.json

ยังไม่รวม build, guest access, OpenStack upload และ post-upload validation

---

## Goal
เป้าหมายของ baseline นี้คือทำให้ sync image เป็น phase ต้นน้ำที่เสถียรที่สุด เพราะถ้า phase นี้ผิด ระบบทั้งชุดจะพังต่อทั้งหมด

สิ่งที่ต้องได้:
- resolve input เป็น canonical form
- map OS/version ไป official source อย่างชัดเจน
- fetch official listing จริง
- เลือก candidate แบบ strict
- parse checksum จริง
- สร้าง dry-run plan.json ที่ใช้ execute ต่อได้
- execute ต้องใช้ plan.json เท่านั้น
- cache ต้องผูกกับ source/version/arch/checksum
- download มี progress MB/s และ ETA
- cleanup partial files อัตโนมัติเมื่อ fail/cancel

---

## Core rules
- ห้าม download จริงก่อนมี dry-run plan
- ห้าม execute จริงโดย resolve source ใหม่เอง
- ห้ามใช้ version ที่ไม่ผ่าน canonical + policy + min_version guard
- ห้าม reuse cache ข้าม source/version/arch/checksum แบบไม่มี identity guard
- host ต้องอยู่ใน allowlist

---

## Configuration Structure

Config ถูกแบ่งเป็น 2 ระดับ:

### Global Config (`config/sync-config.json`)
เก็บ global/shared settings:
- version
- state_root, cache_root, log_root, report_root
- request_timeout_seconds
- allowed_hosts
- user_agent

### Per-OS Config (`config/os/*.json`)
แยกตาม OS แต่ละตัว:
- ubuntu.json - Ubuntu LTS releases
- debian.json - Debian releases  
- rocky.json - Rocky Linux releases
- almalinux.json - AlmaLinux releases

Each file contains:
- os: ชื่อ OS
- min_version: minimum supported version (required)
- max_version: maximum supported version (optional, can be null or omitted)
- selection_policy: version selection policy ("explicit" or "latest")
- release_channel: release channel (e.g., "stable", "lts", "rolling")
- aliases: version aliases
- architectures: arch mappings
- sources: version-specific listing/checksum settings

### Version Selection Policies

**explicit**: User must specify exact version (e.g., "debian 12", "ubuntu 22.04")

**latest**: Supports automatic version discovery
- Use `auto` or `latest` as version selector
- System discovers available versions from config
- Filters by min_version and max_version (if set)
- Selects the latest valid version
- Currently supported for: Debian

---

## Loader Behavior
1. อ่าน global config จาก `config/sync-config.json`
2. อ่านทุก per-OS config จาก `config/os/*.json`
3. Merge เข้าเป็น runtime config structure เดียว
4. ใช้สำหรับ validation, discovery, execution

---

## Current flow
input
-> normalize (canonical_os, canonical_version, canonical_arch)
-> validate (min_version/max_version guard, selection_policy)
-> [if auto/latest mode] discover versions and select latest valid
-> policy lookup
-> official listing fetch
-> strict candidate selection
-> checksum fetch
-> dry-run plan (with version_selection metadata)
-> cache decision
-> execute from plan.json only
-> verify checksum

---

## Run examples

### Explicit Mode (all OS)
```bash
# Ubuntu
py tools\sync\sync_image.py ubuntu 22.04 amd64
py tools\sync\sync_image.py ubuntu jammy amd64
py tools\sync\sync_image.py ubuntu 20.04 amd64
py tools\sync\sync_image.py ubuntu 24.04 amd64

# Debian (explicit)
py tools\sync\sync_image.py debian 12 amd64
py tools\sync\sync_image.py debian 13 amd64
py tools\sync\sync_image.py debian bookworm amd64
py tools\sync\sync_image.py debian trixie amd64

# Rocky Linux
py tools\sync\sync_image.py rocky 8 amd64
py tools\sync\sync_image.py rocky 9 amd64

# AlmaLinux
py tools\sync\sync_image.py almalinux 8 amd64
py tools\sync\sync_image.py almalinux 9 amd64
```

### Auto/Latest Mode (Debian only)
```bash
# Auto-discover and select latest valid Debian version
py tools\sync\sync_image.py debian auto amd64
py tools\sync\sync_image.py debian latest amd64
```

Execute:
```bash
py tools\sync\sync_image.py --execute --plan-id <plan_id>
```

ผลลัพธ์:
- สร้าง `state/sync/plans/<plan_id>/plan.json`
- สร้าง `state/sync/plans/<plan_id>/manifest.json`
- สร้าง `state/sync/plans/<plan_id>/logs.jsonl`
- สร้าง `logs/sync/sync.log.jsonl`
- เมื่อ execute สำเร็จจะมี `run.json` และไฟล์ใน `cache/official/...`

### Version Selection Evidence
When using auto/latest mode, the plan includes version_selection metadata:
```json
{
  "version_selection": {
    "requested_version": "latest",
    "selection_mode": "latest",
    "discovery_log": [
      {"version": "12", "release_name": "bookworm", "status": "valid"},
      {"version": "13", "release_name": "trixie", "status": "valid"}
    ],
    "selection_reason": "latest valid version >= 12"
  }
}
```

---

## Current status

รอบนี้ phase ที่พร้อมใช้งานแล้วคือ:
- phase 0 input normalization (รองรับ alias, reject invalid inputs)
- phase 1 policy loading (split config: global + per-OS, optional max_version, selection_policy)
- phase 2 official listing discovery
- phase 3 checksum planning + strict candidate guard + min_version/max_version guard
- phase 4 dry-run state persistence (with version_selection metadata)
- phase 5 cache HIT/MISS/INVALID/STALE + stale cache detection
- phase 6 controlled download พร้อม progress MB/s + ETA + partial cleanup + retry policy

### Improvements Added
- Download progress แสดง MB/s และ ETA
- Automatic cleanup ของ `.partial` files เมื่อ fail หรือถูก interrupt
- Signal handling สำหรับ Ctrl+C interrupt
- Error messages ที่ user-friendly พร้อม hints
- รองรับ Ubuntu 20.04 (focal) เพิ่ม
- รองรับ Debian 13 (trixie) เพิ่ม
- รองรับ Rocky Linux 8 และ 9
- รองรับ AlmaLinux 8 และ 9
- Stale cache detection (checksum, source_url, filename changes)
- Cache states: HIT, MISS, INVALID, STALE
- Retry policy สำหรับ failed downloads (3 attempts with exponential backoff)
- Timeout handling improvements (URLError, HTTPError, TimeoutError)
- Checksum mismatch test fixture
- **Config split: global + per-OS files**
- **min_version guard for version validation (required)**
- **max_version guard (optional)**
- **selection_policy support (explicit/latest)**
- **Debian auto/latest version discovery**
- **Enhanced checksum parser** (รองรับทั้ง Ubuntu/Debian และ Rocky/AlmaLinux formats)
- **Version selection evidence in plan/manifest**

### OS Coverage
- Ubuntu 20.04 LTS (focal) - min_version: 20.04, policy: explicit
- Ubuntu 22.04 LTS (jammy) - min_version: 20.04, policy: explicit
- Ubuntu 24.04 LTS (noble) - min_version: 20.04, policy: explicit
- Debian 12 (bookworm) - min_version: 12, policy: latest, supports auto/latest
- Debian 13 (trixie) - min_version: 12, policy: latest, supports auto/latest
- Rocky Linux 8 - min_version: 8
- Rocky Linux 9 - min_version: 8
- AlmaLinux 8 - min_version: 8
- AlmaLinux 9 - min_version: 8

### Known Limitations
- **Fedora**: Official download site (download.fedoraproject.org) มี Anubis bot protection ทำให้ไม่สามารถใช้งานกับระบบ automation ได้โดยตรง ต้องใช้ mirror อื่นหรือรอการแก้ไขเพิ่มเติม
- **Auto/latest mode**: Currently only supported for Debian. Ubuntu remains explicit-only.

### Architecture Support
- amd64 (x86_64)
- arm64 (aarch64)

### Error Handling
- Unsupported OS: แสดงรายการ OS ที่รองรับ
- Unsupported version: clear error message
- Below min_version: early rejection with clear message
- Above max_version (if set): early rejection with clear message
- Missing plan-id: usage hint
- Bad plan-id: suggestion to run dry-run first

### Remaining Gaps
- cross-check กับ upstream metadata เพิ่มเติม
- full integration tests with complete downloads (Smoke Pass sufficient for most cases)
- Fedora support (requires mirror or bot protection bypass)
- Extend auto/latest mode to other OS families (Ubuntu, Rocky, AlmaLinux)
