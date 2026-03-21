# Review Prompt - Image Build System
# Date: 2026-03-21
# Purpose: ตรวจสอบงานที่ทำไปแล้วทั้งหมดว่าตรงกับที่ออกแบบไว้ไหม

---

## คำสั่งสำหรับ AI

```
Please do a full review of this repository.
Read ALL files before starting the review.
Do NOT make any changes yet. Review only.
```

---

## สิ่งที่ต้องตรวจสอบ

---

### PART 1: Syntax Check (ตรวจ syntax ทุกไฟล์)

```
Run bash -n on every .sh file:
- scripts/control.sh
- scripts/*.sh
- bin/imagectl.sh
- lib/*.sh
- phases/*.sh

Report:
- ไฟล์ไหน pass
- ไฟล์ไหน fail และ error อะไร บรรทัดไหน
```

---

### PART 2: Structure Check (ตรวจโครงสร้างโฟลเดอร์)

ตรวจว่ามีโฟลเดอร์และไฟล์เหล่านี้ครบไหม:

**settings/ (ต้องมี)**
```
settings/jumphost.env.example
settings/git.env.example
settings/openstack.env.example
settings/openrc.env.example
settings/credentials.env.example
settings/README.md
```

**config/os/ (ต้องมี)**
```
config/os/ubuntu/base.env
config/os/ubuntu/18.04.env
config/os/ubuntu/22.04.env
config/os/ubuntu/24.04.env
```

**config/guest/ (ต้องมี)**
```
config/guest/base.env
config/guest/ubuntu-18.04.env
config/guest/ubuntu-24.04.env
```

**config/pipeline/ (ต้องมี)**
```
config/pipeline/publish.env
config/pipeline/clean.env
```

**lib/ (ต้องมี)**
```
lib/control_common.sh
lib/control_main.sh
lib/control_jump_host.sh
lib/control_sync.sh
lib/control_git.sh
lib/os_helpers.sh
lib/runtime_helpers.sh
lib/layout.sh
lib/local_overrides.sh
```

Report สิ่งที่ขาด และสิ่งที่ไม่ควรมีแต่มีอยู่

---

### PART 3: Config Loading Check (ตรวจการโหลด config)

ตรวจ lib/control_jump_host.sh:
```
- อ่านจาก settings/jumphost.env ไหม
- อ่านจาก settings/git.env ไหม
- มี fallback ไป deploy/local/ ไหม
- validate required fields ครบไหม
```

ตรวจ lib/runtime_helpers.sh:
```
- อ่านจาก settings/openstack.env ไหม
- อ่านจาก settings/openrc.env ไหม
- อ่านจาก settings/credentials.env ไหม
- sync list ถูกต้องไหม
- ไม่มี hardcoded password ใน code ไหม
```

---

### PART 4: Menu Check (ตรวจเมนู)

ตรวจ lib/control_main.sh ว่าเมนูตรงกับที่ออกแบบไว้:

**Main Menu ที่ถูกต้อง:**
```
1. System    (จัดการระบบ)
   - SSH Connect
   - SSH Validate
   - SSH Info
   - Git Bootstrap
   - Git Sync
   - Git Status

2. Run       (รัน pipeline)
   - Full Run
   - By OS
   - By Version
   - By Phase

3. Resume    (ต่อจากที่ค้าง)

4. Cleanup   (ลบ resource)
   - By OS
   - By Version
   - Clean All

5. Status    (ดูสถานะละเอียด)

6. Exit      (ออก)
```

Report:
- เมนูตรงไหม
- อะไรขาด
- อะไรเกิน

---

### PART 5: .gitignore Check (ตรวจ gitignore)

ตรวจว่า .gitignore มีครบ:
```
settings/                    ← gitignored
!settings/*.env.example      ← ยกเว้น template
deploy/local/**
!deploy/local/.gitkeep
cache/**
tmp/**
runtime/state/**
logs/*.log
logs/**/*.log
node_modules/
```

---

### PART 6: Security Check (ตรวจ security)

ตรวจทุกไฟล์ที่ track ใน git:
```
- มี password จริงอยู่ไหม
- มี IP จริงอยู่ไหม
- มี API key อยู่ไหม
- มี private key อยู่ไหม
- มี hardcoded credentials ใน .sh ไฟล์ไหม
```

Report ทุก line ที่พบ

---

### PART 7: Duplicate Check (ตรวจของซ้ำ)

ตรวจว่ามีไฟล์ที่ซ้ำซ้อนกับ settings/ ใหม่ไหม:
```
- config/jumphost/ ยังมีอยู่ไหม (ควรลบแล้ว)
- config/git/ ยังมีอยู่ไหม (ควรลบแล้ว)
- config/credentials/ ยังมีอยู่ไหม (ควรลบแล้ว)
- deploy/local/control.env ยังมีอยู่ไหม (fallback เท่านั้น)
```

---

### PART 8: Feature Check (ตรวจ feature ที่ควรมี)

ตรวจว่า feature เหล่านี้มีใน code ไหม:

```
Resume feature:
- มี logic ดู state file ไหม
- มี logic suggest version ที่พังไหม

Cleanup feature:
- มี cleanup by OS ไหม
- มี cleanup by version ไหม
- มี clean all ไหม
- มี graceful degradation ไหม (ข้ามถ้าไม่เจอ resource)
- มี confirm ก่อนลบไหม

Status dashboard:
- มีแสดง connection status ไหม
- มีแสดง per-version phase status ไหม

Retry logic:
- มี retry configure ไหม
- มี retry import ไหม
```

---

## รูปแบบ Report ที่ต้องการ

```
=== PART 1: Syntax Check ===
PASS: scripts/control.sh
PASS: lib/control_main.sh
FAIL: lib/runtime_helpers.sh line 42 - unexpected token

=== PART 2: Structure Check ===
MISSING: settings/jumphost.env.example
MISSING: config/guest/ubuntu-22.04.env
OK: config/os/ubuntu/base.env

=== PART 3: Config Loading Check ===
ISSUE: control_jump_host.sh ไม่ได้อ่านจาก settings/ ยังอ่านจาก deploy/local/ เท่านั้น

=== PART 4: Menu Check ===
MISSING: Resume menu ยังไม่มี
MISSING: Cleanup menu ยังไม่มี
OK: System menu ครบ
OK: Run menu ครบ

=== PART 5: .gitignore Check ===
MISSING: settings/ ยังไม่อยู่ใน .gitignore

=== PART 6: Security Check ===
DANGER: lib/runtime_helpers.sh line 28 มี ROOT_PASSWORD hardcoded

=== PART 7: Duplicate Check ===
DUPLICATE: config/jumphost/ ยังมีอยู่ ควรลบ

=== PART 8: Feature Check ===
MISSING: Resume feature ยังไม่มี
MISSING: Cleanup feature ยังไม่มี
MISSING: Retry logic ยังไม่มี

=== SUMMARY ===
Critical issues: X
Missing features: X
Minor issues: X
```

---

## หลังจาก Review เสร็จ

อย่าแก้ไขอะไรทั้งนั้น
รอให้ผม confirm ก่อนว่าจะแก้อะไรก่อน