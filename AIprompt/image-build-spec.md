# Image Build System - Project Specification
# สรุปทั้งหมดที่ออกแบบไว้

---

## บริบทโปรเจกต์

Repository นี้คือระบบ Pipeline อัตโนมัติสำหรับสร้างและเผยแพร่ OpenStack Image
สำหรับ Linux distributions ต่างๆ ทำงานผ่าน Jump Host

**สิ่งที่ห้ามเปลี่ยน:**
- Pipeline behavior ทั้งหมด
- Guest VM policy
- Ubuntu flow ที่ทำงานอยู่แล้ว
- Multi-OS download behavior

---

## 1. โครงสร้าง Config ใหม่

### หลักการ
- แต่ละ OS แต่ละ version มี config แยกกันชัดเจน
- เพิ่ม version ใหม่ได้โดยเพิ่มไฟล์เดียว
- loading pattern: โหลด base.env ก่อน แล้ว override ด้วย version-specific

```
config/
│
├── jumphost/
│   └── jumphost.env
│       # JUMP_HOST_ADDR=
│       # JUMP_HOST_USER=
│       # JUMP_HOST_PORT=
│       # JUMP_HOST_REPO_PATH=
│       # JUMP_HOST_BRANCH=
│       # JUMP_SSH_KEY_FILE=
│       # JUMP_SSH_CONFIG_FILE=
│
├── git/
│   └── git.env
│       # REPO_URL=
│       # BRANCH=
│
├── openstack/
│   ├── openrc.path
│   │   # OPENRC_FILE=
│   └── project-natties.env        ← เพิ่ม project ใหม่ได้โดยเพิ่มไฟล์
│       # EXPECTED_PROJECT_NAME=
│       # NETWORK_ID=
│       # FLAVOR_ID=
│       # VOLUME_TYPE=
│       # VOLUME_SIZE_GB=
│       # SECURITY_GROUP=
│       # KEY_NAME=
│       # FLOATING_NETWORK=
│
├── os/
│   ├── ubuntu/
│   │   ├── base.env               ← ค่า default ทุก ubuntu version
│   │   │   # OS_FAMILY=ubuntu
│   │   │   # ARCH=amd64
│   │   │   # LTS_ONLY=1
│   │   │   # CURL_RETRY=3
│   │   │   # CURL_CONNECT_TIMEOUT=20
│   │   │   # VERIFY_SHA256=1
│   │   │   # UBUNTU_RELEASES_BASE_URL=
│   │   │   # IMAGE_PATTERNS=
│   │   │
│   │   ├── 18.04.env              ← override เฉพาะ 18.04
│   │   │   # MIN_VERSION=18.04
│   │   │   # OLS_BASE_URL=http://old-releases.ubuntu.com/ubuntu
│   │   │   # FALLBACK_SERIES=18.04:bionic
│   │   │
│   │   ├── 22.04.env
│   │   │   # MIN_VERSION=22.04
│   │   │   # OLS_BASE_URL=http://mirrors.openlandscape.cloud/ubuntu
│   │   │   # FALLBACK_SERIES=22.04:jammy
│   │   │
│   │   └── 24.04.env
│   │       # MIN_VERSION=24.04
│   │       # OLS_BASE_URL=http://mirrors.openlandscape.cloud/ubuntu
│   │       # FALLBACK_SERIES=24.04:noble
│   │
│   ├── debian/
│   │   ├── base.env
│   │   └── 12.env
│   │
│   ├── rocky/
│   │   ├── base.env
│   │   └── 9.env
│   │
│   ├── centos/
│   │   ├── base.env
│   │   └── 9.env
│   │
│   └── almalinux/
│       ├── base.env
│       └── 9.env
│
├── guest/                         ← policy ใน VM แยกตาม OS+version
│   ├── base.env                   ← ค่า default ทุก OS
│   │   # TIMEZONE=Asia/Bangkok
│   │   # DEFAULT_LANG=en_US.UTF-8
│   │   # EXTRA_LOCALES=th_TH.UTF-8
│   │   # DO_UPGRADE=yes
│   │   # REBOOT_AFTER_UPGRADE=yes
│   │   # WAIT_CLOUD_INIT=yes
│   │   # DISABLE_AUTO_UPDATES=yes
│   │   # DISABLE_MOTD_NEWS=yes
│   │   # DISABLE_GUEST_FIREWALL=yes
│   │   # ROOT_SSH_PERMIT=yes
│   │   # ROOT_PASSWORD_AUTH=yes
│   │   # ROOT_PUBKEY_AUTH=yes
│   │   # KERNEL_KEEP=2
│   │
│   ├── ubuntu-18.04.env           ← override เฉพาะ ubuntu 18.04
│   │   # OLS_BASE_URL=http://old-releases.ubuntu.com/ubuntu
│   │   # OLD_RELEASES_URL=http://old-releases.ubuntu.com/ubuntu
│   │   # KERNEL_KEEP=1
│   │
│   ├── ubuntu-22.04.env
│   │   # OLS_BASE_URL=http://mirrors.openlandscape.cloud/ubuntu
│   │
│   └── ubuntu-24.04.env
│       # OLS_BASE_URL=http://mirrors.openlandscape.cloud/ubuntu
│       # KERNEL_KEEP=2
│
├── pipeline/
│   ├── publish.env
│   │   # FINAL_IMAGE_VISIBILITY=private
│   │   # FINAL_IMAGE_TAGS=stage:complete,os:ubuntu
│   │   # ON_FINAL_EXISTS=recover
│   │   # DELETE_SERVER_BEFORE_PUBLISH=yes
│   │   # DELETE_VOLUME_AFTER_PUBLISH=yes
│   │   # DELETE_BASE_IMAGE_AFTER_PUBLISH=yes
│   │   # WAIT_FOR_FINAL_ACTIVE=yes
│   │   # WAIT_FINAL_TIMEOUT_SECONDS=3600
│   │
│   └── clean.env
│       # POWEROFF_WHEN_DONE=yes
│       # BUILD_USER_HOME=
│
└── credentials/                   ← gitignored ทั้งโฟลเดอร์ ยกเว้น .example
    ├── guest-access.env.example   ← template track ใน git
    │   # ROOT_USER=root
    │   # ROOT_PASSWORD=
    │   # SSH_PORT=22
    │   # ROOT_AUTHORIZED_KEY=
    │
    └── guest-access.env           ← ของจริง gitignored
```

