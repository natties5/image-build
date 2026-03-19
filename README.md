# Image Build Control Panel

This repository is a VS Code-friendly, jump-host-driven image build framework.

## คู่มือภาษาไทย (Operator)

หัวข้อนี้อธิบายการใช้ `bash scripts/control.sh` แบบเป็นขั้นตอนจริง

### 1) เมนูหลักคืออะไร

เมื่อรัน:

```bash
bash scripts/control.sh
```

จะเจอ 4 เมนูหลัก:

- `SSH`
- `Git`
- `Pipeline`
- `Exit`

ความหมาย:

- `SSH`: จัดการการเชื่อมต่อไป jump host (เช็ค/เข้า shell)
- `Git`: จัดการโค้ดบน jump host (bootstrap/sync/status)
- `Pipeline`: รัน flow build image จริง
- `Exit`: ออกจากเมนู

### 2) เมนู SSH ใช้ทำอะไร

เมนูย่อย:

- `connect`: เข้า SSH ไป jump host แบบ interactive
- `validate`: ทดสอบว่า ssh non-interactive ใช้งานได้
- `info`: แสดง target/repo ที่ controller resolve แล้ว
- `back`: กลับเมนูหลัก

ใช้เมื่อไร:

- ก่อนเริ่มงานวันนั้น แนะนำกด `validate` 1 ครั้ง
- ถ้าต้อง debug ที่ jump host ให้ใช้ `connect`

### 3) เมนู Git ใช้ทำอะไร

เมนูย่อย:

- `bootstrap-remote-repo`: เตรียม repo บน jump host ถ้ายังไม่มี
- `sync-safe`: sync โค้ดแบบปลอดภัย (แนะนำใช้ทุกครั้งก่อนรัน pipeline)
- `sync-code-overwrite`: บังคับให้โค้ดตรง origin (destructive)
- `sync-clean`: ล้างโค้ด/artifact มากกว่าเดิม (destructive)
- `status`: ดู git status บน jump host
- `branch-info`: ดู branch/remote บน jump host
- `push`: push branch ปัจจุบันจาก jump host
- `back`

ลำดับแนะนำ:

1. เข้า `Git`
2. กด `sync-safe`
3. กด `status` ตรวจว่าพร้อม
4. ค่อยไป `Pipeline`

### 4) เมนู Pipeline ใช้ทำอะไร

เมนูย่อย:

- `Manual`
- `Auto by OS`
- `Auto by OS Version`
- `Status`
- `Logs`
- `Back`

ความหมาย:

- `Manual`: เลือก phase เองทีละขั้น
- `Auto by OS`: รันครบทุกเวอร์ชันที่ discover ได้ของ OS นั้น
- `Auto by OS Version`: รันครบ pipeline เฉพาะเวอร์ชันเดียว
- `Status`: สถานะ repo + log ล่าสุดบน jump host
- `Logs`: รายชื่อ log ล่าสุด

### 5) ลำดับใช้งานจริง (แนะนำ)

#### ลำดับรายวันแบบเร็วและปลอดภัย

1. `SSH -> validate`
2. `Git -> sync-safe`
3. `Pipeline -> Auto by OS Version -> ubuntu -> 24.04`
4. `Pipeline -> Status` และ `Pipeline -> Logs`

#### ถ้าต้องรันทุกเวอร์ชัน Ubuntu

1. `SSH -> validate`
2. `Git -> sync-safe`
3. `Pipeline -> Auto by OS -> ubuntu`
4. `Pipeline -> Status` และ `Pipeline -> Logs`

### 6) ใช้ Manual เมื่อไร

ใช้เมื่ออยากคุม phase เอง เช่นแก้เฉพาะบางช่วง

ลำดับ:

1. `Pipeline -> Manual`
2. เลือก `ubuntu`
3. Controller จะ run discover ก่อน
4. เลือกเวอร์ชันจาก manifest
5. เลือก action (`preflight/import/create/configure/clean/publish/status/logs`)

หมายเหตุ:

