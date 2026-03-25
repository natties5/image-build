ได้ครับ ผมสรุป “ระบบ Guest OS Config + Versioned Config + Phase การทำงาน” ใหม่ทั้งหมดแบบละเอียดมาก และยึดตามสิ่งที่คุณล็อกไว้ล่าสุด

---

# ภาพรวมที่คุณต้องการจริง

คุณต้องการระบบ configure Guest OS ที่เป็นระบบ และขยายต่อได้ในอนาคต โดยมีหลักคิดแบบนี้

1. แยก config ตาม **OS** และ **version**
2. มี **default config ของแต่ละ OS** เป็นแม่แบบ
3. มี **config เฉพาะ version** ที่ใช้ override default
4. ใช้ AI ช่วยสร้าง/แก้ config สำหรับ version ใหม่
5. คุณเอา config นั้นไปทดสอบเองกับ pipeline จริง
6. ถ้าพัง ระบบต้องมี log ชัดว่าพังตรงไหน
7. คุณเอา log กลับไปให้ AI วิเคราะห์
8. AI สร้าง config ใหม่ให้
9. ทดสอบใหม่
10. เมื่อผ่านแล้ว:

* เก็บเป็น version config ที่เชื่อถือได้
* และสามารถ promote ขึ้นไปเป็น default ใหม่ของ OS นั้นได้

สรุปสั้นที่สุดคือ:

> คุณต้องการระบบ config ของ guest ที่ “เติบโตเองเป็นลูป” จาก default → version → test → fail/pass → improve → promote

และทั้งหมดนี้ต้องสอดคล้องกับ pipeline ที่คุณกำลังจะสร้างใหม่:

* portable
* ไม่พึ่ง jump host
* เมนูเป็นตัวกลาง
* config ไม่มั่ว
* โครงสร้างอ่านง่าย
* phase ชัด
* debug ง่าย

---

# เป้าหมายของส่วน Guest OS Configure

ส่วนนี้ไม่ได้มีหน้าที่แค่ “เข้า VM ไปติดตั้ง package”
แต่มันคือ phase ที่เปลี่ยน base VM ให้กลายเป็น image ที่พร้อมใช้งานและปลอดภัยพอสำหรับ capture/publish

สิ่งที่ phase นี้ต้องรับผิดชอบคือ

* ตรวจ guest ว่าพร้อมหรือไม่
* ตรวจ repo เดิมก่อน
* สลับไป LEGACY_MIRROR อย่างปลอดภัย
* ถ้า LEGACY_MIRROR พัง ให้ rollback กลับ official
* อัปเดตระบบ
* reboot ถ้าจำเป็น
* ตั้งค่าพื้นฐานของ guest
* ปรับ root/SSH/cloud-init ตาม policy
* clean เครื่องก่อน capture
* validate สุดท้ายก่อนส่งต่อ phase ถัดไป
* เขียนผลลัพธ์/state/log ให้คนและ AI ใช้ต่อได้

---

# โครงสร้าง config ที่ควรเป็น

ผมสรุปใหม่ให้เป็นแบบที่ไม่ซับซ้อนและโตต่อได้

```text
config/
└── guest/
    ├── ubuntu/
    │   ├── default.env
    │   ├── 22.04.env
    │   ├── 24.04.env
    │   └── ...
    ├── debian/
    │   ├── default.env
    │   ├── 12.env
    │   └── ...
    ├── rocky/
    │   ├── default.env
    │   ├── 8.env
    │   ├── 9.env
    │   └── ...
    ├── almalinux/
    │   ├── default.env
    │   ├── 8.env
    │   ├── 9.env
    │   └── ...
    └── fedora/
        ├── default.env
        ├── 39.env
        ├── 40.env
        └── ...
```

---

# แนวคิดของ `default.env`

`default.env` คือแม่แบบของ OS นั้น

ตัวอย่าง:

* `config/guest/ubuntu/default.env`
* `config/guest/debian/default.env`
* `config/guest/rocky/default.env`

หน้าที่ของไฟล์นี้คือเก็บ policy ที่ “ควรใช้เหมือนกันเกือบทุก version” ของ OS นั้น เช่น

