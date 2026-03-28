# Checklist — Sync Image System (Phase 0–6 + Coverage)

สถานะที่ใช้:
- `[ ]` ยังไม่ผ่าน / ยังไม่ทำ
- `[x]` ผ่าน
- `[~]` มีบางส่วนแล้ว
- `[-]` ไม่เกี่ยวข้องกับรอบนี้

---

## A. Repository and baseline

- [x] มี branch สำหรับ sync-only baseline
- [x] มี `.gitignore` สำหรับกัน cache/log/runtime/image/local files
- [x] มีโครงสร้าง `config/`, `tools/sync/`, `state/`, `cache/`, `logs/`, `reports/`, `docs/`
- [x] มี `sync-config.json`
- [x] มี `sync_image.py`
- [x] มี `current-plan.md`
- [x] มี `checklist-current-plan.md`

---

## B. Phase 0 — Input intake and normalization

### B.1 Input shape
- [x] รองรับ input `os`
- [x] รองรับ input `version`
- [x] รองรับ input `arch`

### B.2 Normalization
- [x] normalize os เป็น lowercase/canonical ได้
- [x] normalize version alias ได้
- [x] normalize architecture ได้
- [ ] normalize image type ได้เมื่อจำเป็นในอนาคต

### B.3 Validation
- [x] reject unsupported os ได้
- [x] reject unsupported version ได้
- [x] reject unsupported arch ได้
- [ ] validate empty/blank input ให้ครบ
- [ ] validate malformed input ให้ครบ
- [ ] validate invalid os-version combinations ให้ครบ

---

## C. Phase 1 — Policy loading and source mapping

### C.1 Config loading
- [x] โหลด `config/sync-config.json` ได้
- [x] อ่าน alias map ได้
- [x] อ่าน architecture map ได้
- [x] อ่าน source policy ได้
- [x] อ่าน checksum policy ได้

### C.2 Mapping correctness
- [x] map Ubuntu target ได้
- [x] map Debian target ได้
- [ ] map coverage ของ Ubuntu ให้ครบตามเป้า
- [ ] map coverage ของ Debian ให้ครบตามเป้า
- [ ] map Fedora ได้
- [ ] map Rocky ได้
- [ ] map AlmaLinux ได้

### C.3 Security guard
- [x] มี allowed_hosts
- [x] enforce host allowlist ตอน request จริง
- [ ] log denied host ให้ชัดเจนขึ้น

---

## D. Phase 2 — Official source discovery

### D.1 Listing fetch
- [x] fetch official listing ได้จริง
- [x] ใช้ listing URL จาก policy
- [x] fail เมื่อ host ไม่อยู่ allowlist

### D.2 Candidate parsing
- [x] parse links/candidates จาก listing ได้
- [x] filter ตาม filename pattern ได้
- [x] filter ตาม arch ได้
- [x] ตัดสิน candidate ได้แบบ strict

### D.3 Ambiguity handling
- [x] reject เมื่อ candidate มากกว่า 1
- [x] reject เมื่อ candidate = 0
- [ ] เก็บเหตุผลการเลือก candidate ลง manifest/log ให้ละเอียดขึ้น

---

## E. Phase 3 — Version guard and checksum planning

### E.1 Checksum
- [x] fetch checksum file จริง
- [x] parse checksum ได้จริง
- [x] ผูก checksum กับ selected filename ได้
- [x] freeze expected checksum ลง plan ได้

### E.2 Version guard
- [x] selected filename มาจาก official listing จริง
- [x] reject ambiguity ได้
- [ ] cross-check version กับ upstream metadata เพิ่ม
- [ ] เก็บ evidence ของ version resolution ให้ละเอียดขึ้น

### E.3 Guard quality
- [ ] แยก error ระหว่าง source-not-found / checksum-not-found / ambiguity ให้ชัดขึ้น
- [ ] มี error code หรือ status classification

---

## F. Phase 4 — Dry-run plan and state persistence

### F.1 Plan creation
- [x] สร้าง `plan.json` ได้
- [x] สร้าง `manifest.json` ได้
- [x] สร้าง `logs.jsonl` ได้
- [x] มี `plan_id`
- [x] มี `download_url`
- [x] มี `expected_checksum`

### F.2 State persistence
- [x] persist ลง `state/sync/plans/<plan_id>/`
- [x] rerun ด้วย input เดิมได้ plan เดิมแบบ deterministic
- [x] dry-run ยังไม่ download จริง

### F.3 Quality
- [ ] เพิ่ม metadata สำหรับ selection reason
- [ ] เพิ่ม upstream evidence ลง manifest
- [ ] เพิ่ม report summary ถ้าต้องการ

---

## G. Phase 5 — Cache decision

### G.1 Cache identity
- [x] cache ผูกกับ os
- [x] cache ผูกกับ version
- [x] cache ผูกกับ arch
- [x] cache ผูกกับ listing/source
- [x] cache ผูกกับ checksum

### G.2 Cache states
- [x] detect `MISS`
- [x] detect `HIT`
- [x] detect `INVALID`
- [ ] detect `STALE`

