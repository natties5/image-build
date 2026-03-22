# 01 — Start Project Blueprint

เอกสารนี้เป็น “ไฟล์ตั้งต้น” ของโปรเจกต์ทั้งหมด ฉบับจัดใหม่ให้ชัดที่สุด และใช้เป็น source of truth ระดับโครงสร้าง

---

## 1. Project Vision

โปรเจกต์นี้คือ **portable image-build pipeline สำหรับ OpenStack**  
หน้าที่คือ:
1. ค้นหาและ/หรือดาวน์โหลด base image จาก official upstream
2. import เข้า Glance เป็น base image
3. สร้าง boot volume จาก base image
4. สร้าง VM จาก volume
5. เข้าไป configure guest OS
6. clean guest และ poweroff
7. upload volume กลับขึ้นเป็น final image
8. cleanup resource ที่เหลือ
9. เขียน state, logs, manifests เพื่อให้เมนู, AI, และผู้ใช้ตามงานต่อได้

---

## 2. Core Design Principles

### 2.1 Portable / Local-first
- ระบบต้องไม่ผูกกับ jump host
- รันได้จากเครื่อง Linux/Bash ทั่วไป
- พัฒนา/เทสผ่าน VS Code + Git Bash ได้
- ไม่ใช่ระบบ “push code ไป host กลางแล้วค่อยรัน”

### 2.2 One obvious entrypoint
- ผู้ใช้เรียกแค่ `scripts/control.sh`
- ภายในค่อย dispatch ไป menu หรือ phase commands
- หลีกเลี่ยงหลาย entrypoint จนงงว่าไฟล์ไหนคือของจริง

### 2.3 Config minimal but explicit
- `openrc` ไม่เก็บใน repo
- settings ที่ user ต้องมีจริงมีให้น้อยที่สุด แต่ต้องชัด
- ใช้ `settings/openstack.env` เป็น OpenStack settings ชุดเดียว
- ใช้ `settings/guest-access.env` เป็น guest access settings
- tracked config อยู่ใต้ `config/`

### 2.4 Input = `.env`, Output = `.json`
- ไฟล์ต้นทางที่ phase อ่าน = `.env`
- runtime result/manifests = `.json`
- quick status = flag files

### 2.5 Phase-oriented architecture
Phase หลัก:
- sync_download
- import
- create
- configure
- clean
- publish

### 2.6 AI-friendly / repairable
- ทุก phase ต้องมี log ชัด
- ทุก phase ต้องมี runtime JSON
- ทุก phase ควรมี flags
- เมื่อ fail ต้องรู้ว่า fail ที่ phase ไหน command ไหน
- เพื่อให้เอา log ไปให้ AI วิเคราะห์ได้

---

## 3. Things this project is explicitly NOT

ระบบนี้ **ไม่ใช่**:
- jump host centric system
- deploy/local based system
- multi-root config layout ที่หาความจริงไม่เจอ
- system ที่ต้อง sync git ไป remote host ก่อนทุกครั้ง
- system ที่ต้องแก้ shell script มือหลายจุดโดยไม่มี menu หรือ state

---

## 4. Final Project Structure

```text
scripts/
└── control.sh                     # entrypoint หลักที่ผู้ใช้เรียก

lib/
├── core_paths.sh                  # path constants / repo root / canonical directories
├── common_utils.sh                # logging, retry, timeout, json/state helpers, ssh wrappers
├── openstack_api.sh               # wrappers ของ openstack/cinder/glance/nova operations
├── config_store.sh                # load/save config files
└── state_store.sh                 # read/write flag files and runtime json paths

phases/
├── sync_download.sh               # discover / dry-run / download base image
├── import_base.sh                 # local image -> glance base image
├── create_vm.sh                   # base image -> volume -> server
├── configure_guest.sh             # ssh เข้า guest แล้ว configure OS
├── clean_guest.sh                 # final clean + poweroff
└── publish_final.sh               # delete server -> upload volume to final image -> cleanup

config/
├── defaults.env                   # tracked defaults ที่ไม่เป็นความลับ
├── os/
│   ├── ubuntu/sync.env
│   ├── debian/sync.env
│   ├── rocky/sync.env
│   ├── almalinux/sync.env
│   └── fedora/sync.env
└── guest/
    ├── ubuntu/
    │   ├── default.env
    │   ├── 22.04.env
    │   └── 24.04.env
    ├── debian/
    │   ├── default.env
    │   └── 12.env
    ├── rocky/
    │   ├── default.env
    │   └── 9.env
    ├── almalinux/
    │   ├── default.env
    │   └── 9.env
    └── fedora/
        ├── default.env
        └── 40.env

settings/
├── openstack.env                  # user-selected project/network/flavor/... (untracked)
└── guest-access.env               # ssh/root/key/password settings (untracked)

workspace/
└── images/
    ├── ubuntu/
    ├── debian/
    ├── rocky/
    ├── almalinux/
    └── fedora/

runtime/
├── state/
│   ├── sync/
│   ├── import/
│   ├── create/
│   ├── configure/
│   ├── clean/
│   └── publish/
└── logs/
    ├── sync/
    ├── import/
    ├── create/
    ├── configure/
    ├── clean/
    └── publish/
```