### Loading Flow ของ Config
```
1. โหลด config/os/ubuntu/base.env
2. override ด้วย config/os/ubuntu/24.04.env
3. โหลด config/guest/base.env
4. override ด้วย config/guest/ubuntu-24.04.env
5. โหลด config/openstack/project-natties.env
6. โหลด config/credentials/guest-access.env
7. โหลด deploy/local/*.env (local overrides)
```

### การเพิ่ม Version ใหม่ในอนาคต
```bash
# ต้องการเพิ่ม ubuntu 25.04
cp config/os/ubuntu/24.04.env config/os/ubuntu/25.04.env
cp config/guest/ubuntu-24.04.env config/guest/ubuntu-25.04.env
# แก้เฉพาะค่าที่ต่างจาก base
```

---

## 2. โครงสร้าง Log ใหม่

```
logs/
├── download/
│   └── ubuntu/
│       ├── 18.04/
│       │   └── 20260320-143000.log
│       ├── 22.04/
│       └── 24.04/
│           └── 20260320-143000.log
│
├── openstack/
│   └── ubuntu/
│       └── 24.04/
│           ├── import-20260320-143000.log
│           ├── create-vm-20260320-143000.log
│           └── publish-20260320-143000.log
│
├── vm-config/
│   └── ubuntu/
│       └── 24.04/
│           └── configure-20260320-143000.log
│
└── summary/
    └── 20260320-143000-ubuntu-24.04.log
        # PHASE: download   → SUCCESS
        # PHASE: import     → SUCCESS
        # PHASE: create-vm  → SUCCESS
        # PHASE: configure  → FAILED
        # PHASE: clean      → PENDING
        # PHASE: publish    → PENDING
```

---

## 3. โครงสร้าง State และ Manifest ใหม่

