# Current Plan — Sync Image System (Phase 0–6 + Coverage)

## 1) เป้าหมายของเอกสารนี้

เอกสารนี้เป็นแผนงานปัจจุบันของระบบ **sync image** สำหรับโปรเจกต์ `image-build` โดยโฟกัสเฉพาะงานต้นน้ำที่สำคัญที่สุดก่อน ได้แก่

- Phase 0: Input intake and normalization
- Phase 1: Policy loading and source mapping
- Phase 2: Official source discovery
- Phase 3: Version guard and checksum planning
- Phase 4: Dry-run plan and state persistence
- Phase 5: Cache decision
- Phase 6: Controlled download

เป้าหมายคือทำให้ phase ต้นน้ำนี้ **นิ่ง, deterministic, strict, state-driven, rerun-safe และไม่มั่ว** ก่อนจะไปต่อ phase build / guest / upload / validation ภายหลัง

---

## 2) เป้าหมายหลักของระบบ sync image

ระบบ sync image ที่ต้องการต้องทำได้ครบดังนี้

1. รับ input แล้ว normalize เป็น canonical form ได้
2. map OS/version/arch ไป official source ที่ถูกต้องได้
3. fetch official listing ได้จริง
4. เลือก candidate แบบ strict ไม่เดา
5. parse checksum ได้จริง
6. freeze resolved result ลง `plan.json`
7. ตัดสิน cache ได้ว่าควรใช้ของเดิมหรือโหลดใหม่
8. execute จริงโดยอิง `plan.json` เท่านั้น
9. verify checksum หลังโหลดเสมอ
10. รองรับ rerun โดยไม่โหลดซ้ำมั่ว
11. มี logs / manifest / run record ตรวจย้อนหลังได้
12. ขยาย coverage OS/version ได้ทีละชุดอย่างปลอดภัย

---

## 3) หลักการออกแบบที่ห้ามผิด

### 3.1 Dry-run first
ห้าม download จริงก่อนมี dry-run plan

### 3.2 Plan-driven execution
ห้าม execute จริงโดย resolve source ใหม่เอง
การ execute ต้องอ่านจาก `plan.json` เท่านั้น

### 3.3 Strict version discipline
ห้าม fuzzy match / ห้ามเดา / ห้ามเลือกหลาย candidate แล้วสุ่มเอา
ถ้าไม่ชัด ต้อง fail

### 3.4 Checksum as gate
checksum ไม่ใช่ของเสริม แต่เป็น gate สำคัญก่อน promote ไฟล์เข้า cache

### 3.5 Cache must be identity-based
cache ต้องผูกกับ:
- os
- version
- arch
- listing/source
- selected filename
- expected checksum

### 3.6 Host allowlist
request ทุกตัวต้องผ่าน allowlist เพื่อกัน source ผิด host

### 3.7 Observable system
ทุก phase ต้องมีผลลัพธ์ให้ตรวจย้อนหลังได้ เช่น:
- plan.json
- manifest.json
- run.json
- logs.jsonl
- sync.log.jsonl

---

## 4) ขอบเขตงานปัจจุบัน

## In scope
- sync-only phase 0–6
- dry-run
- strict source selection
- checksum planning
- cache decision เบื้องต้น
- execute download จริง
- progress ระหว่างโหลด
- OS coverage expansion

## Out of scope
- image build/customization
- guest access logic
- OpenStack upload
- boot validation
- post-upload validation
- guest agent / cloud-init checks

---

## 5) โครงสร้างไฟล์เป้าหมาย

```text
repo/
├─ .gitignore
├─ config/
│  └─ sync-config.json
│
├─ tools/
│  └─ sync/
│     ├─ sync_image.sh
│     ├─ sync_image.py
│     ├─ checklist_patch.py
│     └─ fixtures/
│
├─ state/
│  └─ sync/
│     └─ plans/
│        └─ <plan_id>/
│           ├─ plan.json
│           ├─ run.json
│           ├─ manifest.json
│           └─ logs.jsonl
│
├─ cache/
│  └─ official/
│     └─ <os>/<release>/<arch>/<artifact_type>/<cache_key_prefix>/
│        ├─ <image-file>
│        └─ <image-file>.meta.json
│
├─ logs/
│  └─ sync/
│     └─ sync.log.jsonl
│
├─ reports/
│  └─ sync/
│
└─ docs/
   ├─ current-plan.md
   └─ checklist-current-plan.md
```

---

## 6) ภาพรวม flow ปัจจุบัน

```text
input
-> normalize
-> validate
-> load policy
-> map source
-> fetch official listing
-> strict candidate selection
-> fetch checksum file
-> resolve expected checksum
-> build dry-run plan
-> persist state
-> detect cache status
-> execute from plan.json only
-> verify checksum
-> write run.json + logs
```

---