* เปิด root SSH หรือไม่
* locale/timezone
* cloud-init policy
* auto update policy
* MOTD policy
* firewall policy
* LEGACY_MIRROR behavior พื้นฐาน
* final clean behavior
* kernel cleanup policy
* reboot policy
* DNS policy

พูดง่าย ๆ คือ:

> default = baseline policy ที่ OS ตระกูลนั้นควรใช้ร่วมกัน

---

# แนวคิดของ `<version>.env`

ไฟล์ราย version ใช้เก็บสิ่งที่แตกต่างจาก default

ตัวอย่าง:

* `config/guest/ubuntu/24.04.env`
* `config/guest/ubuntu/22.04.env`
* `config/guest/debian/12.env`

หน้าที่ของไฟล์นี้คือ override เฉพาะจุดที่ต่างตาม version เช่น

* codename
* suite
* repo layout
* LEGACY_MIRROR URL pattern
* package manager behavior เฉพาะรุ่น
* source file layout
* cloud-init behavior เฉพาะรุ่น
* clean logic ที่รุ่นนั้นต้องระวัง
* known workaround ของรุ่นนั้น

พูดง่าย ๆ คือ:

> version file = สิ่งที่เปลี่ยนจาก default เพราะ version นี้พิเศษ

---

# หลักการโหลด config

เวลา phase configure ทำงาน ควรโหลด config ตามลำดับนี้

1. โหลด `config/guest/<os>/default.env`
2. ถ้ามี `config/guest/<os>/<version>.env` ให้โหลดทับ
3. ค่าใน version file จะ override ค่าใน default
4. ถ้าไม่มี version file:

   * สามารถสร้าง template จาก default ได้
   * แล้วค่อยเอาไปให้ AI หรือคนปรับต่อ

นี่คือหลักสำคัญที่ทำให้ config ไม่ซ้ำซ้อน และยังยืดหยุ่น

---

# ทำไมแนวทางนี้ดี

แนวทางนี้มีข้อดีหลายข้อ

## 1) รองรับ version ใหม่ง่าย

เวลา version ใหม่มา ไม่ต้องเริ่มจากศูนย์
แค่ copy จาก default แล้วแก้เฉพาะส่วนที่ต่าง

## 2) debug ง่าย

รู้เลยว่าปัญหาเป็นที่:

* policy กลางของ OS
* หรือ behavior เฉพาะ version

## 3) ให้ AI ทำงานได้เป็นรอบ

AI สามารถ:

* อ่าน log
* อ่าน default
* อ่าน version file
* แล้ว generate override ใหม่มาให้ทดสอบได้

## 4) ทำ promotion ได้ชัด

ถ้า version ล่าสุดผ่านดีมาก
ก็ใช้ version นั้นเป็นฐานใหม่ของ default ได้

---

# Promotion Flow ที่คุณต้องการ

นี่คือส่วนสำคัญที่ผมเข้าใจว่าคุณต้องการจริง

## จุดเริ่ม

มี default ของ OS อยู่ก่อนแล้ว

ตัวอย่าง:

* Ubuntu default มาจาก Ubuntu 24 ที่ผ่าน
* Debian default มาจาก Debian 12 ที่ผ่าน

## เวลา version ใหม่มา

ตัวอย่างเช่น Ubuntu 26.04 มาในอนาคต

flow คือ:

1. ใช้ `config/guest/ubuntu/default.env` เป็นฐาน
2. generate `config/guest/ubuntu/26.04.env`
3. รัน test จริง
4. ถ้าพัง:

   * เก็บ log
   * ให้ AI วิเคราะห์
   * generate file ใหม่
   * ทดสอบซ้ำ
5. ถ้าผ่าน:

   * เก็บ `26.04.env` เป็น config ที่ใช้ได้จริง
   * ถ้าคุณต้องการ ก็ promote ขึ้นไปอัปเดต `default.env`

พูดอีกแบบคือ:

> version ใหม่ = เริ่มจาก default → ปรับเฉพาะส่วนต่าง → ทดสอบ → ถ้าผ่านค่อยยกระดับกลับไปที่ default

---

# ลูปการทำงานกับ AI ที่คุณวางไว้

ผมสรุปเป็นลูปให้แบบชัดที่สุด

## Loop จริงที่คุณจะใช้