### State (สถานะปัจจุบันของแต่ละ phase)
```
runtime/state/
└── ubuntu/
    ├── 18.04/
    │   ├── last-download.env
    │   ├── last-import.env
    │   ├── last-vm.env
    │   ├── last-configure.env
    │   └── last-publish.env
    └── 24.04/
        ├── last-download.env
        │   # STATUS=success
        │   # TIMESTAMP=20260320-143000
        │   # ARTIFACT_NAME=
        │   # LOCAL_PATH=
        │   # SHA256=
        │
        ├── last-import.env
        │   # STATUS=success
        │   # BASE_IMAGE_ID=
        │   # BASE_IMAGE_NAME=
        │
        ├── last-vm.env
        │   # STATUS=success
        │   # SERVER_ID=
        │   # VOLUME_ID=
        │   # VM_NAME=
        │   # LOGIN_IP=
        │
        ├── last-configure.env
        │   # STATUS=failed
        │   # TIMESTAMP=
        │
        └── last-publish.env
            # STATUS=success
            # FINAL_IMAGE_ID=
            # FINAL_IMAGE_NAME=
```

### Manifest (ข้อมูล artifact ที่ build แล้ว)
```
manifests/
└── ubuntu/
    ├── 18.04/
    │   ├── download.json
    │   └── base-image.env
    └── 24.04/
        ├── download.json
        └── base-image.env
```

---

## 4. เมนูใหม่

### หน้าแรก (Status Dashboard)
```
═══════════════════════════════════════════════════
  Image Build System v2.0
═══════════════════════════════════════════════════
 Connection  : ● Connected  jump-host-01 (10.x.x.x)
 Project     : natties_op
 Last Run    : ubuntu 24.04 - SUCCESS (2026-03-20 14:30)

 OS              DL    IMPORT  VM    CONFIG  PUBLISH
 ubuntu 18.04  [ ✓ ] [ ✓ ]  [ ✓ ] [ ✓ ]  [ ✓ ]
 ubuntu 22.04  [ ✓ ] [ ✓ ]  [ ✓ ] [ ✗ ]  [ - ]
 ubuntu 24.04  [ ✓ ] [ - ]  [ - ] [ - ]  [ - ]
 debian 12     [ ✓ ] [ - ]  [ - ] [ - ]  [ - ]
═══════════════════════════════════════════════════
```

### Main Menu
```
Main Menu
├── 1. System    (จัดการระบบ)
│   ├── 1.1 SSH Connect       - เปิด terminal ไป jump host
│   ├── 1.2 SSH Validate      - ทดสอบ connection
│   ├── 1.3 SSH Info          - ดูข้อมูล connection
│   ├── 1.4 Git Bootstrap     - เตรียม repo บน jump host ครั้งแรก
│   ├── 1.5 Git Sync          - sync code ไป jump host
│   └── 1.6 Git Status        - ดูสถานะ git
│
├── 2. Run       (รัน pipeline)
│   ├── 2.1 Full Run          - รันทุก OS ทุก version ตั้งแต่ต้นจนจบ
│   ├── 2.2 By OS             - เลือก OS แล้วรันทุก version
│   ├── 2.3 By Version        - เลือก OS และ version ที่ต้องการ
│   └── 2.4 By Phase          - เลือก OS, version และ phase เดี่ยวๆ
│
├── 3. Resume    (ต่อจากที่ค้าง)
│   └── แสดง version ที่พัง → เลือก → ต่อได้เลย
│
├── 4. Cleanup   (ลบ resource ใน OpenStack)
│   ├── 4.1 By OS             - เลือก OS → ลบทุก version
│   ├── 4.2 By Version        - เลือก OS และ version
│   └── 4.3 Clean All         - ลบทุกอย่างทุก OS
│
├── 5. Status    (ดูสถานะละเอียด)
│   └── แสดงทุก OS ทุก version ว่าแต่ละ phase เป็นยังไง
│
└── 6. Exit      (ออก)
```

### Run Flow (เมนู 2)
```
กด Run → เลือก preset:
  Full Run / By OS / By Version / By Phase
    ↓
  เลือก project (เลือกครั้งเดียวตอนเริ่ม)
    ↓
  เลือก OS (ubuntu / debian / rocky / centos)
    ↓
  เลือก version (ทั้งหมด หรือเลือกเฉพาะ)
    ↓
  เลือก phase (ถ้าเลือก By Phase)
    ↓
  แสดงสรุปว่าจะทำอะไร → confirm → run
```

