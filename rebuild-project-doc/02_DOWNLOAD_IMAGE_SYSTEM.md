ได้ ผมสรุป “เรื่องการ download image” ใหม่แบบละเอียดและล็อกตามที่คุณเลือกแล้ว

## เป้าหมายของ phase นี้

phase แรกคือ `sync_download`
หน้าที่ของมันคือ:

* ค้นหา base image จาก **official upstream**
* เลิกใช้ URL hardcode
* ใช้ระบบ **rule-driven auto-discovery**
* รองรับ **dry-run** แบบจริงจัง
* ถ้าดาวน์โหลดจริง ต้อง **resume ได้** และ **verify hash 100%**
* ผลลัพธ์ต้องถูกเขียนลง **state/manifest/log** เพื่อให้ phase ถัดไปเอาไปใช้ต่อได้

เป้าหมายของ phase นี้ **ไม่ใช่** แค่โหลดไฟล์
แต่คือทำให้ระบบ “รู้แน่ชัด” ว่าแต่ละ OS / version จะใช้ไฟล์อะไร, อยู่ที่ URL ไหน, hash อะไร, format ไหน, และ local status เป็นอะไร

---

## หลักคิดที่ล็อกแล้ว

ตอนนี้กติกาหลักของระบบ download คือแบบนี้

### 1) ใช้ tracked versions only เป็นค่า default

ระบบจะเช็กเฉพาะ version ที่เราระบุไว้ใน rule file เท่านั้น เช่น `22.04 24.04`

เหตุผล:

* predictable
* เร็ว
* ไม่ noisy
* เหมาะกับงานจริง

และในอนาคตค่อยมี option เสริม เช่น `--discover-all` สำหรับ debug / maintenance

### 2) รองรับ architecture แค่ `amd64/x86_64` ก่อน

ยังไม่เปิดหลาย arch เพื่อไม่ให้ logic ซับซ้อนเกินจำเป็น

### 3) เลือก image format ตามลำดับนี้

* เอา `.img` ก่อน
* ถ้าไม่มี ค่อย fallback ไป `.qcow2`

### 4) dry-run ต้องเป็น first-class mode

dry-run ไม่ใช่แค่ skip download แบบลวก ๆ
แต่ต้อง:

* แสดงผลบนหน้าจอ
* เขียน state
* เขียน manifest
* พิสูจน์ได้ว่า discovery logic ใช้ได้จริง

### 5) manifest หลักใช้ `.json`

เพราะ phase นี้มีข้อมูลหลายชั้น ไม่เหมาะกับ `.env` อย่างเดียว

### 6) state ใช้ flag file + manifest แยกกัน

* flag ใช้บอกสถานะเร็ว ๆ
* JSON ใช้เก็บรายละเอียดเต็ม

---

# โครงสร้างที่เกี่ยวกับการ download

## 1) Rule files

เก็บไว้ที่:

```text
config/os/<os>/sync.env
```

ตัวอย่าง:

```text
config/os/ubuntu/sync.env
config/os/debian/sync.env
config/os/rocky/sync.env
config/os/almalinux/sync.env
config/os/fedora/sync.env
```

แต่ละไฟล์คือ “กฎการค้นหา image” ของ OS นั้น

---

## 2) Runtime outputs

ผลลัพธ์จาก `sync_download` จะถูกเขียนประมาณนี้:

```text
runtime/
├── state/
│   └── sync/
│       ├── ubuntu-22.04.dryrun-ok
│       ├── ubuntu-22.04.ready
│       ├── ubuntu-22.04.failed
│       └── ...
└── logs/
    └── sync/
        ├── ubuntu-22.04.log
        ├── ubuntu-24.04.log
        └── summary.tsv
```

และ manifest หลัก:

```text
runtime/state/sync/ubuntu-22.04.json
runtime/state/sync/ubuntu-24.04.json
```

---

## 3) Workspace download target

ไฟล์ image จริงเก็บไว้ที่:

```text
workspace/images/<os>/<version>/
```