1. AI เขียน config แยกตาม OS/version
2. คุณเอา config ไปวาง
3. คุณสั่ง run phase configure
4. ระบบรันจริง
5. ถ้า fail:

   * ระบบต้องบอกว่า fail ที่ phase ไหน
   * มี log ชัด
   * มี state/manifest ชัด
6. คุณเอา log กลับไปให้ AI
7. AI วิเคราะห์และ generate config ใหม่
8. วนทดสอบอีกครั้ง
9. เมื่อผ่าน:

   * ใช้ version config นั้นต่อ
   * หรือ promote ไปเป็น default ของ OS นั้น

นี่เป็น workflow ที่ดีมากสำหรับโปรเจกต์แนวนี้ เพราะ upstream และ guest behavior มักมี edge case เยอะ

---

# สิ่งที่ระบบต้องมีเพื่อรองรับ loop นี้

เพื่อให้ลูปนี้ทำงานได้จริง ระบบต้องมี 3 อย่างหลัก

## 1) Config model ที่ชัด

ต้องรู้ว่าค่าไหนมาจาก:

* default
* version
* runtime settings

## 2) Log ที่อ่านง่าย

ต้องบอกได้ว่า:

* พังตอน baseline official test
* พังตอน LEGACY_MIRROR injection
* พังตอน apt update หลังสลับ LEGACY_MIRROR
* พังตอน reboot
* พังตอน final clean
* พังตอน final validation

## 3) State/manifest ที่ชัด

ต้องมีผลลัพธ์ของแต่ละ run เช่น:

* OS
* version
* config file ที่ใช้
* state สุดท้าย
* fail step
* log path
* เวลา run

---

# สิ่งที่อยู่ใน Guest Config

ตอนนี้จากสิ่งที่คุณคุยมา guest config ควรครอบคลุมหัวข้อเหล่านี้

## Common Policy

* update / upgrade
* reboot
* kernel cleanup
* root SSH policy
* root password / key policy
* per-instance authorized_keys script
* locale
* timezone
* cloud-init behavior
* disable auto update
* disable MOTD news
* disable firewall in guest
* ไม่ fix DNS ใน guest
* ให้ DHCP/subnet แจก DNS เอง

## Repo / LEGACY_MIRROR Policy

* baseline official repo test
* backup repo files
* LEGACY_MIRROR mirror injection
* LEGACY_MIRROR validation
* rollback ถ้า LEGACY_MIRROR fail
* ไปต่อด้วย official ถ้า rollback สำเร็จ

## Vault Fallback Policy (new)

ลำดับการเลือก repo: **official → LEGACY_MIRROR → vault → official-fallback → failed**

* vault ถูกเรียกเมื่อ:

  * official degraded ที่ ANY phase (ตรวจพบระหว่าง configure)
  * LEGACY_MIRROR fail และ rollback official ยังใช้ไม่ได้
* เมื่อ inject vault: validate ทันทีด้วย GUEST_VAULT_VALIDATION_COMMAND
* ถ้า vault fail ด้วย: STOP + เขียน .failed + log + VM ยังเปิดทิ้งไว้เพื่อตรวจสอบ

### Failure Behavior

ถ้าทุก repo mode ล้มเหลว (official + LEGACY_MIRROR + vault):

* **หยุดทันที** — ไม่ไปต่อ phase ถัดไป
* เขียน `runtime/state/configure/<os>-<version>.failed`
* บันทึก failure_phase และ failure_reason ลง JSON state
* **VM ยังเปิดค้างไว้** — เพื่อให้ตรวจสอบ log และ repo state ได้
* ไม่ poweroff อัตโนมัติ

### repo_mode_used / repo_mode_reason values

| repo_mode_used | repo_mode_reason | ความหมาย |
|---|---|---|
| `official` | `legacy_mirror_skip` | LEGACY_MIRROR ถูก disable |
| `ols` | `legacy_mirror_ok` | LEGACY_MIRROR ใช้ได้ปกติ |
| `vault` | `legacy_mirror_failed` | LEGACY_MIRROR fail → vault |
| `vault` | `official_degraded` | official degraded → vault |
| `official-fallback` | `legacy_mirror_failed` | LEGACY_MIRROR fail → rollback official สำเร็จ |
| `failed` | `all_repos_failed` | ทุก repo mode ล้มเหลว |

## Final Clean Policy