### Resume Flow (เมนู 3)
```
กด Resume → script ดู state แล้วแสดง:
  ┌─────────────────────────────────────┐
  │ พบ pipeline ที่ยังไม่เสร็จ:          │
  │ ubuntu 22.04 - ค้างที่ configure     │
  │ ubuntu 24.04 - ค้างที่ import        │
  └─────────────────────────────────────┘
  เลือก version → confirm → ต่อได้เลย
```

### Cleanup Flow (เมนู 4)
```
กด Cleanup → เลือก By OS / By Version / Clean All
  ↓
แสดงสิ่งที่จะถูกลบ:
  ┌─────────────────────────────────────────┐
  │ จะลบ ubuntu 24.04:                      │
  │ ├── Base Image  : abc-123  [พบ]         │
  │ ├── VM/Server   : def-456  [พบ]         │
  │ ├── Volume      : ghi-789  [พบ]         │
  │ └── Final Image : jkl-000  [ไม่พบ]      │
  └─────────────────────────────────────────┘
  ยืนยันการลบ? (yes/no) → ลบ
```

---

## 5. Cleanup Logic

### Graceful Degradation
```
ลบทุก resource ที่หาเจอ ข้ามสิ่งที่ไม่เจอ ไม่ error หยุด:

ลบ VM     → ไม่เจอ → ข้ามไป log ว่า "ไม่พบ VM"
ลบ Volume → เจอ    → ลบได้
ลบ Base Image → เจอ → ลบได้
ลบ Final Image → ไม่เจอ → ข้ามไป log ว่า "ไม่พบ Final Image"
สรุป: ลบได้ 2/4 → แจ้งผลให้ชัดเจน
```

### กรณีไม่มี State File
```
ไม่มี state file
  ↓
ค้นหาใน OpenStack โดยใช้ชื่อ pattern
เช่น "ubuntu-24.04-*"
  ↓
เจอ → แสดงให้ user เลือก
ไม่เจอ → แจ้ง "ไม่พบ resource" แล้วข้ามไป
```

### สิ่งที่ถูกลบในแต่ละ version
```
├── Base Image    (glance image ที่ import เข้า openstack)
├── VM/Server     (openstack server)
├── Volume        (cinder volume)
└── Final Image   (image complete ที่ publish แล้ว)
```

### ต้อง Confirm ก่อนลบทุกครั้ง
```
"คุณแน่ใจว่าต้องการลบ ubuntu 24.04 ทั้งหมด? (yes/no)"
```

---

## 6. Error Handling และ Retry Flow

### Import พัง
```
import พัง
  ↓
retry 1 ครั้ง (ลบ base image เก่า → import ใหม่)
  ↓ ถ้าพังอีก
แจ้ง user → หยุดรอ user ตัดสินใจ
```

### Configure พัง (สำคัญมาก พังบ่อย)
```
configure พัง
  ↓
retry configure กับ VM เดิม 1 ครั้ง
  ↓ ถ้าพังอีก
ลบ VM + Volume → สร้าง VM ใหม่ → retry configure 1 ครั้ง
  ↓ ถ้าพังอีก
แจ้ง user → หยุดรอ user ตัดสินใจ
```

### VM Boot ไม่ขึ้น
```
สร้าง VM แล้วรอ ACTIVE timeout
  ↓ ถ้า timeout
retry 1 ครั้ง (ลบ VM → สร้างใหม่)
  ↓ ถ้าพังอีก
แจ้ง user → หยุด
```

### SSH เข้า VM ไม่ได้
```
รอ SSH ready timeout
  ↓ ถ้า timeout
retry 1 ครั้ง
  ↓ ถ้าพังอีก
แจ้ง user → หยุด
```

### Config ไม่เข้ากับ Version (พังบ่อยที่สุด)
```
สาเหตุหลัก:
- ubuntu 18.04 ใช้ mirror เก่า old-releases
- ubuntu 24.04 ใช้ mirror ใหม่
- apt command, package name, service name ต่างกัน
- sshd config format ต่างกัน

การดัก:
- แต่ละ version โหลด guest config ของตัวเองก่อนเสมอ
- ตรวจ OS version ใน VM จริงก่อน configure
- ถ้า version ไม่ตรงกับที่คาดไว้ → แจ้ง error ชัดเจน
```

