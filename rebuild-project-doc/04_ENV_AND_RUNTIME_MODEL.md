
## 1) ไฟล์ต้นทางที่ระบบอ่านเพื่อทำงาน = `.env`

ใช้กับ config ทุกชนิดที่เป็น input ของระบบ เพราะโปรเจกต์นี้เป็น Bash-heavy และต้องการให้เรียกใช้/override ง่าย

ตัวอย่าง:

```text
config/os/<os>/sync.env
config/guest/<os>/default.env
config/guest/<os>/<version>.env
settings/openstack.env
settings/guest-access.env
```

เหตุผลที่ใช้ `.env`

* source ใน shell ได้ตรง ๆ
* override default → version ง่าย
* AI เขียนให้ได้ง่าย
* คนแก้มือก็ง่าย
* ไม่ต้องมี JSON parser มาเป็นภาระของ input config

---

## 2) ไฟล์ผลลัพธ์ตอน runtime = `.json`

ใช้สำหรับ manifest/state/result ที่ระบบเขียนออกมาหลังทำงาน

ตัวอย่าง:

```text
runtime/state/sync/ubuntu-24.04.json
runtime/state/configure/ubuntu-24.04.json
runtime/state/publish/ubuntu-24.04.json
```

เหตุผลที่ใช้ `.json`

* เก็บข้อมูลซ้อนกันได้
* เก็บ log path / fail step / repo mode / candidates / result ได้ครบ
* เมนูในอนาคตเอาไปอ่านต่อได้ง่าย
* AI เอาไปวิเคราะห์ต่อได้ดี

---

## 3) ไฟล์สถานะเร็ว = flag files

ใช้เช็ก state แบบเร็ว ๆ โดยไม่ต้องเปิด JSON

ตัวอย่าง:

```text
runtime/state/sync/ubuntu-24.04.dryrun-ok
runtime/state/sync/ubuntu-24.04.ready
runtime/state/sync/ubuntu-24.04.failed

runtime/state/configure/ubuntu-24.04.ready
runtime/state/configure/ubuntu-24.04.failed
```

บทบาทของ flag

* เมนูเช็กสถานะเร็ว
* shell logic ตัดสินใจเร็ว
* phase ถัดไปเช็กได้ง่าย

---

# สรุปเรื่อง Download Phase

## Input config

ใช้:

```text
config/os/<os>/sync.env
```

## Output runtime

ใช้:

```text
runtime/state/sync/<os>-<version>.json
runtime/state/sync/<os>-<version>.<flag>
runtime/logs/sync/<os>-<version>.log
```

## กติกาที่ล็อกแล้ว

* default = tracked versions only
* อนาคตค่อยมี `--discover-all`
* รองรับ `amd64/x86_64` ก่อน
* เลือก `.img` ก่อน ถ้าไม่มีค่อย `.qcow2`
* dry-run ต้อง:

  * แสดงผลหน้าจอ
  * เขียน state
  * เขียน manifest JSON
* ถ้าดาวน์โหลดจริง:

  * resume ได้
  * verify hash 100%
* ใช้ per-OS discovery rules
* checksum-first when possible
* HTML scraping ใช้เท่าที่จำเป็น

---

# สรุปเรื่อง Guest Configure Phase

## Input config

ใช้ `.env` เหมือนกัน โดยแยกเป็น 2 ชั้น

### 1) default ของแต่ละ OS

```text
config/guest/<os>/default.env
```

เช่น:

```text
config/guest/ubuntu/default.env
config/guest/debian/default.env
config/guest/rocky/default.env
```

นี่คือ baseline policy ของ OS นั้น

### 2) version-specific override

```text
config/guest/<os>/<version>.env
```

เช่น:

```text
config/guest/ubuntu/22.04.env
config/guest/ubuntu/24.04.env
config/guest/debian/12.env
```

นี่คือค่าที่แตกต่างเฉพาะ version

## Output runtime

```text
runtime/state/configure/<os>-<version>.json
runtime/state/configure/<os>-<version>.<flag>
runtime/logs/configure/<os>-<version>.log
```

---

# หลักการของ Guest Config

## `default.env`

เก็บ policy กลางของ OS family นั้น เช่น

* root SSH policy
* locale
* timezone
* cloud-init defaults
* disable auto update
* disable MOTD
* firewall policy
* DNS policy
* LEGACY_MIRROR fallback policy
* final clean policy

## `<version>.env`

เก็บสิ่งที่ต่างเฉพาะ version เช่น

* codename
* suites
* repo layout
* ใช้ `sources.list` หรือ `.sources`
* LEGACY_MIRROR path ของ version นี้
* workaround เฉพาะรุ่น
* behavior ของ package manager ที่ต่างจากรุ่นอื่น

---

# หลักการโหลด Guest Config

ตอน configure ระบบจะทำแบบนี้

1. โหลด `config/guest/<os>/default.env`
2. ถ้ามี `config/guest/<os>/<version>.env` ให้โหลดทับ
3. version file override default
4. ถ้ายังไม่มี version file:

   * สร้างต้นแบบจาก default ได้
   * ค่อยให้ AI/คนแก้ต่อ
5. run configure
6. เขียน runtime JSON + log + flags
7. ถ้าผ่าน:

   * ใช้ version config นั้นต่อ
   * และ promote ไปเป็น default ใหม่ได้
8. ถ้าพัง:

   * log ต้องบอกว่าพังที่ phase ไหน
   * คุณเอา log ไปให้ AI วิเคราะห์
   * AI สร้าง config ใหม่มาลองอีก