## 7) Detailed pipeline by phase

## PHASE 0 — Input intake and normalization

### เป้าหมาย
ทำให้ input จากผู้ใช้หรือ automation อยู่ในรูปที่ canonical และตรวจได้

### Input หลัก
- os
- version
- arch

### สิ่งที่ต้องทำ
- normalize os เช่น `Ubuntu` -> `ubuntu`
- normalize alias เช่น `jammy` -> `22.04`
- normalize arch เช่น `amd64` -> `x86_64`
- reject unsupported os/version/arch

### Output
- normalized input object

### Definition of done
- input เดิมและ alias ต้องได้ผลลัพธ์ canonical เดียวกัน
- invalid input ต้อง fail ชัดเจน

---

## PHASE 1 — Policy loading and source mapping

### เป้าหมาย
โหลด config กลาง และ map target ไป source policy ที่ถูกต้อง

### สิ่งที่ต้องมีใน config
- alias map
- architecture map
- listing_url
- filename_patterns
- checksum_file
- checksum_algorithm
- release_name
- artifact_type
- allowed_hosts

### Output
- effective source policy for selected target

### Definition of done
- target ที่รองรับต้อง map ได้
- target ที่ไม่รองรับต้อง fail ชัด
- allowlist ต้องมี

---

## PHASE 2 — Official source discovery

### เป้าหมาย
ดึง official listing จริง และเลือก candidate ที่ตรง target แบบ strict

### ขั้นตอน
1. fetch listing page
2. parse links/files
3. match ตาม filename pattern
4. filter ตาม arch
5. ต้องเหลือ candidate เดียว

### Failure conditions
- fetch ไม่ได้
- host ไม่อยู่ allowlist
- candidate = 0
- candidate > 1

### Definition of done
- selected filename มาจาก official listing จริง
- ambiguity ต้องถูก reject

---

## PHASE 3 — Version guard and checksum planning

### เป้าหมาย
ล็อก artifact ที่จะโหลดให้ชัด และมี checksum ที่ใช้ verify ได้จริง

### ขั้นตอน
1. fetch checksum file
2. parse checksum ของ selected filename
3. cross-check ว่า filename ที่เลือกมี checksum จริง
4. freeze checksum ลง plan

### สิ่งที่ควรเพิ่มในรอบ hardening
- cross-check version กับ upstream metadata เพิ่ม
- เก็บเหตุผลการเลือก candidate
- เก็บ evidence ว่า checksum มาจากไฟล์ไหน

### Definition of done
- selected filename + expected checksum ต้องถูก freeze ลง `plan.json`

---

## PHASE 4 — Dry-run plan and state persistence

### เป้าหมาย
สร้าง plan ที่ใช้ execute จริงได้ โดย dry-run ยังไม่โหลดจริง

### สิ่งที่ต้องเขียน
- `plan.json`
- `manifest.json`
- `logs.jsonl`
- global log

### ข้อมูลสำคัญใน plan
- input canonical
- source listing
- checksum url
- expected checksum
- selected filename
- download url
- cache path
- status by phase
- guards

### Definition of done
- dry-run สร้าง state ได้ครบ
- rerun dry-run input เดิม ต้องได้ plan ที่ deterministic

---

## PHASE 5 — Cache decision

### เป้าหมาย
ตัดสินว่าควรโหลดใหม่หรือใช้ cache เดิม

### สถานะขั้นต่ำ
- `MISS`
- `HIT`
- `INVALID`

### สถานะที่ควรเพิ่ม
- `STALE`

### Logic ขั้นต่ำ
- ถ้ามี file + meta + checksum ตรง = HIT
- ถ้ามี file แต่ไม่มี meta = INVALID
- ถ้าไม่มีเลย = MISS

### Definition of done
- execute ต้องไม่โหลดซ้ำถ้า cache ตรงจริง

---

## PHASE 6 — Controlled download

### เป้าหมาย
โหลด image จริงจาก `plan.json` เท่านั้น พร้อม verify checksum

### ขั้นตอน
1. เปิด `plan.json`
2. ตรวจ guard
3. ถ้ามี cache hit ให้ skip download
4. ถ้า miss ให้ stream download ลง `.partial`
5. แสดง progress
6. คำนวณ checksum ระหว่างโหลด
7. verify checksum
8. rename `.partial` -> final file
9. เขียน meta / run / logs

### สิ่งที่ต้อง harden เพิ่ม
- MB/s
- ETA
- cleanup `.partial` เมื่อ cancel/fail
- timeout / retry
- better error messages

### Definition of done
- download สำเร็จ
- checksum ตรง
- rerun แล้วกลายเป็น cache hit

---

## 8) สถานะปัจจุบันที่ถือว่าทำได้แล้ว

