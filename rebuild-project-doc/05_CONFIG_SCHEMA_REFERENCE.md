ใช้ **2 ชั้นสำหรับ input config** และ **1 ชั้นสำหรับ runtime result**

### Input config

* `config/guest/<os>/default.env`
* `config/guest/<os>/<version>.env`

### Runtime result

* `runtime/state/configure/<os>-<version>.json`
* `runtime/state/configure/<os>-<version>.<flag>`

สรุปสั้น ๆ คือ:

* **`.env`** ใช้กับไฟล์ที่ระบบต้อง `source` เพื่อเอาค่าไปทำงาน
* **`.json`** ใช้กับไฟล์ผลลัพธ์ที่ระบบเขียนออกมา
* **flag files** ใช้เช็กสถานะเร็ว

นี่คือแบบที่เหมาะสุดกับ Bash, เหมาะกับ loop ที่คุณจะเอา log ไปให้ AI วิเคราะห์, และไม่ทำให้ config มั่ว

---

# ภาพรวม schema ที่ผมแนะนำ

## 1) Guest Input Config Schema

อันนี้คือ schema ของไฟล์:

```text
config/guest/<os>/default.env
config/guest/<os>/<version>.env
```

ผมแนะนำให้ใช้ schema แบบ “section-based env” คือมีคีย์แบ่งเป็นหมวดชัดเจน ไม่ใช่โยนทุกอย่างรวมกันมั่ว ๆ

หมวดที่ควรมีคือ:

1. Identity
2. Repo / OLS policy
3. Update / Reboot policy
4. Access / SSH policy
5. System defaults
6. Final clean policy
7. Validation policy

---

# 2) หลักการแบ่งว่าอะไรอยู่ `default.env` และอะไรอยู่ `<version>.env`

## อยู่ใน `default.env`

สิ่งที่เป็น policy กลางของ OS family นั้น เช่น Ubuntu ทั้งตระกูลควรใช้คล้ายกัน

ตัวอย่าง:

* เปิด root SSH หรือไม่
* locale
* timezone
* cloud-init defaults
* disable auto update
* disable MOTD news
* firewall policy
* DNS policy
* OLS failover policy
* final clean policy
* reboot policy
* kernel keep policy

## อยู่ใน `<version>.env`

สิ่งที่ต่างเพราะ version นี้เท่านั้น

ตัวอย่าง:

* `OS_VERSION`
* `OS_CODENAME`
* repo layout
* ใช้ `sources.list` หรือ `deb822`
* suites ของ apt
* OLS path ของรุ่นนี้
* workaround เฉพาะรุ่น
* package manager behavior เฉพาะรุ่น

กฎง่าย ๆ คือ:

> ถ้าค่านี้ควรเหมือนกันเกือบทุก version ของ OS นั้น → ไป `default.env`
> ถ้าค่านี้เปลี่ยนตาม version → ไป `<version>.env`

---

# 3) Schema ที่ผมแนะนำจริง ๆ

## A. `default.env` schema

อันนี้คือ “schema กลาง” ที่ผมคิดว่าดีที่สุดสำหรับเริ่มต้น