* cloud-init clean
* clear package cache
* clear history
* clear temp files
* clear logs
* reset machine-id
* remove ssh host keys
* keep per-instance script
* remove build-time authorized_keys
* poweroff

---

# โครงสร้างผลลัพธ์การรันที่ควรมี

เพื่อรองรับ loop การวิเคราะห์ด้วย AI ผมแนะนำให้มี output แบบนี้

```text
runtime/
├── logs/
│   └── configure/
│       ├── ubuntu-24.04-20260321.log
│       ├── ubuntu-24.04-20260321.summary.log
│       └── ...
└── state/
    └── configure/
        ├── ubuntu-24.04.json
        ├── ubuntu-24.04.failed
        ├── ubuntu-24.04.ready
        └── ...
```

---

# รูปแบบของ state/manifest ที่ควรมี

ไฟล์ JSON ต่อ run หรืออย่างน้อยต่อ OS/version ควรบอกข้อมูลประมาณนี้

* os_family
* version
* config_default_file
* config_version_file
* effective_config_snapshot
* repo_mode_used

  * official
  * ols
  * legacy-mirror-fallback-official
* current_phase
* final_status
* failure_reason
* log_path
* started_at
* finished_at

สิ่งนี้สำคัญมาก เพราะมันทำให้:

* คนอ่าน debug ได้
* เมนูแสดง status ได้
* AI เอาไปวิเคราะห์ได้

---

# Phase การทำงานแบบละเอียดมาก

ต่อไปคือ phase จริงของ `configure` ที่ผมสรุปใหม่ในลำดับที่เหมาะที่สุด

---

## Phase 0 — Resolve Config

ก่อนเข้า guest จริง ต้อง resolve config ที่จะใช้ให้ชัดก่อน

### สิ่งที่ต้องทำ

* รับ input ว่ากำลัง configure OS อะไร version อะไร
* โหลด `config/guest/<os>/default.env`
* โหลด `config/guest/<os>/<version>.env` ถ้ามี
* merge ให้ได้ effective config
* บันทึก effective config snapshot ลง runtime/state

### เป้าหมาย

* ให้รู้แน่ชัดว่ารอบนี้ใช้ config อะไร
* ป้องกันความงงว่าค่าไหนมาจากไหน

---

## Phase 1 — Guest Detect & Preflight

เป็น phase ตรวจความพร้อมก่อนแตะ repo หรือแก้ระบบ

### Checklist

* SSH เข้า VM ได้จริง
* ใช้ root ได้จริง
* detect OS family
* detect version
* detect package manager
* เช็ก network ออกได้
* เช็ก DNS ใช้งานได้
* เช็กไม่มี lock file ของ package manager
* เช็กคำสั่งพื้นฐานพร้อม

### ผลที่ควรได้

* รู้ว่าใช้ flow ไหน:

  * Ubuntu/Debian
  * RHEL family

### ถ้าพัง

* fail ทันที
* log ว่า guest preflight fail

---

## Phase 2 — Baseline Official Repo Test

phase นี้คือ “Test before Trust”

### Checklist

* ใช้ official repo เดิม
* Ubuntu/Debian:

  * `apt update`
* RHEL family:

  * `dnf clean all`
  * `dnf makecache` หรือ `dnf repolist`

### ถ้า fail

ให้ fail ทันที เพราะแปลว่า:

* network มีปัญหา
* DNS มีปัญหา
* guest มีปัญหา
* repo เดิมพังอยู่แล้ว

### หลักคิด

ถ้า official ยังใช้ไม่ได้
เราไม่ควรไปลอง LEGACY_MIRROR ต่อ เพราะจะทำให้สืบ root cause ยากขึ้น

---

## Phase 3 — Repo Backup Snapshot

ก่อนแตะ repo ต้อง backup เสมอ

### Ubuntu/Debian

backup:

* `/etc/apt/sources.list`
* `/etc/apt/sources.list.d/*.list`
* `/etc/apt/sources.list.d/*.sources`

### RHEL family

backup:

* `/etc/yum.repos.d/*.repo`

### สิ่งสำคัญ

* backup ต้อง restore ได้จริง
* ไม่ใช่ backup แค่บางไฟล์
* ต้องมีที่เก็บชัดเจน
* ต้อง log path ของ backup

---

