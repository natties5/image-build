# สรุปงานเพิ่มการดาวน์โหลด image หลายระบบปฏิบัติการแบบ auto-discover

เอกสารนี้สรุปการเพิ่มความสามารถดาวน์โหลด image อย่างเป็นทางการสำหรับ Debian, Fedora, CentOS, AlmaLinux และ Rocky Linux โดยยึดรูปแบบเดียวกับ Ubuntu ที่มีอยู่เดิมให้มากที่สุด

## สิ่งที่เพิ่มเข้ามา

- เพิ่มไฟล์ config ใหม่ใน `config/os/` สำหรับ `debian`, `fedora`, `centos`, `almalinux`, `rocky`
- เพิ่ม phase wrapper ใหม่ใน `phases/download_<os>.sh` เพื่อเรียก workflow ของแต่ละระบบปฏิบัติการ
- เพิ่ม `phases/download_multi_os.sh` เป็นตัวรวม logic ที่ใช้รูปแบบเดียวกับ Ubuntu:
  - discover เวอร์ชันจาก official source
  - คัดกรองด้วย `MIN_VERSION`, `MAX_VERSION`, `ALLOW_EOL`
  - หา artifact ที่เป็น cloud image / qcow2
  - ดาวน์โหลดไปที่ `cache/<os>/<version>/`
  - ตรวจ checksum
  - เขียน manifest ไปที่ `manifests/<os>/<os>-<version>.json`
  - เขียน summary TSV ไปที่ `manifests/<os>/<os>-auto-discover-summary.tsv`
  - rerun แล้วถ้า checksum ตรงจะรายงาน `cached`

## การยึดรูปแบบ Ubuntu

งานนี้ไม่ได้ออกแบบระบบใหม่ แต่ใช้รูปแบบเดียวกับ Ubuntu เดิม ได้แก่

- ใช้ config เป็นตัวควบคุมการเลือกเวอร์ชัน
- ใช้ official index/release page เพื่อ discover image
- ใช้ checksum จากต้นทางอย่างเป็นทางการเพื่อตรวจสอบไฟล์
- ใช้ cache layout และ manifest layout แบบเดียวกับ Ubuntu
- ใช้สถานะ `downloaded` และ `cached` เหมือนกัน
- `phases/download.sh` ยังทำงานแบบเดิมกับ Ubuntu และจะ dispatch ไป workflow ใหม่เฉพาะเมื่อ `OS_FAMILY` ไม่ใช่ `ubuntu`

## ระบบปฏิบัติการที่รองรับในงานนี้

- Debian 9-13
- Fedora 26-43
- CentOS 6-10
- AlmaLinux 8-10
- Rocky Linux 8-10

หมายเหตุ: ค่า default ในแต่ละไฟล์ `config/os/*.env` ถูกตั้งไว้ให้ทดสอบช่วงเวอร์ชันใหม่ก่อน แต่ operator สามารถขยาย/ลดช่วงเวอร์ชันได้เองด้วย `MIN_VERSION` และ `MAX_VERSION`

## ตำแหน่งไฟล์

### ไฟล์ image ที่ดาวน์โหลด

เก็บที่:

- `cache/debian/<version>/`
- `cache/fedora/<version>/`
- `cache/centos/<version>/`
- `cache/almalinux/<version>/`
- `cache/rocky/<version>/`

### manifest

เก็บที่:

- `manifests/debian/debian-<version>.json`
- `manifests/fedora/fedora-<version>.json`
- `manifests/centos/centos-<version>.json`
- `manifests/almalinux/almalinux-<version>.json`
- `manifests/rocky/rocky-<version>.json`

### summary TSV

เก็บที่:

- `manifests/debian/debian-auto-discover-summary.tsv`
- `manifests/fedora/fedora-auto-discover-summary.tsv`
- `manifests/centos/centos-auto-discover-summary.tsv`
- `manifests/almalinux/almalinux-auto-discover-summary.tsv`
- `manifests/rocky/rocky-auto-discover-summary.tsv`

## วิธีทำงานของ MIN_VERSION / MAX_VERSION / ALLOW_EOL