```bash
# =========================
# Identity
# =========================
OS_FAMILY="ubuntu"

# =========================
# Repo / OLS Policy
# =========================
OLS_ENABLED="yes"
OLS_FAILOVER_TO_OFFICIAL="yes"
OLS_BASE_URL="http://mirrors.openlandscape.cloud"
REPO_BACKUP_MODE="full"

# apt: auto | list | deb822
APT_SOURCE_MODE="auto"

# dnf/yum: auto | mirrorlist_to_baseurl
DNF_REPO_MODE="auto"

# =========================
# Update / Reboot Policy
# =========================
RUN_UPDATE="yes"
RUN_UPGRADE="yes"
REBOOT_AFTER_UPGRADE="yes"
KERNEL_KEEP="2"

# =========================
# Access / SSH Policy
# =========================
ENABLE_ROOT_SSH="yes"
SSH_PERMIT_ROOT_LOGIN="yes"
SSH_PASSWORD_AUTH="yes"
SSH_PUBKEY_AUTH="yes"
SET_ROOT_PASSWORD="yes"
INSTALL_PER_INSTANCE_ROOT_KEY_SCRIPT="yes"
KEEP_PER_INSTANCE_SCRIPT_ON_CLEAN="yes"

# =========================
# Locale / Timezone / Cloud-init
# =========================
ENABLE_LOCALE_SETUP="yes"
LOCALES="en_US.UTF-8 th_TH.UTF-8"
DEFAULT_LANG="en_US.UTF-8"
TIMEZONE="Asia/Bangkok"

CLOUD_INIT_PRESERVE_HOSTNAME="false"
CLOUD_INIT_MANAGE_ETC_HOSTS="true"
CLOUD_INIT_DISABLE_ROOT="false"

# =========================
# System Behavior Policy
# =========================
DISABLE_AUTO_UPDATE="yes"
DISABLE_MOTD_NEWS="yes"
DISABLE_GUEST_FIREWALL="yes"

# dhcp | static
DNS_MODE="dhcp"

# =========================
# Final Clean Policy
# =========================
RUN_FINAL_CLEAN="yes"
CLOUD_INIT_CLEAN="yes"
RESET_MACHINE_ID="yes"
REMOVE_HOST_KEYS="yes"
CLEAR_PACKAGE_CACHE="yes"
CLEAR_HISTORY="yes"
CLEAR_LOGS="yes"
CLEAR_TMP="yes"
REMOVE_BUILD_AUTH_KEYS="yes"
POWEROFF_AFTER_CONFIGURE="yes"

# =========================
# Validation Policy
# =========================
VALIDATE_REPO_AFTER_CONFIGURE="yes"
VALIDATE_ROOT_ACCESS="yes"
VALIDATE_NETWORK="yes"
VALIDATE_PACKAGE_MANAGER="yes"
```

---

## B. `<version>.env` schema

อันนี้คือ schema ของไฟล์เฉพาะ version

```bash
# =========================
# Identity
# =========================
OS_VERSION="24.04"
OS_CODENAME="noble"

# =========================
# Repo / OLS Layout
# =========================
REPO_FAMILY="apt"

# apt source format: list | deb822
APT_SOURCE_MODE="deb822"

APT_SUITES="noble noble-updates noble-security noble-backports"
APT_COMPONENTS="main restricted universe multiverse"

# official upstream
APT_OFFICIAL_URIS="http://archive.ubuntu.com/ubuntu http://security.ubuntu.com/ubuntu"

# OLS path for this version
OLS_REPO_PATH="/ubuntu"

# =========================
# Version-specific Behavior
# =========================
KERNEL_PACKAGE_PATTERN="linux-image-*"

# optional workarounds
ENABLE_VERSION_WORKAROUND="no"
VERSION_WORKAROUND_NOTE=""
```

---

# 4) ทำไม schema นี้ดีที่สุด

ผมเลือกแบบนี้เพราะมันบาลานซ์ 4 อย่างพร้อมกัน:

## 1. อ่านง่าย

เปิดไฟล์มาก็รู้เลยว่า config นี้พูดเรื่องอะไรบ้าง

## 2. source ใน Bash ง่าย

ไม่ต้อง parse JSON ตอนโหลด config

## 3. แยก default กับ version ได้จริง

ไม่ปนกันจนดูไม่ออกว่าอะไรเป็น policy กลาง อะไรเป็น override

## 4. AI เขียน/แก้ได้ง่าย

AI สามารถ:

* อ่าน default
* อ่าน version
* เห็น key ที่ขาด
* generate override ใหม่ได้ตรงมาก

---

# 5) สิ่งที่ “ไม่ควรทำ”

ผมไม่แนะนำแบบนี้

## ไม่ควรใส่ทุกอย่างไว้ไฟล์เดียว

เช่น `ubuntu-24.04.env` ไฟล์เดียวจบ
เพราะพอมีหลาย version แล้วจะซ้ำกันเยอะมาก และแก้ยาก

## ไม่ควรใช้ JSON เป็น input config ตอนนี้

เพราะ pipeline เป็น Bash-heavy
ถ้าใช้ JSON เป็น input:

* parse ยุ่ง
* merge default/version ยุ่ง
* dependency เพิ่ม
* AI อาจ generate แล้ว shell ใช้ลำบาก

## ไม่ควรมี field เยอะเกินตั้งแต่วันแรก