### G.3 Cache behavior
- [x] ถ้ามี file + meta + checksum ตรง ให้เป็น HIT
- [x] ถ้ามี file แต่ meta ไม่ครบ ให้เป็น INVALID
- [ ] ถ้า checksum เปลี่ยน ให้เป็น STALE
- [ ] ถ้า source เปลี่ยน ให้เป็น STALE

---

## H. Phase 6 — Controlled download

### H.1 Execution gate
- [x] execute ต้องใช้ `--plan-id`
- [x] execute อ่านจาก `plan.json`
- [x] execute ไม่ re-resolve source ใหม่
- [x] block ถ้าไม่มี plan

### H.2 Download behavior
- [x] download จริงได้
- [x] verify checksum หลังโหลดได้
- [x] เขียน `run.json` ได้
- [x] เขียน `logs.jsonl` ได้
- [x] เขียน global sync log ได้
- [x] แสดง percent progress ได้

### H.3 Hardening
- [ ] แสดง MB/s
- [ ] แสดง ETA
- [ ] cleanup `.partial` เมื่อ fail
- [ ] cleanup `.partial` เมื่อ cancel
- [ ] รองรับ retry ที่ปลอดภัย
- [ ] รองรับ timeout handling ที่ดีขึ้น

### H.4 Cache reuse
- [x] rerun แล้วใช้ cache hit ได้ในหลักการ
- [ ] ทดสอบ cache hit จริงซ้ำหลัง download สำเร็จ
- [ ] ทดสอบ INVALID path จริง
- [ ] ทดสอบ STALE path จริง

---

## I. Documentation alignment

- [x] มี `current-plan.md`
- [x] มี `checklist-current-plan.md`
- [x] docs อธิบาย scope phase 0–6
- [x] docs อธิบาย dry-run และ execute
- [ ] docs อัปเดต command examples ให้ครบทุก OS coverage
- [ ] docs ใส่ known limitations ให้ชัด
- [ ] docs ใส่ troubleshooting guide

---

## J. Test matrix — Core

### J.1 Positive tests
- [x] ubuntu 22.04 amd64 dry-run
- [x] ubuntu alias `jammy` amd64 dry-run
- [x] debian 12 amd64 dry-run
- [x] ubuntu 22.04 execute จริง
- [ ] debian 12 execute จริง
- [ ] ubuntu 24.04 dry-run
- [ ] ubuntu 24.04 execute จริง

### J.2 Negative tests
- [ ] unsupported os
- [ ] unsupported version
- [ ] unsupported arch
- [ ] missing plan-id
- [ ] bad plan-id
- [ ] candidate ambiguity
- [ ] checksum missing
- [ ] checksum mismatch

### J.3 Cache tests
- [ ] first run = MISS
- [ ] second run = HIT
- [ ] file exists but meta missing = INVALID
- [ ] checksum changed = STALE

---

## K. Coverage plan

## K.1 Ubuntu
- [ ] Ubuntu 20.04 policy
- [x] Ubuntu 22.04 policy
- [ ] Ubuntu 24.04 policy verification test
- [ ] Ubuntu coverage test complete

## K.2 Debian
- [x] Debian 12 policy
- [ ] Debian 12 execute test complete
- [ ] Debian 13 policy (ถ้าจะรองรับ)
- [ ] Debian coverage test complete

## K.3 Fedora
- [ ] Fedora policy added
- [ ] Fedora dry-run test
- [ ] Fedora execute test

## K.4 Rocky
- [ ] Rocky policy added
- [ ] Rocky dry-run test
- [ ] Rocky execute test

## K.5 AlmaLinux
- [ ] AlmaLinux policy added
- [ ] AlmaLinux dry-run test
- [ ] AlmaLinux execute test

---

## L. Hardening plan before moving forward

- [ ] improve input validation
- [ ] improve error taxonomy
- [ ] improve selection reason logging
- [ ] add version cross-check from extra metadata
- [ ] add download speed / ETA
- [ ] add partial cleanup
- [ ] add stale cache logic
- [ ] add retry policy
- [ ] add timeout policy

---

## M. Gate before moving to later phases

ห้ามไป phase build/upload ถ้ายังไม่ผ่านขั้นต่ำดังนี้:

- [ ] Ubuntu dry-run + execute ผ่าน
- [ ] Debian dry-run + execute ผ่าน
- [ ] cache hit test ผ่าน
- [ ] invalid input tests ผ่าน
- [ ] bad plan-id test ผ่าน
- [ ] checksum mismatch test ผ่าน
- [ ] ambiguity reject test ผ่าน
- [ ] docs ตรงกับของจริง
- [ ] coverage baseline ผ่านอย่างน้อย Ubuntu + Debian

---

## N. Immediate next actions

- [ ] commit current working version
- [ ] push current working version
- [ ] add MB/s and ETA to progress
- [ ] test cache hit on second run
- [ ] add partial cleanup on fail/cancel
- [ ] test invalid input set
- [ ] test missing/bad plan-id
- [ ] test Debian execute
- [ ] update docs after each verified change