จากการทดสอบที่มีอยู่ตอนนี้ ระบบทำได้แล้วอย่างน้อย:
- normalize input
- alias mapping
- arch mapping
- dry-run for ubuntu/debian
- official listing fetch จริง
- checksum planning จริง
- execute จาก `plan_id`
- download จริงสำเร็จ
- checksum verify สำเร็จ
- progress percent แสดงได้

---

## 9) Gap ที่ยังต้องทำต่อ

## 9.1 Hardening ที่ยังไม่ครบ
- validate input edge cases ครบ
- reject invalid combinations ครบ
- cross-check version กับ metadata เพิ่ม
- error messages ให้ชัดขึ้น
- partial cleanup เมื่อ fail/cancel
- progress แบบ speed + ETA
- retry/timeout policy
- stale cache detection

## 9.2 Coverage ที่ยังไม่ครบ
ต้องขยาย coverage ของ OS/version แบบมีระบบ

### Ubuntu
- 20.04
- 22.04
- 24.04

### Debian
- 12
- 13 (ถ้าจะรองรับ)

### เพิ่มภายหลัง
- Fedora
- Rocky
- AlmaLinux
- CentOS Stream / equivalent policy ตามที่ต้องการ

---

## 10) Coverage strategy

coverage ต้องเพิ่มแบบ “ทีละระบบ + มีเทสคู่กัน” ไม่ใช่เพิ่ม config แล้วถือว่าจบ

### ขั้นตอนต่อ OS/version
1. เพิ่ม policy ลง config
2. เพิ่ม alias map
3. เพิ่ม filename patterns
4. เพิ่ม checksum type
5. dry-run test
6. execute test
7. cache hit test
8. invalid input test
9. ambiguity test
10. checksum failure simulation

---

## 11) Test matrix ที่ต้องมี

## Core matrix
- ubuntu 22.04 amd64 dry-run
- ubuntu 22.04 amd64 execute
- ubuntu jammy amd64 dry-run
- debian 12 amd64 dry-run
- debian 12 amd64 execute

## Negative matrix
- unsupported os
- unsupported version
- unsupported arch
- missing plan-id
- bad plan-id
- candidate ambiguity
- checksum missing
- checksum mismatch

## Cache matrix
- first run = MISS
- second run = HIT
- file exists but meta missing = INVALID
- stale checksum = STALE (ต้องเพิ่ม)

---

## 12) AI / CML execution goals

ถ้าจะสั่ง AI/CML ให้ทำต่อ เป้าหมายที่ควรสั่งคือ:

### Goal A — Hardening phase 0–6
ทำให้ระบบ sync-only phase 0–6 production-grade ขึ้น โดย:
- เพิ่ม speed + ETA
- cleanup `.partial`
- retry policy
- better errors
- stale detection
- input validation เพิ่ม

### Goal B — Expand coverage
เพิ่ม OS/version coverage ทีละชุด พร้อมเทสจริงทุกชุด:
- Ubuntu: 20.04, 22.04, 24.04
- Debian: 12, 13 (ถ้าต้องการ)
- Fedora / Rocky / AlmaLinux ภายหลัง

### Goal C — Documentation alignment
เอกสารต้องตรงกับของจริงเสมอ:
- current-plan.md
- checklist-current-plan.md
- command examples
- known limitations

---

## 13) ลำดับงานถัดไปที่แนะนำ

### Priority 1
- เพิ่ม speed + ETA ใน progress
- cleanup partial เมื่อ fail
- cache hit test รอบสอง
- invalid input tests
- missing plan-id tests

### Priority 2
- stale cache detection
- better error taxonomy
- selection reason logging
- cross-check metadata เพิ่ม

### Priority 3
- coverage expansion for Ubuntu/Debian
- coverage tests ต่อ OS/version

---

## 14) Definition of ready before moving to later phases

ห้ามไป phase build/upload ถ้า sync phase ยังไม่ผ่านเกณฑ์นี้:

- dry-run ใช้งานได้
- execute ใช้งานได้
- checksum verify ใช้งานได้
- cache hit works
- invalid input rejects
- ambiguous candidate rejects
- logs/manifests/run files usable
- อย่างน้อย Ubuntu + Debian coverage ผ่านจริง

---

## 15) สรุปสุดท้าย

ตอนนี้ระบบ sync image อยู่ในจุดที่ “เริ่มใช้งานได้จริง” แล้ว แต่ยังต้อง harden ต่ออีกเล็กน้อยก่อนจะถือว่าแข็งแรงพอสำหรับ coverage expansion เต็มรูปแบบ

เป้าหมายถัดไปจึงไม่ใช่การโดดไป phase อื่น แต่คือ:
1. harden phase 0–6 ให้แน่น
2. ขยาย coverage ทีละ OS/version
3. ปิด test matrix ให้ครบ
4. ค่อยไป phase build/upload ทีหลัง
