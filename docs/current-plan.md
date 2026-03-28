# Sync Image Plan (Phase 0–6 Only)

## Scope
ระบบนี้โฟกัสเฉพาะ phase 0–6 ของงาน sync image:

- Phase 0: input intake and normalization
- Phase 1: policy loading and source mapping
- Phase 2: source discovery
- Phase 3: version guard and checksum planning
- Phase 4: dry-run plan and state persistence
- Phase 5: cache decision
- Phase 6: controlled download

ยังไม่รวม build, guest access, OpenStack upload และ post-upload validation

---

## Goal
เป้าหมายของ baseline นี้คือทำให้ sync image เป็น phase ต้นน้ำที่เสถียรที่สุด เพราะถ้า phase นี้ผิด ระบบทั้งชุดจะพังต่อทั้งหมด

สิ่งที่ต้องได้จาก baseline นี้:
- resolve input เป็น canonical form
- map OS/version ไป official source อย่างชัดเจน
- ห้ามเดา version แบบคลุมเครือ
- dry-run ต้องสร้าง plan.json ได้
- execution ภายหลังต้องอิง plan.json เท่านั้น
- cache และ download จะถูกต่อยอดบน state นี้

---

## Core rules
- ห้าม download จริงก่อนมี dry-run plan
- ห้าม execute จริงโดย resolve source ใหม่เอง
- ห้ามใช้ version ที่ไม่ผ่าน canonical + policy
- ห้าม reuse cache ข้าม source/version/arch แบบไม่มี identity guard

---

## Current flow
input
-> normalize
-> validate
-> policy lookup
-> source mapping
-> dry-run plan
-> persist state

ใน baseline ชุดนี้ phase 2–6 ยังเป็นโครงที่เตรียมให้ต่อยอด โดย phase 0–4 ใช้งานได้แล้วในระดับ dry-run planner

---

## Files in this baseline
- `config/sync-config.json`
- `tools/sync/sync_image.sh`
- `tools/sync/sync_image.py`
- `tools/sync/checklist_patch.py`
- `docs/current-plan.md`
- `docs/checklist-current-plan.md`

---

## Run example
```bash
bash tools/sync/sync_image.sh ubuntu 22.04 amd64