เช่น:

```text
workspace/images/ubuntu/24.04/ubuntu-24.04-server-cloudimg-amd64.img
workspace/images/debian/12/debian-12-generic-amd64.qcow2
```

---

# Schema ของ `sync.env`

ผมสรุปให้เป็น schema ที่ไม่มั่วและยืดหยุ่นพอ

## ฟิลด์หลักที่ควรมี

### Identity

```bash
OS_FAMILY="ubuntu"
TRACKED_VERSIONS="22.04 24.04"
```

### Discovery behavior

```bash
DISCOVERY_MODE="checksum_driven"
LATEST_LOGIC="current_folder"
```

### URLs / upstream structure

```bash
INDEX_URL_TEMPLATE="https://cloud-images.ubuntu.com/releases/{VERSION}/release/"
CHECKSUM_FILE="SHA256SUMS"
```

หรือถ้า distro นั้นซับซ้อนกว่า:

```bash
RELEASE_DISCOVERY_REGEX='release-[0-9]{8}(\.[0-9]+)?/'
CHECKSUM_FILE_REGEX='^SHA256SUMS$'
```

### Matching and selection

```bash
ARCH_PRIORITY="amd64 x86_64"
FORMAT_PRIORITY="img qcow2"
IMAGE_REGEX='...'
CHECKSUM_REGEX='^([a-fA-F0-9]+)[[:space:]]+\*?(.*)$'
```

### Hash verification

```bash
HASH_ALGO="sha256"
```

### Optional switches

```bash
DRY_RUN_SUPPORTED="yes"
```

---

## ฟิลด์ที่ผมแนะนำให้ถือว่า “บังคับ”

อย่างน้อยทุก `sync.env` ควรมี:

* `OS_FAMILY`
* `TRACKED_VERSIONS`
* `DISCOVERY_MODE`
* `LATEST_LOGIC`
* `HASH_ALGO`
* `ARCH_PRIORITY`
* `FORMAT_PRIORITY`
* ข้อมูล upstream อย่างน้อยหนึ่งชุด เช่น `INDEX_URL_TEMPLATE` หรือ equivalent
* rule สำหรับ match image/checksum อย่างน้อยหนึ่งแบบ

---

# แนวคิดการเลือก image

ระบบจะไม่เลือกไฟล์แบบมั่ว ๆ
ต้องมีลำดับชัดเจนดังนี้

## ลำดับการคัด candidate

1. อยู่ใน version ที่ tracked
2. เป็น architecture ที่ต้องการ (`amd64/x86_64`)
3. เป็น image file จริง ไม่ใช่ checksum/manifest/torrent/boot ISO
4. ถ้ามีหลาย format ให้เลือก `.img` ก่อน
5. ถ้าไม่มี `.img` ค่อยเลือก `.qcow2`
6. ถ้ามีหลาย patch release ให้ใช้ `LATEST_LOGIC` ของ OS นั้นเลือกตัวล่าสุด

---

# Discovery Engine ที่ควรเป็น

engine กลางอยู่ที่:

```text
phases/sync_download.sh
```

มันต้องเป็น generic engine ที่อ่าน rule file แล้วทำงานตามกฎ
ไม่ใช่เขียน shell ยาวแยกเต็ม ๆ ในแต่ละ distro

ถ้าบาง distro ต้องมี logic เฉพาะจริง ค่อยแยก helper function ไปไว้ใน `lib/`

---

# Flow การทำงานแบบละเอียด

## ขั้นที่ 1: โหลด rule file

เมื่อผู้ใช้เลือก OS เช่น Ubuntu
ระบบจะอ่าน:

```text
config/os/ubuntu/sync.env
```

จากนั้น parse ค่าต่าง ๆ เช่น tracked versions, discovery mode, format priority, hash algo

---

## ขั้นที่ 2: วนตาม tracked versions

สมมติ `TRACKED_VERSIONS="22.04 24.04"`
ระบบจะทำ discovery แยกทีละ version