## Phase 4 — LEGACY_MIRROR Mirror Injection

phase นี้คือเปลี่ยนจาก official ไป LEGACY_MIRROR แบบมี control

### Ubuntu/Debian

รองรับทั้ง:

* `sources.list`
* `*.list`
* `*.sources` แบบ deb822

### ถ้าเป็น `.list`/`sources.list`

* เปลี่ยน URL official → LEGACY_MIRROR

### ถ้าเป็น `.sources`

* แก้ field `URIs:`
* คง `Suites`, `Components`, `Signed-By` ให้ถูก

### RHEL family

* ปิด `mirrorlist=`
* เปิดหรือกำหนด `baseurl=`
* ชี้ไป LEGACY_MIRROR
* ทำกับทุก section อย่างระวัง

### สิ่งที่ต้องระวัง

* sed กว้างเกินจนพัง syntax
* แก้ไม่ครบทุกไฟล์
* official/LEGACY_MIRROR ปนกันแบบงง
* comment state พัง
* repo ที่ไม่ควรแตะโดนแก้ไปด้วย

---

## Phase 5 — LEGACY_MIRROR Validation

หลัง inject แล้วต้อง validate ทันที

### Ubuntu/Debian

* `apt clean`
* clear apt lists/cache ตามเหมาะสม
* `apt update`

### RHEL family

* `dnf clean all`
* `dnf makecache`
* หรือ `dnf repolist`

### ถ้า validation ผ่าน

* ใช้ LEGACY_MIRROR ต่อ
* log ว่า repo mode = LEGACY_MIRROR

### ถ้า validation ไม่ผ่าน

* เข้าสู่ phase rollback

---

## Phase 6 — Rollback to Official on LEGACY_MIRROR Failure

phase นี้เป็นหัวใจของ “เร็วแต่ไม่พัง”

### Checklist

* restore ไฟล์ repo จาก backup
* clear cache ใหม่
* รัน official validation ซ้ำ

### ถ้า official กลับมาใช้ได้

* ไปต่อด้วย official
* log ว่า repo mode = fallback-official

### ถ้า official ก็ยังพัง

* fail configure ทันที

### หลักคิด

LEGACY_MIRROR เป็น optimization
ไม่ใช่ dependency ที่ทำให้ pipeline ต้องพัง

---

## Phase 7 — Update / Upgrade

เมื่อ repo อยู่ในสภาพที่ใช้งานได้แล้ว ค่อยอัปเดตระบบ

### Checklist

Ubuntu/Debian:

* `apt update`
* `apt upgrade -y`

RHEL family:

* `dnf upgrade -y`

### ข้อสำคัญ

อย่าเอา phase นี้ไปปนกับ repo validation
ต้องแยกชัดว่า:

* พังเพราะ repo
* หรือพังเพราะ package change

---

## Phase 8 — Reboot & Reconnect

หลัง upgrade ควร reboot เพื่อให้ระบบนิ่งและ apply kernel change

### Checklist

* reboot
* รอ SSH กลับมา
* ตรวจว่า package manager ยังปกติ
* log reboot success/fail

### ถ้าพัง

* fail พร้อม log ว่า guest ไม่กลับมาหลัง reboot

---

## Phase 9 — Kernel Cleanup

ลด kernel เก่าและของค้างหลัง upgrade

### Checklist

* ตรวจจำนวน installed kernels
* ถ้ามากกว่า 2:

  * cleanup ให้เหลือ 2
* ถ้ามี 2 หรือน้อยกว่า:

  * ไม่ต้องทำอะไร

### จุดประสงค์

* ลดขนาด image
* ลดขยะจากระบบ

---

## Phase 10 — Access & Root SSH Policy

ตั้งค่า guest ให้ตรง policy ของคุณ

### Checklist

* เปิด root SSH

  * `PermitRootLogin yes`
  * `PasswordAuthentication yes`
  * `PubkeyAuthentication yes`
* ตั้ง root password
* ทำ per-instance script เพื่อ copy authorized_keys ไป root
* เก็บ script ไว้ที่:

  * `/var/lib/cloud/scripts/per-instance/`
* script นี้ห้ามลบตอน final clean

### เหตุผล

* ให้ image บูตขึ้นมาแล้วเข้าถึงได้ตาม policy
* ไม่ต้อง hardcode authorized key ค้างใน image