### Status ที่แสดงเมื่อ Error
```
แจ้ง error ต้องบอก:
├── phase ที่พัง
├── OS และ version
├── error message จริงๆ
├── สิ่งที่ได้ลองทำแล้ว (retry กี่ครั้ง)
└── แนะนำว่าต้องทำอะไรต่อ
```

---

## 7. OS ที่รองรับ

### ปัจจุบัน (Implemented)
```
ubuntu → full pipeline (download → import → create → configure → clean → publish)
```

### รองรับ Download เท่านั้น
```
debian
centos
almalinux
rocky
```

### อนาคต (ยังไม่ทำ)
```
windows → architecture ต่างมาก ทำทีหลัง
```

### Pattern การเพิ่ม OS ใหม่
```
1. สร้าง config/os/[os]/base.env
2. สร้าง config/os/[os]/[version].env
3. สร้าง config/guest/[os]-[version].env (ถ้า implement configure ด้วย)
4. script จะ auto pickup
```

---

## 8. สิ่งที่ต้องแก้ในโค้ดปัจจุบัน

### ปัญหาร้ายแรง
```
1. Credentials ใน tracked code
   - lib/runtime_helpers.sh มี ROOT_PASSWORD hardcode
   - doc/ มี password จริง
   → ย้ายออกไป config/credentials/guest-access.env

2. node_modules/ อยู่ใน git
   → เพิ่มใน .gitignore และลบออก

3. geminido.md อยู่ใน root
   → ลบออก

4. package.json ไม่สัมพันธ์กับ project
   → ลบออก
```

### ปัญหา Architecture
```
5. imagectl_os_is_implemented() hardcode
   → อ่านจาก config/os/[os]/base.env ที่มี OS_IMPLEMENTED=yes แทน

6. control_main.sh ใหญ่เกินไป
   → แยก pipeline logic ออกเป็น control_pipeline.sh

7. runtime_helpers.sh เรียก subshell ซ้ำหนัก
   → cache ด้วย associative array

8. local_overrides.sh กับ runtime_helpers.sh ทับกัน
   → รวมเป็น function เดียวที่ชัดเจน
```

---

## 9. .gitignore ที่ต้องเพิ่ม

```gitignore
# Local config
deploy/local/**
!deploy/local/.gitkeep

# Credentials
config/credentials/guest-access.env
config/credentials/*.env
!config/credentials/*.env.example

# Runtime
cache/**
tmp/**
runtime/state/**
logs/*.log
logs/**/*.log

# Node
node_modules/
package-lock.json

# OS
.DS_Store
```

---

## 10. สรุป Library Files ที่ต้องมี

```
lib/
├── control_common.sh      ← utility (log, die, prompt) ไม่เปลี่ยน
├── control_jump_host.sh   ← SSH connection ไม่เปลี่ยน
├── control_sync.sh        ← git sync ไม่เปลี่ยน
├── control_git.sh         ← git operations ไม่เปลี่ยน
├── control_main.sh        ← menu + dispatch (ลด size ลง)
├── control_pipeline.sh    ← NEW: แยก pipeline logic ออกมา
├── control_cleanup.sh     ← NEW: cleanup logic
├── control_status.sh      ← NEW: status display logic
├── os_helpers.sh          ← แก้ให้อ่าน config แทน hardcode
├── runtime_helpers.sh     ← แก้ credentials และ performance
├── layout.sh              ← แก้ให้รองรับ structure ใหม่
└── local_overrides.sh     ← ปรับให้ชัดเจนขึ้น
```

---

## คำสั่งที่ยังใช้ได้เหมือนเดิม (Compatibility)

```bash
# ยังใช้ได้ทุกอัน
bash scripts/control.sh
bash scripts/control.sh ssh validate
bash scripts/control.sh git bootstrap
bash scripts/control.sh git sync-safe
bash scripts/control.sh pipeline manual
bash scripts/control.sh pipeline auto-by-os --os ubuntu
bash scripts/control.sh pipeline auto-by-os-version --os ubuntu --version 24.04
```