เช่น:

* ubuntu 22.04
* ubuntu 24.04

---

## ขั้นที่ 3: resolve upstream path

ระบบจะหา release/index/checksum location ตามกฎของ OS นั้น

ตัวอย่าง:

* Ubuntu อาจใช้ current/release structure
* Debian อาจใช้ latest structure
* Rocky/Alma อาจกวาดหน้า directory หลักแล้ว sort
* Fedora อาจต้องหา checksum file ก่อน

หลักการสำคัญคือ:

**ถ้ามี checksum/index file ที่เชื่อถือได้ ให้ยึด checksum/index file ก่อน HTML scraping**

HTML scraping ใช้เมื่อจำเป็นจริงเท่านั้น

---

## ขั้นที่ 4: หา checksum source

ระบบต้องหา checksum file ให้เจอก่อนหรือเร็วที่สุดเท่าที่เป็นไปได้ เพราะ checksum file มักเป็นแหล่งข้อมูลที่นิ่งกว่า HTML

เช่น:

* `SHA256SUMS`
* `SHA512SUMS`
* `CHECKSUM`
* Fedora-style named checksum file

---

## ขั้นที่ 5: parse checksum entries

หลังจากได้ checksum content แล้ว ระบบจะ parse รายการไฟล์ทั้งหมดออกมาเป็น candidate list

แต่ละ candidate อย่างน้อยควรได้ข้อมูล:

* filename
* hash
* hash_algo
* source url/reference

---

## ขั้นที่ 6: match image ด้วย rule

ใช้กฎของ OS นั้นกรอง candidate ให้เหลือเฉพาะไฟล์ที่ต้องการจริง

เช่น:

* ชื่อมี `amd64` หรือ `x86_64`
* เป็น `.img` หรือ `.qcow2`
* เป็น cloud image จริง
* ไม่ใช่ generic file อื่น

---

## ขั้นที่ 7: ใช้ priority logic เลือกไฟล์สุดท้าย

เมื่อเจอหลาย candidate ระบบเลือกด้วยลำดับนี้

### 7.1 เลือก arch

* `amd64`
* ถ้าไม่มี ค่อยดู `x86_64`

### 7.2 เลือก format

* `.img`
* ถ้าไม่มี ค่อย `.qcow2`

### 7.3 เลือก latest

ขึ้นอยู่กับ `LATEST_LOGIC` เช่น:

* `current_folder`
* `sort_version`
* `latest_symlink`
* `checksum_driven`

---

## ขั้นที่ 8: สร้าง download result object

เมื่อเลือกรายการสุดท้ายได้แล้ว ระบบต้องประกอบข้อมูลสำหรับ output

อย่างน้อยควรมี:

* `os_family`
* `version`
* `filename`
* `format`
* `arch`
* `download_url`
* `checksum`
* `hash_algo`
* `checksum_source`
* `discovery_mode`
* `status`

---

# โหมด dry-run

dry-run คือ phase สำคัญมากในระบบนี้
มันต้องทำงาน “เกือบครบทุกอย่าง” ยกเว้นไม่โหลดไฟล์จริง

## dry-run ต้องทำอะไรบ้าง

* โหลด rule file
* resolve upstream
* หา checksum
* parse candidate
* เลือก image ที่จะใช้จริง
* ประกอบ download URL
* แสดงผลบนหน้าจอ
* เขียน log
* เขียน manifest JSON
* เขียน flag state

## dry-run ไม่ทำอะไร

* ไม่โหลดไฟล์จริง
* ไม่เขียนไฟล์ image ลง workspace
* ไม่ verify local file ด้วย hash เว้นแต่ user ขอ explicit local check mode

## สถานะของ dry-run

ถ้าสำเร็จ ควรได้สถานะเช่น:

* `discovered`
* `dryrun-ok`

ถ้าล้มเหลว เช่น:

* `failed-discovery`
* `failed-checksum`
* `failed-pattern-match`

---

# โหมด download จริง