---

## Phase 11 — Locale / Timezone / Cloud-init Policy

ตั้งสภาพพื้นฐานของ guest

### Checklist

* locale

  * `locale-gen en_US.UTF-8 th_TH.UTF-8`
  * `LANG=en_US.UTF-8`
* timezone

  * `Asia/Bangkok`
* cloud-init behavior

  * `preserve_hostname: false`
  * `manage_etc_hosts: true`
  * `disable_root: false`

### เป้าหมาย

* ให้ image มี default behavior คงที่
* ลด surprise ตอน boot จริง

---

## Phase 12 — System Behavior Policy

ตั้ง behavior ของ guest ให้เหมาะกับ environment คุณ

### Checklist

* ปิด auto update
* ปิด MOTD news
* ปิด firewall ใน guest

  * ให้ไปคุมผ่าน Security Group แทน
* ไม่ fix DNS ใน guest
* ให้ DHCP/subnet แจก DNS เอง

### เป้าหมาย

* ลดสิ่งรบกวน
* ลดความขัดกันกับ infra ภายนอก
* ทำให้ image generic มากขึ้น

---

## Phase 13 — Repo State Re-Validation

หลังตั้งค่าหลายอย่างแล้ว ต้องเช็กอีกครั้งว่าระบบ package ยังโอเค

### Checklist

* repo state ต้องตรงกับที่ตั้งใจ

  * LEGACY_MIRROR
  * หรือ official fallback
* Ubuntu/Debian:

  * `apt update` ผ่านอีกครั้ง
* RHEL family:

  * `dnf makecache` หรือ `repolist` ผ่านอีกครั้ง

### จุดประสงค์

* กันกรณีที่ config อื่นไปทำให้ package state พังทีหลัง

---

## Phase 14 — Final Clean

phase นี้คือการทำให้ image สะอาดก่อน capture

### Checklist

* `cloud-init clean --logs`

* ลบ:

  * `/var/lib/cloud/instance`
  * `/var/lib/cloud/instances`

* ห้ามลบ:

  * `/var/lib/cloud/scripts/per-instance/`

* ลบ netplan cloud-init file ตาม policy

* reset machine-id

* ลบ dbus machine-id link/file ตามเหมาะสม

* ลบ SSH host keys

* clean package cache

  * `apt clean`
  * หรือ `dnf clean all`

* ลบ build-time authorized_keys

* ลบ shell history

* ลบ temp files

* ลบ log ที่ไม่จำเป็น

### เป้าหมาย

* ให้ image เล็กลง
* ให้ image สะอาด
* ไม่มีข้อมูล build-time ค้าง
* ลด security risk
* ให้ instance ใหม่ regenerate state สำคัญเองตอน boot

---

## Phase 15 — Final Validation

ก่อนปิดเครื่องหรือส่งต่อ publish ต้องตรวจรอบสุดท้าย

### Checklist

* cloud-init state ปกติ
* root SSH policy ถูก
* root account พร้อม
* per-instance script ยังอยู่
* locale ถูก
* timezone ถูก
* repo state ถูก
* package manager ใช้งานได้
* firewall state ถูก
* network ใช้งานได้
* build-time keys ถูกลบแล้ว
* temp residue ถูกลบแล้ว

### เป้าหมาย

* ให้มั่นใจก่อน capture image จริง

---

## Phase 16 — Shutdown

ขั้นสุดท้ายของ configure flow

### Checklist

* poweroff

นี่เป็น signal ว่า guest อยู่ใน state พร้อม capture/publish

---

# State Model ที่ควรมีใน phase configure

เพื่อให้ phase นี้ดูผ่านเมนูได้และ AI วิเคราะห์ต่อได้ ควรมี state ที่ชัดเจน

ตัวอย่าง:

* `preflight-ok`
* `baseline-official-ok`
* `repo-backup-ok`
* `legacy-mirror-injected`
* `legacy-mirror-validated`
* `vault-injected`
* `vault-validated`
* `legacy-mirror-fallback-official`
* `upgrade-ok`
* `reboot-ok`
* `kernel-cleanup-ok`
* `access-policy-ok`
* `system-policy-ok`
* `final-clean-ok`
* `final-validation-ok`
* `ready`
* `failed`

