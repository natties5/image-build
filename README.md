# image-build

ระบบ Pipeline อัตโนมัติสำหรับสร้างและเผยแพร่ OpenStack Image ของ Linux distributions ต่างๆ ทำงานผ่าน Jump Host

---

## Quick Start

### 1. เตรียม Local

```bash
# วาง SSH private key
deploy/local/ssh/id_jump

# ตั้งค่า SSH config
deploy/local/ssh_config

# ตั้งค่า jump host และ repo path
deploy/local/control.env        # JUMP_HOST_ADDR, JUMP_HOST_USER, JUMP_HOST_REPO_PATH
deploy/local/guest-access.env   # ROOT_USER, ROOT_PASSWORD, SSH_PORT
deploy/local/openstack.env      # NETWORK_ID, FLAVOR_ID, SECURITY_GROUP, ...
deploy/local/openrc.path        # OPENRC_FILE=/path/to/openrc
```

ดู template ได้ที่ `deploy/*.example` และ `config/credentials/guest-access.env.example`

### 2. รัน Controller

```bash
bash scripts/control.sh
```

เมนูหลัก: **SSH** → **Git** → **Pipeline** → **Exit**

### 3. ขั้นตอนแรก (ครั้งแรก)

```bash
bash scripts/control.sh git bootstrap      # เตรียม repo บน jump host
bash scripts/control.sh git sync-safe      # sync code ขึ้น jump host
```

### 4. รัน Pipeline

```bash
bash scripts/control.sh pipeline auto-by-os --os ubuntu
bash scripts/control.sh pipeline auto-by-os-version --os ubuntu --version 24.04
bash scripts/control.sh pipeline manual
```

---

## OS ที่รองรับ

| OS         | Download | Import | Configure | Publish |
|------------|:--------:|:------:|:---------:|:-------:|
| ubuntu     | ✓        | ✓      | ✓         | ✓       |
| debian     | ✓        | -      | -         | -       |
| rocky      | ✓        | -      | -         | -       |
| centos     | ✓        | -      | -         | -       |
| almalinux  | ✓        | -      | -         | -       |

---

## โครงสร้างโปรเจกต์

```
bin/imagectl.sh          ← entry point สำหรับรันบน jump host
scripts/control.sh       ← entry point สำหรับ operator บน local

phases/                  ← pipeline phase scripts (download, import, create, configure, clean, publish)
lib/                     ← shared library functions (รวมถึง core_paths.sh)

settings/                ← ข้อมูล configuration และ secrets ส่วนตัว (gitignored ทั้งหมด)
                         มีการจำลองไฟล์จาก *.example อัตโนมัติเมื่อรันครั้งแรก
├── openstack.env        ← OpenStack credentials
├── openrc.env           ← path ไปยัง openrc file
├── guest-access.env     ← ข้อมูลสำหรับเข้าถึง Guest VM
└── ...

config/                  ← tracked system defaults และ reusable rules

deploy/
├── local/               ← (Legacy) ย้ายไปใช้โฟลเดอร์ settings/ เป็นหลัก
└── *.example            ← template สำหรับการอ้างอิง

manifests/               ← runtime artifacts (gitignored ยกเว้น .gitkeep)
runtime/state/           ← state ของแต่ละ phase (gitignored)
logs/                    ← log files (gitignored)
cache/                   ← downloaded images (gitignored)
doc/                     ← เอกสารอธิบายระบบ (ภาษาไทย)
```

---

## เอกสาร

| ไฟล์ | เนื้อหา |
|------|---------|
| [doc/20260320-architecture-overview-th.md](doc/20260320-architecture-overview-th.md) | ภาพรวมระบบ |
| [doc/20260320-operator-guide-th.md](doc/20260320-operator-guide-th.md) | คู่มือ operator |
| [doc/20260320-config-layout-th.md](doc/20260320-config-layout-th.md) | โครงสร้าง config |
| [doc/20260320-jump-host-config-th.md](doc/20260320-jump-host-config-th.md) | การเตรียม jump host |
| [image-build-spec.md](image-build-spec.md) | Project specification (สรุปการออกแบบ) |