- เวอร์ชันจะมาจาก manifest ที่ discover ได้จริง
- ถ้าเวอร์ชันไม่อยู่ใน manifest จะไม่ให้รัน phase ที่ต้องใช้ version

### 7) คำสั่งตรง (ไม่เข้าเมนู)

```bash
bash scripts/control.sh ssh validate
bash scripts/control.sh git sync-safe
bash scripts/control.sh pipeline auto-by-os-version --os ubuntu --version 24.04
bash scripts/control.sh pipeline auto-by-os --os ubuntu
bash scripts/control.sh pipeline status
bash scripts/control.sh pipeline logs
```

### 8) สิ่งที่ควรรู้ก่อนรัน

- Ubuntu คือ flow ที่ implement จริง
- Debian/CentOS/AlmaLinux/Rocky เป็น skeleton
- `deploy/local/**` คือ local-only config
- controller จะ sync เฉพาะ runtime env ที่จำเป็น ไม่ copy ssh config/private key

## Primary Entrypoint

Use `scripts/control.sh` for operator workflows:

- `bash scripts/control.sh` (interactive main menu: SSH / Git / Pipeline / Exit)
- `bash scripts/control.sh ssh validate`
- `bash scripts/control.sh git bootstrap`
- `bash scripts/control.sh pipeline manual`
- `bash scripts/control.sh pipeline auto-by-os --os ubuntu`
- `bash scripts/control.sh pipeline auto-by-os-version --os ubuntu --version 24.04`

Compatibility aliases remain supported:

- `bash scripts/control.sh script manual`
- `bash scripts/control.sh script auto --os ubuntu --version 24.04`
- `bash scripts/control.sh auto --os ubuntu --version 24.04`

Legacy wrappers under `scripts/01..11_*.sh` and `bin/imagectl.sh` remain supported.

## Jump Host Configuration (Local Only)

1. Copy `deploy/control.env.example` to `deploy/local/control.env`.
2. Copy `deploy/ssh_config.example` to `deploy/local/ssh_config`.
3. Add private key at `deploy/local/ssh/id_jump`.
4. Set `EXPECTED_PROJECT_NAME` in `deploy/local/control.env` (or `deploy/local/openstack.env`) for preflight checks.
5. Optional local overrides:
   - `deploy/local/openstack.env`
   - `deploy/local/openrc.path`
   - `deploy/local/guest-access.env`
   - `deploy/local/publish.env`
   - `deploy/local/clean.env`

`deploy/local/**` is gitignored by default.

## SSH / Git / Pipeline Sections

- SSH:
  - `connect` opens a real SSH session to jump host.
  - `validate` checks non-interactive connectivity.
  - `info` prints resolved target and repo settings (no secrets).
- Git:
  - `bootstrap` prepares remote repo safely if missing/empty.
  - `sync-safe`, `sync-code-overwrite`, `sync-clean`.
  - `status`, `branch`, optional `push`.
- Pipeline:
  - `Manual`, `Auto by OS`, `Auto by OS Version`, `Status`, `Logs`.
  - Controller enforces discover first, then manifest-driven version choices.
  - Before mutating phases, controller validates local runtime config and syncs required `deploy/local/*.env` files to jump host repo at `deploy/local/`.

## Remote Runtime Config Sync

Controller syncs only required runtime env files (if present) from local repo to jump-host repo:

- `deploy/local/guest-access.env`
- `deploy/local/openstack.env`
- `deploy/local/openrc.path`
- `deploy/local/publish.env`
- `deploy/local/clean.env`

Never copied by controller:

- `deploy/local/ssh_config`
- `deploy/local/ssh/*` private keys

## Sync Modes

- `safe`: fetch + checkout + pull (non-destructive)
- `code-overwrite`: align tracked code with remote branch
- `clean`: overwrite code + clean runtime/work artifacts

Destructive sync modes require confirmation or `--yes`.

## OS Support

- Implemented: Ubuntu
- Skeleton only: Debian, CentOS, AlmaLinux, Rocky

Non-Ubuntu flows return a clear not-implemented message.