ควรเริ่มด้วย schema v1 ที่ “พอใช้จริง” ก่อน
แล้วค่อยเพิ่ม field ตอนเจอ use case ใหม่

---

# 6) Runtime JSON Schema ที่ควรใช้คู่กัน

อันนี้ไม่ใช่ input config แต่เป็นไฟล์ผลลัพธ์ที่ระบบเขียนหลัง configure

ไฟล์:

```text
runtime/state/configure/<os>-<version>.json
```

ผมแนะนำ schema แบบนี้:

```json
{
  "os_family": "ubuntu",
  "os_version": "24.04",
  "config_default_file": "config/guest/ubuntu/default.env",
  "config_version_file": "config/guest/ubuntu/24.04.env",
  "effective_config": {
    "OLS_ENABLED": "yes",
    "OLS_FAILOVER_TO_OFFICIAL": "yes",
    "APT_SOURCE_MODE": "deb822",
    "TIMEZONE": "Asia/Bangkok"
  },
  "repo_mode_used": "ols",
  "phase_status": {
    "resolve_config": "ok",
    "guest_preflight": "ok",
    "baseline_official": "ok",
    "repo_backup": "ok",
    "ols_injection": "ok",
    "ols_validation": "ok",
    "update_upgrade": "ok",
    "reboot_reconnect": "ok",
    "kernel_cleanup": "ok",
    "access_policy": "ok",
    "system_policy": "ok",
    "repo_revalidation": "ok",
    "final_clean": "ok",
    "final_validation": "ok",
    "shutdown": "ok"
  },
  "final_status": "ready",
  "failure_phase": "",
  "failure_reason": "",
  "log_path": "runtime/logs/configure/ubuntu-24.04.log",
  "started_at": "2026-03-22T10:00:00Z",
  "finished_at": "2026-03-22T10:12:00Z"
}
```

นี่จะมีประโยชน์มากกับเมนูในอนาคต และกับ loop ที่คุณจะเอา log/ผลลัพธ์ไปให้ AI วิเคราะห์

---

# 7) ลำดับ phase ที่ schema นี้รองรับ

schema ที่ผมเสนอถูกออกแบบให้รองรับ phase ที่เราตกลงไว้พอดี

## Phase 0 — Resolve Config

ใช้:

* `default.env`
* `<version>.env`

ผลลัพธ์:

* effective config snapshot ใน JSON

## Phase 1 — Guest Detect & Preflight

ใช้:

* `OS_FAMILY`
* `OS_VERSION`
* `REPO_FAMILY`
* `APT_SOURCE_MODE`
* validation flags

## Phase 2 — Baseline Official Repo Test

ใช้:

* `REPO_FAMILY`
* official repo behavior ของ version นั้น

## Phase 3 — Repo Backup Snapshot

ใช้:

* `APT_SOURCE_MODE`
* `REPO_BACKUP_MODE`
* `DNF_REPO_MODE`

## Phase 4 — OLS Mirror Injection

ใช้:

* `OLS_ENABLED`
* `OLS_BASE_URL`
* `OLS_REPO_PATH`
* `APT_SOURCE_MODE`

## Phase 5 — OLS Validation

ใช้:

* `OLS_FAILOVER_TO_OFFICIAL`
* package manager family

## Phase 6 — Rollback to Official

ใช้:

* `OLS_FAILOVER_TO_OFFICIAL`
* backup mode

## Phase 7 — Update / Upgrade

ใช้:

* `RUN_UPDATE`
* `RUN_UPGRADE`

## Phase 8 — Reboot & Reconnect

ใช้:

* `REBOOT_AFTER_UPGRADE`

## Phase 9 — Kernel Cleanup

ใช้:

* `KERNEL_KEEP`
* `KERNEL_PACKAGE_PATTERN`

## Phase 10 — Access & Root SSH Policy

ใช้:

* `ENABLE_ROOT_SSH`
* `SSH_PERMIT_ROOT_LOGIN`
* `SSH_PASSWORD_AUTH`
* `SSH_PUBKEY_AUTH`
* `SET_ROOT_PASSWORD`
* `INSTALL_PER_INSTANCE_ROOT_KEY_SCRIPT`

## Phase 11 — Locale / Timezone / Cloud-init

ใช้:

* `LOCALES`
* `DEFAULT_LANG`
* `TIMEZONE`
* `CLOUD_INIT_*`

## Phase 12 — System Behavior Policy

ใช้:

* `DISABLE_AUTO_UPDATE`
* `DISABLE_MOTD_NEWS`
* `DISABLE_GUEST_FIREWALL`
* `DNS_MODE`

## Phase 13 — Repo Re-Validation

ใช้:

* `VALIDATE_REPO_AFTER_CONFIGURE`

## Phase 14 — Final Clean

ใช้:

* `RUN_FINAL_CLEAN`
* `CLOUD_INIT_CLEAN`
* `RESET_MACHINE_ID`
* `REMOVE_HOST_KEYS`
* `CLEAR_PACKAGE_CACHE`
* `CLEAR_HISTORY`
* `CLEAR_LOGS`
* `CLEAR_TMP`
* `REMOVE_BUILD_AUTH_KEYS`

## Phase 15 — Final Validation

ใช้:

* `VALIDATE_ROOT_ACCESS`
* `VALIDATE_NETWORK`
* `VALIDATE_PACKAGE_MANAGER`

## Phase 16 — Shutdown

ใช้:

* `POWEROFF_AFTER_CONFIGURE`

---

# 8) ผมขอเสนอ schema v1 แบบ “เริ่มใช้งานได้จริงก่อน”

ถ้าจะให้ practical ที่สุด ผมแนะนำเริ่มด้วย field ชุดนี้ก่อน

## `default.env` ขั้นต่ำที่ควรมี

```bash
OS_FAMILY=""
OLS_ENABLED="yes"
OLS_FAILOVER_TO_OFFICIAL="yes"
OLS_BASE_URL="http://mirrors.openlandscape.cloud"
RUN_UPDATE="yes"
RUN_UPGRADE="yes"
REBOOT_AFTER_UPGRADE="yes"
KERNEL_KEEP="2"
ENABLE_ROOT_SSH="yes"
SSH_PERMIT_ROOT_LOGIN="yes"
SSH_PASSWORD_AUTH="yes"
SSH_PUBKEY_AUTH="yes"
SET_ROOT_PASSWORD="yes"
INSTALL_PER_INSTANCE_ROOT_KEY_SCRIPT="yes"
KEEP_PER_INSTANCE_SCRIPT_ON_CLEAN="yes"
LOCALES="en_US.UTF-8 th_TH.UTF-8"
DEFAULT_LANG="en_US.UTF-8"
TIMEZONE="Asia/Bangkok"
DISABLE_AUTO_UPDATE="yes"
DISABLE_MOTD_NEWS="yes"
DISABLE_GUEST_FIREWALL="yes"
DNS_MODE="dhcp"
RUN_FINAL_CLEAN="yes"
RESET_MACHINE_ID="yes"
REMOVE_HOST_KEYS="yes"
CLEAR_PACKAGE_CACHE="yes"
CLEAR_HISTORY="yes"
CLEAR_LOGS="yes"
CLEAR_TMP="yes"
REMOVE_BUILD_AUTH_KEYS="yes"
POWEROFF_AFTER_CONFIGURE="yes"
```

## `<version>.env` ขั้นต่ำที่ควรมี

```bash
OS_VERSION=""
OS_CODENAME=""
REPO_FAMILY=""
APT_SOURCE_MODE="auto"
APT_SUITES=""
APT_COMPONENTS=""
APT_OFFICIAL_URIS=""
OLS_REPO_PATH=""
KERNEL_PACKAGE_PATTERN=""
```

นี่เป็นชุดที่ “ไม่เยอะเกิน” แต่ “พอทำงานจริงได้”

---

# 9) คำตอบแบบฟันธง

ถ้าถามว่า schema แบบไหนดีที่สุดสำหรับตอนนี้

## คำตอบของผมคือ:

**ใช้ `.env` แบบ 2-layer สำหรับ input config**

* `config/guest/<os>/default.env`
* `config/guest/<os>/<version>.env`

และใช้ **`.json` สำหรับ runtime result**

* `runtime/state/configure/<os>-<version>.json`

นี่คือแบบที่:

* สะอาด
* ไม่มั่ว
* เข้ากับ Bash
* รองรับ AI loop
* โตต่อได้
* debug ง่าย