ถ้าจะทำเป็น flag file ก็ได้
ถ้าจะเก็บรวมใน JSON ด้วยก็ยิ่งดี

---

# Log ที่ต้องมีเพื่อให้ AI ช่วยคุณได้จริง

ทุก run ควรมี log ที่ละเอียดพอจะตอบคำถามเหล่านี้ได้:

* ใช้ config file ไหน
* OS อะไร version อะไร
* official baseline ผ่านไหม
* LEGACY_MIRROR inject สำเร็จไหม
* LEGACY_MIRROR validation ผ่านไหม
* ถ้า fail แล้ว rollback สำเร็จไหม
* update/upgrade ผ่านไหม
* reboot กลับมาไหม
* clean ผ่านไหม
* final validation ผ่านไหม

ถ้า fail ต้องระบุว่า fail ที่ phase ไหน และ command ไหน

---

# Promotion Logic แบบที่คุณต้องการ

ผมสรุปอีกครั้งแบบละเอียด

## กรณี config version ใหม่

สมมุติคุณกำลังเพิ่ม Ubuntu 26.04

flow:

1. ใช้ `config/guest/ubuntu/default.env` เป็นฐาน
2. generate `config/guest/ubuntu/26.04.env`
3. run configure/test
4. ถ้า fail:

   * เก็บ log
   * เอา log ไปให้ AI
   * AI ปรับ `26.04.env`
   * run ใหม่
5. ถ้า pass:

   * `26.04.env` ถือว่า validated
   * ถ้าคุณต้องการ ก็เอา config ที่ effective แล้ว promote กลับไป `default.env`

## ประโยชน์

* future versions ไม่ต้องเริ่มใหม่
* default ของ OS จะดีขึ้นเรื่อย ๆ ตาม version ล่าสุดที่ผ่านจริง
* version-specific edge case ยังแยกอยู่ ไม่ปนกับ default แบบมั่ว

---

# สิ่งที่ระบบนี้ช่วยคุณในอนาคต

เมื่อโครงแบบนี้นิ่งแล้ว เวลามี OS/version ใหม่มา คุณจะไม่ต้องคิดทุกอย่างใหม่หมด

สิ่งที่เกิดขึ้นคือ:

* มี baseline พร้อม
* มี flow test พร้อม
* มี log พร้อม
* มี state พร้อม
* มี AI loop พร้อม

นั่นแปลว่า:

* เพิ่ม version ใหม่ง่ายขึ้น
* debug ง่ายขึ้น
* แก้ไขเฉพาะจุดได้
* ลดการพังแบบมั่ว

---

# สรุปภาพใหญ่ทั้งหมดอีกครั้ง

สิ่งที่คุณต้องการคือระบบ configure guest ที่มีลักษณะดังนี้

## ด้าน config

* แยกตาม OS
* แยกตาม version
* มี default ของ OS
* มี override ของ version

## ด้าน execution

* phase ชัดจาก preflight → baseline → LEGACY_MIRROR → fallback → update → reboot → access policy → system policy → clean → validate → shutdown

## ด้าน failure handling

* ถ้า LEGACY_MIRROR พัง ให้ rollback official แล้วไปต่อได้
* ถ้าพังจริง ต้องมี log ว่าพังตรงไหน

## ด้าน AI-assisted loop

* AI สร้าง config
* คุณรันทดสอบ
* fail → เก็บ log → AI วิเคราะห์ → config ใหม่
* pass → เก็บ version config → promote เป็น default ได้

## ด้าน maintainability

* config ไม่ปนกัน
* path อ่านง่าย
* phase อ่านง่าย
* log/state เอาไปต่อเมนูและ AI ได้

---

# เวอร์ชันสรุปสั้นมาก

คุณกำลังออกแบบระบบที่:

* ใช้ `default.env` เป็นแม่แบบของแต่ละ OS
* ใช้ `<version>.env` เป็น override ของแต่ละ version
* phase configure มีลำดับชัดและมี LEGACY_MIRROR failover
* ถ้า fail มี log ให้ AI ช่วยแก้
* ถ้า pass เอาไปเป็นฐานของ OS version ถัดไป
* เป็น loop ที่ทำให้ config ของแต่ละ OS ดีขึ้นเรื่อย ๆ