- `MIN_VERSION` เป็นค่าบังคับ ใช้คัดกรองเวอร์ชันต่ำสุดที่ต้องการ
- `MAX_VERSION` เป็นค่าทางเลือก ใช้จำกัดเวอร์ชันสูงสุด
- `ALLOW_EOL=1` ใช้เมื่อ operator ต้องการรวมเวอร์ชันที่หมดอายุแล้ว เช่น Fedora archive หรือ CentOS รุ่นเก่า
- ถ้าเป็นรุ่น EOL และยังไม่ได้เปิด `ALLOW_EOL` script จะหยุดพร้อมข้อความชัดเจน ไม่ข้ามเงียบ ๆ

## พฤติกรรม rerun

เมื่อรันซ้ำ:

- ถ้าไฟล์มีอยู่แล้วและ checksum ตรง จะเขียนสถานะเป็น `cached`
- ถ้าไฟล์มีอยู่แต่ checksum ไม่ตรง จะดาวน์โหลดใหม่และสถานะจะเป็น `downloaded`
- ถ้าไฟล์ยังไม่มี จะดาวน์โหลดใหม่และสถานะจะเป็น `downloaded`

## สิ่งที่ยังไม่ได้ทำ

ตามขอบเขตของงานนี้ ยัง **ไม่ได้** เพิ่มสำหรับ OS ใหม่เหล่านี้ในส่วนต่อไปนี้

- Windows
- guest configuration
- OpenStack import/create/configure/clean/publish สำหรับ OS ใหม่
- การ redesign โครงสร้าง repo

## ข้อจำกัดของ environment นี้

Codex environment ปัจจุบันมีข้อจำกัดด้าน network/proxy ทำให้การยิง official source จริงอาจล้มเหลวด้วย 403 หรือ tunnel/proxy error ได้ ดังนั้นใน environment นี้ให้ยืนยันได้เฉพาะระดับ code เช่น syntax, shellcheck, manifest/path layout, และการ review การประกอบ URL

การทดสอบดาวน์โหลดจริงจาก official source ต้องไปรันต่อบน **jump host** ที่ออกเน็ตได้ตามปกติ

## Operator checklist สำหรับ jump host

ให้รันจาก root ของ repo และตรวจผลทั้งรอบแรก (`downloaded`) และรอบสอง (`cached`)

### Debian

```bash
cp config/os/debian.env /tmp/debian.env
sed -i 's/^MIN_VERSION=.*/MIN_VERSION="12"/' /tmp/debian.env
sed -i 's/^MAX_VERSION=.*/MAX_VERSION="12"/' /tmp/debian.env
bash bin/imagectl.sh download /tmp/debian.env
bash bin/imagectl.sh download /tmp/debian.env
```

### Fedora

```bash
cp config/os/fedora.env /tmp/fedora.env
sed -i 's/^MIN_VERSION=.*/MIN_VERSION="42"/' /tmp/fedora.env
sed -i 's/^MAX_VERSION=.*/MAX_VERSION="42"/' /tmp/fedora.env
bash bin/imagectl.sh download /tmp/fedora.env
bash bin/imagectl.sh download /tmp/fedora.env
```

### CentOS

```bash
cp config/os/centos.env /tmp/centos.env
sed -i 's/^MIN_VERSION=.*/MIN_VERSION="9"/' /tmp/centos.env
sed -i 's/^MAX_VERSION=.*/MAX_VERSION="9"/' /tmp/centos.env
bash bin/imagectl.sh download /tmp/centos.env
bash bin/imagectl.sh download /tmp/centos.env
```

### AlmaLinux

```bash
cp config/os/almalinux.env /tmp/almalinux.env
sed -i 's/^MIN_VERSION=.*/MIN_VERSION="9"/' /tmp/almalinux.env
sed -i 's/^MAX_VERSION=.*/MAX_VERSION="9"/' /tmp/almalinux.env
bash bin/imagectl.sh download /tmp/almalinux.env
bash bin/imagectl.sh download /tmp/almalinux.env
```

### Rocky

```bash
cp config/os/rocky.env /tmp/rocky.env
sed -i 's/^MIN_VERSION=.*/MIN_VERSION="9"/' /tmp/rocky.env
sed -i 's/^MAX_VERSION=.*/MAX_VERSION="9"/' /tmp/rocky.env
bash bin/imagectl.sh download /tmp/rocky.env
bash bin/imagectl.sh download /tmp/rocky.env
```

หลังจากแต่ละชุดคำสั่ง ให้ตรวจอย่างน้อย:

- มีไฟล์ใน `cache/<os>/<version>/`
- มี manifest ใน `manifests/<os>/`
- มี summary TSV ของ OS นั้น
- รอบสองรายงาน `cached`