เมื่อไม่ใช่ dry-run ระบบถึงจะเริ่มแตะไฟล์ในเครื่อง

## ขั้นที่ 1: ตรวจ local file ก่อน

ระบบจะดูว่าไฟล์ปลายทางใน `workspace/images/...` มีอยู่แล้วหรือไม่

### ถ้ามีอยู่แล้ว

* คำนวณ hash
* ถ้าตรงกับ expected checksum → mark `cached-valid`
* ถ้าไม่ตรง → mark stale แล้ว re-download

### ถ้ายังไม่มี

* ไปโหลดใหม่

---

## ขั้นที่ 2: ดาวน์โหลดแบบ resume

คำแนะนำที่เราล็อกคือ:

* prefer `wget --continue`
* fallback `curl -L -C -`

เหตุผล:

* portable กว่า
* รองรับ resume
* เหมาะกับไฟล์ใหญ่

---

## ขั้นที่ 3: verify หลังโหลดเสร็จ

เมื่อดาวน์โหลดเสร็จ ต้อง verify hash อีกรอบเสมอ

เช่น:

* `sha256sum`
* `sha512sum`

ถ้า hash ไม่ตรง:

* mark `failed-checksum`
* ไม่ให้ถือว่า ready
* เก็บ log ให้ชัด

ถ้าตรง:

* mark `downloaded-valid`
* เขียน manifest
* สร้าง ready flag

---

# State model ของ sync phase

ผมแนะนำให้ state ของ phase นี้มี 2 ชั้น

## 1) Flag files

ใช้สำหรับเช็กเร็ว
เช่น:

```text
runtime/state/sync/ubuntu-24.04.discovered
runtime/state/sync/ubuntu-24.04.dryrun-ok
runtime/state/sync/ubuntu-24.04.ready
runtime/state/sync/ubuntu-24.04.failed
```

## 2) JSON manifest

ใช้เก็บรายละเอียดเต็ม

เช่น:

```text
runtime/state/sync/ubuntu-24.04.json
```

---

# สถานะที่ควรใช้

ผมสรุปชุดสถานะที่เหมาะสุดตอนนี้คือ:

* `discovered`
* `dryrun-ok`
* `cached-valid`
* `downloaded-valid`
* `ready`
* `failed-discovery`
* `failed-checksum`
* `failed-download`
* `failed-no-candidate`

---

# รูปแบบของ manifest JSON

ไฟล์หลักควรเป็น JSON เพราะ phase นี้มีข้อมูลซ้อนและโตได้

ตัวอย่างโครง:

```json
{
  "os_family": "ubuntu",
  "version": "24.04",
  "status": "dryrun-ok",
  "mode": "dry-run",
  "arch_selected": "amd64",
  "format_selected": "img",
  "filename": "ubuntu-24.04-server-cloudimg-amd64.img",
  "download_url": "https://...",
  "checksum": "abc123...",
  "hash_algo": "sha256",
  "checksum_source": "https://.../SHA256SUMS",
  "workspace_path": "workspace/images/ubuntu/24.04/ubuntu-24.04-server-cloudimg-amd64.img",
  "candidates": [
    {
      "filename": "ubuntu-24.04-server-cloudimg-amd64.img",
      "arch": "amd64",
      "format": "img",
      "checksum": "abc123..."
    },
    {
      "filename": "ubuntu-24.04-server-cloudimg-amd64.qcow2",
      "arch": "amd64",
      "format": "qcow2",
      "checksum": "def456..."
    }
  ],
  "discovery": {
    "mode": "checksum_driven",
    "index_url": "https://...",
    "latest_logic": "current_folder"
  },
  "generated_at": "2026-03-21T00:00:00Z"
}
```

---

# Per-OS behavior ที่ล็อกไว้

## Ubuntu

แนวคิด:

* เจาะ current/release structure ตาม rule
* parse checksum file
* เลือก cloud image ที่ตรง version
* `.img` ก่อน `qcow2`

## Debian

แนวคิด:

* ใช้ latest structure
* ยึด checksum เป็นหลัก
* บังคับใช้ `sha512`

## Rocky / AlmaLinux

แนวคิด:

* กวาด candidate หลาย patch release
* filter ให้เหลือ cloud image จริง
* ใช้ `sort -V` เลือกตัวล่าสุด

## Fedora

แนวคิด:

* หา checksum file ก่อน
* ใช้ checksum naming and metadata ช่วยเลือก candidate
* parser ต้องยืดหยุ่นกว่ากลุ่มอื่น

---

# สิ่งที่ phase นี้ต้อง “ไม่ทำมั่ว”

เพื่อให้ระบบนิ่งและ maintain ง่าย ผมล็อกข้อห้ามไว้แบบนี้

* ไม่ hardcode direct image URL ต่อ version
* ไม่ parse HTML ลึกเกินไปถ้ามี checksum/index file ที่นิ่งกว่า
* ไม่เลือกไฟล์จาก regex กว้างเกินจนปน ISO/checksum/manifest
* ไม่ถือว่าไฟล์ local ใช้ได้ถ้ายังไม่ได้ verify hash
* ไม่ mark ready ก่อน checksum ผ่าน
* ไม่ผูก discovery logic กับ download จน dry-run แยกไม่ได้
* ไม่ทำให้แต่ละ OS ต้องมี script ยาวคนละชุดถ้าใช้ generic engine ได้

---

# Menu behavior ที่เกี่ยวกับ download

ในเมนูหลัก phase นี้ควรมีอย่างน้อย:

## Sync / Download

* Dry-run discovery by OS
* Dry-run discovery all tracked versions
* Download selected OS/version
* Download all tracked versions
* Show last sync manifest
* Show sync logs
* Clear failed sync state

ตัวอย่าง flow:

1. ผู้ใช้เลือก OS
2. ระบบโหลด `sync.env`
3. dry-run discovery
4. แสดง candidate/result
5. ถ้าผู้ใช้ยืนยัน ค่อย download จริง

---

# พฤติกรรมที่เหมาะกับการพัฒนาใน VS Code + Git Bash

เพราะคุณต้องการให้ทดสอบผ่าน Git Bash ได้ด้วย
phase นี้ควรออกแบบให้:

* ใช้ Bash มาตรฐาน
* ไม่พึ่ง path แบบ Linux-only แปลก ๆ มากเกินไป
* ใช้ `wget` หรือ `curl` อย่างใดอย่างหนึ่งได้
* dry-run ทำงานได้แม้เครื่องนั้นไม่อยากโหลดไฟล์ใหญ่จริง
* เขียน output แบบอ่านง่ายทั้งคนและ shell

นี่ทำให้ `sync_download` เป็น phase ที่เหมาะสุดสำหรับเริ่มโครงสร้างใหม่ก่อน phase อื่น

---

# ข้อสรุปสุดท้ายของการ download image

สรุปแบบล็อกแล้วตอนนี้คือ:

## Input

* per-OS rule file: `config/os/<os>/sync.env`
* default behavior: tracked versions only
* arch priority: `amd64` / `x86_64`
* format priority: `.img` ก่อน, ถ้าไม่มีค่อย `.qcow2`

## Engine

* ใช้ generic engine ที่ `phases/sync_download.sh`
* checksum-first when possible
* HTML scraping ใช้เท่าที่จำเป็น

## Modes

* `dry-run` เป็น first-class mode
* `download` เป็น mode จริงอีกแบบ

## Output

* state flags ใน `runtime/state/sync/`
* manifest JSON ต่อ OS/version
* logs แยก per OS/version
* ไฟล์จริงเก็บที่ `workspace/images/<os>/<version>/`

## Verification

* local cache ต้อง verify hash ก่อน reuse
* download เสร็จต้อง verify อีกครั้ง
* only verified files become `ready`

## Future-safe

* ตอนนี้เน้น tracked versions only
* ภายหลังค่อยเพิ่ม `--discover-all`

