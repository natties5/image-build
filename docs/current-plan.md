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

---

## Core rules
- ห้าม download จริงก่อนมี dry-run plan
- ห้าม execute จริงโดย resolve source ใหม่เอง
- ห้ามใช้ version ที่ไม่ผ่าน canonical + policy
- ห้าม reuse cache ข้าม source/version/arch/checksum แบบไม่มี identity guard
- host ต้องอยู่ใน allowlist

---

## Current flow
input
-> normalize
-> validate
-> policy lookup
-> official listing fetch
-> strict candidate selection
-> checksum fetch
-> dry-run plan
-> cache decision
-> execute from plan.json only

---

## Run examples

Dry-run:
```bash
py tools\sync\sync_image.py ubuntu 22.04 amd64
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

---

## Current status
รอบนี้ phase ที่พร้อมใช้งานแล้วคือ:
- phase 0 input normalization
- phase 1 policy loading
- phase 2 official listing discovery
- phase 3 checksum planning + strict candidate guard
- phase 4 dry-run state persistence
- phase 5 cache HIT/MISS/INVALID แบบเบื้องต้น
- phase 6 controlled download จาก plan.json
