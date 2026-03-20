# โครงสร้างค่ากำหนด (Configuration Layout)

เอกสารนี้อธิบายโครงสร้างการตั้งค่า (Configuration) ของ repository `image-build`

## ชั้นของค่ากำหนด (Layers)

Repository นี้แบ่งการตั้งค่าออกเป็นชั้นต่างๆ ดังนี้:

### 1. Control Config (`config/control/`)
เทมเพลตและค่าเริ่มต้นสำหรับการควบคุมโดย Operator หรือการตั้งค่า Jump-host:
- `clean.env`: ค่ากำหนดสำหรับขั้นตอนการล้างทรัพยากร (Cleanup phase)
- `publish.env`: ค่ากำหนดสำหรับขั้นตอนการเผยแพร่ Image (Image publication phase)
- `source.env`: ค่ากำหนดสำหรับการค้นหาต้นทาง (Source discovery)

### 2. Runtime Sync Config (`config/runtime/`)
เทมเพลตสำหรับการรันในสภาพแวดล้อม OpenStack สำหรับค่ากำหนดส่วนตัวควรเก็บไว้ที่ `deploy/local/`:
- `openstack.env`: เทมเพลตทรัพยากรและ ID ต่างๆ ของ OpenStack
- `openrc.path`: พาธไปยังไฟล์ Credentials ของ OpenStack

### 3. OS Config (`config/os/`)
พฤติกรรมการค้นหาและดาวน์โหลดของแต่ละระบบปฏิบัติการ (OS):
- `ubuntu.env`, `debian.env`, `fedora.env`, ฯลฯ
- ประกอบด้วย `MIN_VERSION`, `MAX_VERSION`, `ALLOW_EOL` และ URL ของต้นทางอย่างเป็นทางการ

### 4. Guest Policy Config (`config/guest/`)
การตั้งค่าเกี่ยวกับนโยบายของ VM ซึ่งแยกส่วนอิสระจากตัวควบคุมหรือตรรกะการรัน:
- `access.env`: การเข้าถึงพื้นฐาน (Root user, SSH port)
- `policy.env`: นโยบายการปรับแต่งค่าอย่างละเอียด (ภาษา, โซนเวลา, การอัปเกรด, ฯลฯ)
- `config.env`: การตั้งค่าเพิ่มเติมเฉพาะเจาะจงของ Guest

## ค่ากำหนดเฉพาะส่วนตัว (`deploy/local/`)
โฟลเดอร์นี้ประกอบด้วยไฟล์ส่วนตัวที่จะถูกเพิกเฉยโดย Git (Gitignored) สำหรับเขียนทับค่าเริ่มต้น ซึ่งจะไม่ถูก Commit เข้าระบบ:
- `control.env`: การตั้งค่าเฉพาะตัวควบคุม (เช่น รายละเอียดการเชื่อมต่อ Jump-host)
- `openstack.env`: ค่าเขียนทับสำหรับทรัพยากร OpenStack ส่วนตัว
- `openrc.path`: พาธไปยังไฟล์ `openrc` ส่วนตัวของคุณ
- `guest-access.env`: ข้อมูลประจำตัวส่วนตัวของ Guest (เช่น `ROOT_PASSWORD`)
- `ssh_config`: การตั้งค่า SSH สำหรับเชื่อมต่อ Jump host
- `ssh/`: กุญแจ SSH (SSH Keys)

## ลำดับการโหลดค่ากำหนด (Effective Config Loading Flow)
1. **Local Operator** เริ่มต้นใช้งาน `scripts/control.sh`
2. **Load Control Config**: โหลดไฟล์จาก `deploy/local/control.env` และค่าเริ่มต้นที่กำหนดไว้
3. **Connect/Sync to Jump Host**: ใช้การตั้งค่า SSH เพื่อซิงค์ Repository ไปยัง Jump Host
4. **Sync Runtime Config**: สร้างไฟล์ Overlay จาก `deploy/local/*.env` และซิงค์ไปยังโฟลเดอร์ `deploy/local/` บน Jump Host
5. **Phase Execution**: ขั้นตอนต่างๆ บนรีโมทจะโหลดไฟล์ที่ซิงค์มาใน `deploy/local/` ตามด้วยค่าเริ่มต้นที่กำหนดไว้ใน `config/`

## ตารางสรุป (Summary Table)

| ประเภท | โฟลเดอร์ | ซิงค์ไป Jump Host? | เก็บใน Git? |
| :--- | :--- | :--- | :--- |
| **Control** | `config/control/` | ไม่ | ใช่ |
| **Runtime** | `config/runtime/` | ไม่ | ใช่ |
| **OS** | `config/os/` | ใช่ | ใช่ |
| **Guest** | `config/guest/` | ใช่ | ใช่ |
| **Local Overrides** | `deploy/local/` | เฉพาะบางไฟล์ | ไม่ |
| **Outputs/State** | `manifests/`, `runtime/`, `logs/` | ใช่ | เฉพาะบางไฟล์ |
