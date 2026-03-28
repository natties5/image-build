
## `docs/checklist-current-plan.md`
```md id="85736"
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
- [ ] validate input edge cases ครบ
- [ ] reject invalid combinations ครบทุกกรณี

## Phase 1: Policy loading and source mapping
- [x] โหลด `config/sync-config.json` ได้
- [x] map OS/version ไป source policy ได้
- [x] map alias ไป canonical version ได้
- [ ] coverage ของ OS/source ยังไม่ครบ
- [ ] host allowlist ยังไม่ได้ enforce ตอน request จริง

## Phase 2: Source discovery
- [~] มี source listing URL ใน policy แล้ว
- [ ] fetch official listing จริง
- [ ] parse candidate จริง
- [ ] filter candidate จริง
- [ ] select candidate แบบ strict จริง

## Phase 3: Version guard and checksum planning
- [~] มี selected filename candidate จาก policy
- [ ] parse checksum file จริง
- [ ] cross-check version กับ metadata จริง
- [ ] reject ambiguity จริง
- [ ] freeze checksum ลง plan จริง

## Phase 4: Dry-run plan and state persistence
- [x] สร้าง `plan.json` ได้
- [x] สร้าง `manifest.json` ได้
- [x] มี `plan_id`
- [x] persist state ลง `state/sync/plans/<plan_id>/`
- [x] dry-run ยังไม่ download จริง

## Phase 5: Cache decision
- [ ] มี cache identity จริง
- [ ] detect HIT / MISS / INVALID / STALE
- [ ] bind cache กับ checksum/source/version/arch

## Phase 6: Controlled download
- [ ] block download ถ้ายังไม่มี dry-run
- [ ] download จาก `plan.json` เท่านั้น
- [ ] verify checksum หลังโหลด
- [ ] write run.json
- [ ] write logs.jsonl