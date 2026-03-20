# ระบบสร้าง OpenStack Image (image-build)

Repository นี้เป็นระบบ Pipeline อัตโนมัติสำหรับการสร้างและเผยแพร่ OpenStack Image สำหรับ Linux distributions ต่างๆ โดยเน้นความง่ายในการจัดการผ่าน Jump Host

## วิธีการใช้งานเบื้องต้น (Quick Start)

### 1. การเตรียมเครื่อง Local
1. วาง Private Key สำหรับเชื่อมต่อ Jump Host ไว้ที่ `deploy/local/ssh/`
2. ตั้งค่าการเชื่อมต่อใน `deploy/local/ssh_config`
3. กำหนดค่าเริ่มต้นใน `deploy/local/control.env`:
   ```bash
   JUMP_HOST="root@10.254.20.100"
   JUMP_HOST_REPO_PATH="/root/image-build"
   ```

### 2. การสั่งงานผ่าน Controller
ใช้สคริปต์หลักในการสั่งงาน:
```bash
bash scripts/control.sh
```
เมนูหลักประกอบด้วย:
- **SSH**: ตรวจสอบการเชื่อมต่อและเปิด Terminal ไปยัง Jump Host
- **Git**: เตรียม Repository บน Jump Host (Bootstrap) และซิงค์โค้ด
- **Pipeline**: รันขั้นตอนการสร้าง Image (Manual หรือ Auto)

### 3. ขั้นตอนการรัน Pipeline
1. เลือกเมนู **Git** -> **bootstrap-remote-repo** (ทำครั้งแรกครั้งเดียว)
2. เลือกเมนู **Pipeline** -> **Auto by OS**
3. เลือก OS ที่ต้องการ (เช่น `ubuntu`)
4. ระบบจะทำการ:
   - ค้นหาเวอร์ชันใหม่ (Discover)
   - ดาวน์โหลด Image (Download)
   - นำเข้าสู่ OpenStack (Import)
   - ปรับแต่งค่าภายใน VM (Configure)
   - บันทึกเป็น Image สำเร็จรูป (Publish)
   - ลบทรัพยากรส่วนเกิน (Cleanup)

## เอกสารเพิ่มเติม (Documentation)
คุณสามารถอ่านรายละเอียดเพิ่มเติมได้ในโฟลเดอร์ `doc/`:
- `doc/20260320-architecture-overview-th.md`: ภาพรวมระบบ
- `doc/20260320-config-layout-th.md`: โครงสร้างการตั้งค่า
- `doc/20260320-operator-guide-th.md`: คู่มือการใช้งานอย่างละเอียด
- `doc/20260320-jump-host-config-th.md`: การเตรียม Jump Host

## ติดต่อและแจ้งปัญหา
หากพบปัญหาในการใช้งาน กรุณาแจ้งผ่านระบบ Issue ของโปรเจกต์
