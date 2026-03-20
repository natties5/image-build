# การตั้งค่า Jump Host (Jump Host Configuration)

ระบบ `image-build` อาศัย Jump Host ในการรันคำสั่ง OpenStack และดาวน์โหลด Image

## ความต้องการ (Requirements)

1. **ระบบปฏิบัติการ (Operating System)**: โดยทั่วไปเป็น Ubuntu หรือ CentOS
2. **การเข้าถึง (Access)**: การเข้าถึงผ่าน SSH ด้วย Key-based authentication
3. **OpenStack CLI**: ต้องติดตั้งและตั้งค่า `openstack` client ไว้เรียบร้อยแล้ว
4. **Git**: ใช้สำหรับการซิงค์ Repository
5. **พื้นที่ดิสก์ (Disk Space)**: พื้นที่เพียงพอสำหรับเก็บ Image Cache (เช่น ใน `/root/image-build/cache`)

## การตั้งค่าเริ่มต้น (Initial Setup)

1. **เตรียมการเข้าถึงผ่าน SSH (Bootstrap SSH Access)**:
   - ตรวจสอบให้แน่ใจว่าได้เพิ่ม Public Key ของ Jump Host เข้าไปในกฎความปลอดภัย (Security Rules) ของโปรเจกต์ OpenStack ที่เกี่ยวข้อง หากจำเป็น
   - ปรับแต่งค่าใน `deploy/local/ssh_config` บนเครื่อง Local ของคุณให้ชี้ไปยัง Jump Host
   - นำกุญแจ SSH ส่วนตัว (Private Keys) ของคุณไปวางไว้ในโฟลเดอร์ `deploy/local/ssh/`

2. **เตรียม Repository ระยะไกล (Bootstrap the Remote Repository)**:
   - รันคำสั่ง `scripts/control.sh git bootstrap` เพื่อทำการ Clone Repository ลงบน Jump Host
   - กระบวนการนี้จะใช้การตั้งค่าจากไฟล์ `deploy/local/control.env`

3. **ตั้งค่าข้อมูลประจำตัว OpenStack (Configure OpenStack Credentials)**:
   - อัปโหลดไฟล์ `openrc` ของคุณไปยัง Jump Host
   - อัปเดตไฟล์ `deploy/local/openrc.path` บนเครื่อง Local ให้ชี้ไปยังพาธของไฟล์ `openrc` บน Jump Host

## รายละเอียดการเชื่อมต่อ (Connection Details) (`deploy/local/control.env`)

ไฟล์ส่วนตัวนี้กำหนดวิธีการเชื่อมต่อกับ Jump Host:

```bash
# JUMP_HOST: ตัวระบุเป้าหมาย SSH (เช่น user@hostname)
JUMP_HOST="root@10.254.20.100"

# JUMP_HOST_REPO_PATH: ตำแหน่งที่เก็บ Repository บน Jump Host
JUMP_HOST_REPO_PATH="/root/image-build"

# SSH_CONFIG_PATH: พาธไปยังไฟล์ SSH config ที่ใช้งาน
SSH_CONFIG_PATH="deploy/local/ssh_config"
```

## ข้อควรระวังด้านความปลอดภัย (Security Considerations)

- **กุญแจ SSH**: อย่าทำการ Commit กุญแจส่วนตัวของคุณเข้าระบบ ให้เก็บไว้ใน `deploy/local/ssh/`
- **ข้อมูลประจำตัว OpenStack**: อย่าทำการ Commit ไฟล์ `openrc` ของคุณ ให้อ้างอิงตามพาธของไฟล์บน Jump Host ในไฟล์ `deploy/local/openrc.path`
- **ค่าเขียนทับส่วนตัว**: โฟลเดอร์ `deploy/local/` จะถูกละเว้นโดย Git เพื่อป้องกันการหลุดของข้อมูลสภาพแวดล้อมและข้อมูลสำคัญของคุณ