---

# Guest Configure Phase ที่ตกลงกันแล้ว

ลำดับ phase ของ `configure` คือแบบนี้

## Phase 0 — Resolve Config

* โหลด default.env
* โหลด version.env
* merge เป็น effective config
* เก็บ snapshot

## Phase 1 — Guest Detect & Preflight

* SSH ได้
* root ได้
* detect OS/version
* detect package manager
* DNS/network พร้อม
* ไม่มี package manager lock

## Phase 2 — Baseline Official Repo Test

* ใช้ official repo เดิมก่อน
* Ubuntu/Debian: `apt update`
* RHEL family: `dnf clean all` + `dnf makecache` หรือ `repolist`
* ถ้าพัง หยุดทันที

## Phase 3 — Repo Backup Snapshot

* backup repo files ก่อนแก้
* Ubuntu/Debian:

  * `sources.list`
  * `*.list`
  * `*.sources`
* RHEL:

  * `*.repo`

## Phase 4 — LEGACY_MIRROR Mirror Injection

* เปลี่ยน official → LEGACY_MIRROR
* Ubuntu/Debian รองรับทั้ง classic และ deb822 `.sources`
* RHEL family ปิด mirrorlist และตั้ง baseurl

## Phase 5 — LEGACY_MIRROR Validation

* clean cache
* test package metadata/update ใหม่
* ถ้าผ่าน ใช้ LEGACY_MIRROR ต่อ

## Phase 6 — Rollback to Official on LEGACY_MIRROR Failure

* restore backup
* clear cache
* validate official repo ซ้ำ
* ถ้า official กลับมาใช้ได้ → ไปต่อด้วย official
* ถ้ายังไม่ได้ → fail pipeline

## Phase 7 — Update / Upgrade

* Ubuntu/Debian: `apt update && apt upgrade -y`
* RHEL family: `dnf upgrade -y`

## Phase 8 — Reboot & Reconnect

* reboot
* รอ SSH กลับมา
* validate ว่าระบบยังโอเค

## Phase 9 — Kernel Cleanup

* ถ้ามากกว่า 2 kernel → cleanup ให้เหลือ 2

## Phase 10 — Access & Root SSH Policy

* PermitRootLogin yes
* PasswordAuthentication yes
* PubkeyAuthentication yes
* ตั้ง root password
* สร้าง per-instance authorized_keys script

## Phase 11 — Locale / Timezone / Cloud-init Policy

* locale
* timezone
* cloud-init behavior

## Phase 12 — System Behavior Policy

* ปิด auto update
* ปิด MOTD news
* ปิด guest firewall
* ไม่ fix DNS ใน guest

## Phase 13 — Repo State Re-Validation

* เช็กว่า repo state ยังดี
* apt/dnf ยังใช้งานได้

## Phase 14 — Final Clean

* cloud-init clean
* clear package cache
* clear history
* clear temp/log
* reset machine-id
* remove SSH host keys
* keep per-instance script
* remove build-time authorized_keys

## Phase 15 — Final Validation

* root access OK
* repo state OK
* package manager OK
* per-instance script ยังอยู่
* locale/timezone OK
* network OK

## Phase 16 — Shutdown

* poweroff

---

# เรื่อง `deb822 .sources` ที่คุยกัน

อันนี้คือ format repo แบบใหม่ของ APT ที่ใช้ไฟล์ `.sources` แทน `sources.list` แบบเก่า

สรุปที่ตกลงกันแล้วคือ:

* ต้องรองรับทั้ง

  * `/etc/apt/sources.list`
  * `/etc/apt/sources.list.d/*.list`
  * `/etc/apt/sources.list.d/*.sources`

เพราะถ้ารองรับแค่ `sources.list` อย่างเดียว จะเจอ image บางตัวที่เหมือนแก้ repo แล้ว แต่จริง ๆ apt ยังใช้อีก format อยู่

---

# Promotion Flow ที่ตกลงกันแล้ว

คุณต้องการระบบแบบนี้

1. มี `default.env` ของแต่ละ OS
2. version ใหม่มา → ใช้ default เป็นฐาน
3. AI ช่วยสร้าง `<version>.env`
4. คุณเอาไปเทสจริง
5. ถ้าพัง:

   * เก็บ log
   * ส่ง log ให้ AI
   * AI สร้าง config ใหม่
6. ถ้าผ่าน:

   * เก็บ version config เป็น validated config
   * และ promote ไปเป็น `default.env` ใหม่ของ OS นั้นได้

พูดอีกแบบ:

* `default.env` = baseline ล่าสุดที่เชื่อถือได้ของ OS
* `<version>.env` = override เฉพาะ version
* AI loop = ใช้ log เพื่อปรับ config จนผ่าน

---

# กติกากลางของทั้งโปรเจกต์ตอนนี้

สรุปให้สั้นและตายตัวอีกครั้ง

## Input config

ใช้ `.env`

```text
config/os/<os>/sync.env
config/guest/<os>/default.env
config/guest/<os>/<version>.env
settings/openstack.env
settings/guest-access.env
```

## Runtime result

ใช้ `.json`

```text
runtime/state/sync/<os>-<version>.json
runtime/state/configure/<os>-<version>.json
runtime/state/publish/<os>-<version>.json
```

## Quick state

ใช้ flag files

```text
runtime/state/<phase>/<os>-<version>.ready
runtime/state/<phase>/<os>-<version>.failed
```

---