---

## 5. Canonical Path Model

`lib/core_paths.sh` ต้องเป็น single source of truth สำหรับ path ทั้งหมด

ควร export:
- `ROOT_DIR`
- `SCRIPTS_DIR`
- `LIB_DIR`
- `PHASES_DIR`
- `CONFIG_DIR`
- `SETTINGS_DIR`
- `WORKSPACE_DIR`
- `IMAGES_DIR`
- `RUNTIME_DIR`
- `STATE_DIR`
- `LOG_DIR`

### Responsibilities
- หา repo root ให้เสถียร
- ให้ phase ทุกตัว source ไฟล์นี้
- ไม่ให้มี `../../..` กระจัดกระจาย
- สร้าง dir ที่จำเป็นได้
- คืน path ของ state/log/json แบบมาตรฐาน

---

## 6. Entry and Control Model

### Only visible entrypoint
```text
scripts/control.sh
```

### Responsibilities of `scripts/control.sh`
- load `core_paths.sh`
- load `common_utils.sh`
- load menu dispatch / command dispatch
- validate repo root
- ถ้าไม่มี args -> เปิด interactive menu
- ถ้ามี args -> รัน direct command mode

### Command model
ต้องรองรับทั้ง:
- interactive menu
- direct command mode

ตัวอย่าง:
```bash
scripts/control.sh
scripts/control.sh settings validate-auth
scripts/control.sh sync dry-run --os ubuntu --version 24.04
scripts/control.sh build import --os ubuntu --version 24.04
scripts/control.sh build all --os ubuntu --version 24.04
scripts/control.sh status dashboard
scripts/control.sh cleanup reconcile
```

---

## 7. Configuration Philosophy

### Tracked config
อยู่ใน `config/`
- เป็นกฎระบบ
- เป็น defaults
- ไม่ควรมีความลับ
- git track ได้

### Untracked settings
อยู่ใน `settings/`
- เป็นของผู้ใช้/ของ environment
- ไม่ track
- สร้างจาก template ได้
- menu สามารถเขียนให้ได้

### OpenRC
- ไม่เก็บใน repo
- ผู้ใช้ source เอง หรือ provide path ตอนรัน
- menu validate ได้ แต่ไม่ควร persist secret ใน repo

---

## 8. Runtime Model

ทุก phase ควรเขียน:
1. log file
2. runtime JSON
3. quick state flag

### Example
```text
runtime/logs/sync/ubuntu-24.04.log
runtime/state/sync/ubuntu-24.04.json
runtime/state/sync/ubuntu-24.04.ready
```

---

## 9. Build Pipeline Overview

1. Preflight / Auth
2. Sync / Discover
3. Import Base Image
4. Create Boot Volume
5. Create Server from Volume
6. Configure Guest
7. Final Clean + Poweroff
8. Delete Server / Wait Volume Available
9. Upload Final Image from Volume
10. Delete Volume
11. Delete Base Image
12. Final State Write

---

## 10. What to keep from the old repo

เก็บ:
- แนวคิด path layer
- auto-init settings/templates
- phase-based execution
- CI baseline
- runtime state concept
- cleanup / resume / status as user features

ไม่เก็บ:
- jump host flow
- git bootstrap/sync to remote
- `deploy/local/*`
- control wrapper ที่ผูก remote host
- file naming และ config layering ที่ทำให้สับสน

---

## 11. First milestone

Milestone แรกที่ต้องทำให้สำเร็จคือ:

### `sync_download`
อย่างน้อยต้อง:
- อ่าน `config/os/<os>/sync.env`
- dry-run ได้
- discover image target ได้
- เขียน runtime JSON + flags ได้
- แสดง candidate / URL / checksum ได้
- download จริง optional แต่โครงต้องพร้อม

เหตุผล:
- เป็น phase ที่ไม่แตะ OpenStack หนัก
- ทดสอบได้ง่าย
- validate architecture ใหม่ได้เร็ว

---

## 12. Definition of Done (Round 1)

ระบบรอบแรกถือว่า “เริ่มใช้ได้จริง” เมื่อ:
- `scripts/control.sh` เปิด menu ได้
- Settings เลือก project/network/flavor ได้
- Sync dry-run ทำงานได้
- import/create/configure/publish มี skeleton พร้อม state/log
- runtime JSON ถูกเขียนจริง
- cleanup/reconcile มีอย่างน้อยระดับพื้นฐาน
- ไม่มี jump host dependency

---

## 13. Guiding style for implementation

- Bash-first
- phase small and composable
- use helpers instead of copy-paste
- log every major action
- never wait silently on long operations
- every long operation must have timeout + last status
- every user-facing action should be resumable or diagnosable
