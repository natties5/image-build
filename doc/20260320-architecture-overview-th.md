# ภาพรวมสถาปัตยกรรม (Architecture Overview)

โปรเจกต์ `image-build` เป็นระบบ Pipeline อัตโนมัติสำหรับสร้างและเผยแพร่ (Publish) OpenStack Image สำหรับ Linux distributions ต่างๆ

## วงจรชีวิตของ Pipeline (Pipeline Lifecycle)

Pipeline ประกอบด้วยขั้นตอนต่างๆ ดังนี้:

1. **Discover**: ตรวจสอบและค้นหา Cloud Image อย่างเป็นทางการจาก Mirror ของแต่ละ Distribution
2. **Download**: ดาวน์โหลด Image มาเก็บไว้ใน Cache บน Jump Host
3. **Build (Import)**: อัปโหลด Base Image ขึ้นไปยัง OpenStack Glance
4. **Configure (Build VM)**: สร้าง VM ชั่วคราวจาก Base Image และเริ่มการปรับแต่งค่า (Configuration)
5. **Validate**: ทำการทดสอบเพื่อให้แน่ใจว่า Image มีคุณภาพตามมาตรฐาน
6. **Publish**: ทำการ Snapshot VM ที่ปรับแต่งแล้ว และบันทึกเป็น Image สุดท้ายลงใน Glance
7. **Reuse (Cleanup)**: ลบทรัพยากรชั่วคราวที่ใช้ในกระบวนการสร้างออกทั้งหมด

## ชั้นของส่วนประกอบ (Component Layers)

โครงสร้างของ Repository แบ่งออกเป็นชั้นต่างๆ ดังนี้:

### 1. Control Layer (`scripts/control.sh`)
จุดเริ่มต้นสำหรับผู้ใช้งาน (Operator) ทำงานบนเครื่อง Local ของผู้ใช้ จัดการเรื่อง:
- การเชื่อมต่อ SSH ไปยัง Jump Host
- การซิงค์โค้ด (Git Sync) ของ Repository
- การควบคุมลำดับขั้นตอนของ Pipeline
- การซิงค์ค่ากำหนดการรัน (Runtime Configuration Sync)

### 2. Phase Layer (`phases/`)
สคริปต์ Shell ที่ทำงานเฉพาะทางในแต่ละขั้นตอนของ Pipeline ซึ่งจะถูกรันบน Jump Host:
- ออกแบบมาให้ทำงานซ้ำได้ (Idempotent)
- อ่านค่าจากอินพุตที่ถูกจัดระเบียบแล้ว (Normalized Inputs) ผ่าน Helper Library

### 3. Library Layer (`lib/`)
ตัวช่วย (Helpers) และตรรกะที่นำกลับมาใช้ใหม่ได้:
- `control_*.sh`: ตัวช่วยสำหรับ Local Controller (main, ssh, sync, ฯลฯ)
- `os_helpers.sh`: ตัวช่วยจัดการเกี่ยวกับระบบปฏิบัติการที่หลากหลายและ Manifest
- `runtime_helpers.sh`: ตัวช่วยในการโหลดค่ากำหนดและการซิงค์ข้อมูลระยะไกล

### 4. Configuration Layer (`config/`)
ค่ากำหนดที่ถูกบันทึกไว้สำหรับส่วนต่างๆ ของ Pipeline:
- ดูรายละเอียดได้ที่ `doc/YYYYMMDD-config-layout-th.md`

### 5. Manifest and Output Layer
ไฟล์ที่เครื่องสามารถอ่านได้และสถานะการทำงาน:
- `manifests/`: ข้อมูลเวอร์ชันที่ค้นพบและ Build Metadata
- `runtime/state/`: สถานะการทำงานปัจจุบันของ Pipeline
- `logs/`: บันทึกรายละเอียดการทำงาน (Logs)

## รูปแบบการทำงานผ่าน Jump Host (Jump Host Driven Model)

ระบบใช้ **Jump Host** เป็นสภาพแวดล้อมหลักในการรันคำสั่ง OpenStack และดาวน์โหลด Image โดย Local Controller จะซิงค์โค้ดและค่ากำหนดไปยัง Jump Host ผ่าน SSH และสั่งรันขั้นตอนต่างๆ จากระยะไกล รูปแบบนี้ช่วยให้การจัดการข้อมูลสำคัญ (Credentials) และการใช้งานเครือข่ายหนักๆ (เช่น การดาวน์โหลด Image ขนาดใหญ่) อยู่ในสภาพแวดล้อมที่ควบคุมได้
