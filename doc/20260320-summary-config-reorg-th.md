# สรุปการปรับปรุงโครงสร้าง Configuration (Reorganization)

เอกสารนี้สรุปการเปลี่ยนแปลงในการจัดระเบียบโครงสร้างไฟล์และลำดับการโหลดค่ากำหนด (Configuration) ของ repository `image-build`

## ปัญหาที่พบก่อนหน้านี้
- ไฟล์ config กระจัดกระจายอยู่ในโฟลเดอร์ `config/` โดยไม่มีการแยกหน้าที่ชัดเจน
- ความรับผิดชอบระหว่างค่ากำหนดสำหรับ Controller, Runtime และ Guest Policy ปะปนกัน
- การไล่ลำดับการโหลด config (Loading Flow) ทำได้ยาก

## โครงสร้างใหม่ที่ปรับปรุงแล้ว
เราได้แยกชั้นของ config ออกเป็น 4 เลเยอร์หลัก:

1. **Control Config (`config/control/`)**
   - ใช้สำหรับค่ากำหนดระดับตัวควบคุม (Operator/Jump-host control)
   - ไฟล์: `clean.env`, `publish.env`, `source.env`
   
2. **Runtime Config (`config/runtime/`)**
   - ใช้สำหรับค่ากำหนดที่ต้องใช้ในการรันบน OpenStack (Sync ไปยัง Jump Host)
   - ไฟล์: `openstack.env`, `openrc.path`

3. **OS Config (`config/os/`)**
   - ค่ากำหนดเฉพาะของแต่ละ OS (Discover/Download)
   - อยู่ในโฟลเดอร์เดิมแต่แยกหน้าที่ชัดเจนขึ้น

4. **Guest Policy Config (`config/guest/`)**
   - ค่ากำหนดนโยบายภายใน VM (VM Policy เท่านั้น)
   - ไฟล์: `access.env`, `policy.env`, `config.env`

## การแยกไฟล์ Local-only และ Tracked Files
- **Tracked Files**: ไฟล์ใน `config/` ทั้งหมดจะถูก Track ใน Git (เป็น Template หรือค่าเริ่มต้นที่ปลอดภัย)
- **Local-only Files**: ไฟล์ใน `deploy/local/` จะถูก Gitignored เสมอ ใช้สำหรับเก็บความลับ (Secrets) หรือค่าเฉพาะเครื่องของ Operator

## สิ่งที่ถูก Sync ไปยัง Jump Host
- ไฟล์ใน `config/os/` และ `config/guest/` จะถูก Sync ไปทั้งหมด
- ไฟล์ใน `deploy/local/*.env` (เฉพาะที่จำเป็น เช่น `guest-access.env`, `openstack.env`) จะถูกสร้างเป็น Overlay และ Sync ไปยัง `deploy/local/` บน Jump Host

## วิธีการอ่าน Repository ในปัจจุบัน
- หากต้องการดูนโยบายของ VM ให้ดูที่ `config/guest/`
- หากต้องการดูการตั้งค่า OpenStack พื้นฐาน ให้ดูที่ `config/runtime/`
- หากต้องการดูวิธีการเชื่อมต่อ Jump Host ให้ดูที่ `deploy/local/control.env`
- หากต้องการดูประวัติการเปลี่ยนแปลง ให้ดูที่ `doc/commit-history-and-branching.md`

## สิ่งที่ไม่มีการเปลี่ยนแปลง (Intentionally NOT changed)
- **พฤติกรรมของ Pipeline**: ขั้นตอน Discover -> Download -> Build ยังคงเหมือนเดิม
- **Ubuntu Flow**: การ Build Ubuntu ยังทำงานได้ปกติ
- **Multi-OS Auto-download**: ระบบค้นหาและดาวน์โหลด OS อื่นๆ ยังทำงานได้ปกติ
- **Entrypoint**: ยังคงใช้ `scripts/control.sh` เป็นหลัก

## สรุปการย้ายไฟล์
- `config/*.env` (ส่วนใหญ่) -> `config/control/` หรือ `config/runtime/`
- `config/guest-config.env` -> `config/guest/config.env`
- `docs/` -> รวมเข้ากับ `doc/`
- `lib/control_os.sh` -> `lib/os_helpers.sh`
- `lib/control_runtime_config.sh` -> `lib/runtime_helpers.sh`
