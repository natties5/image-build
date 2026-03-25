ผมจะเขียนเป็น **ชื่อเมนูภาษาอังกฤษ** และมี **วงเล็บอธิบายไทย** ตามที่คุณต้องการ

---

# แนวคิดหลักของเมนู

เมนูทั้งหมดต้องตอบโจทย์นี้:

* ใช้งานง่าย
* อ่านแล้วรู้ว่าต้องเริ่มตรงไหน
* รองรับทั้งมือใหม่และคนแก้ปัญหา
* ไม่ผูก jump host
* ไม่บังคับให้แก้ไฟล์มือทุกครั้ง
* ดูสถานะและไปต่อจากจุดค้างได้
* ถ้ามีปัญหา ต้องรู้ว่าพังตรงไหนและดู log ได้ทันที

---

# Main Menu (เมนูหลัก)

นี่คือหน้าหลักที่ควรเป็น

1. **Settings (ตั้งค่าและตรวจสอบระบบ)**
2. **Sync (ค้นหา/ดาวน์โหลด Base Image)**
3. **Build (รัน OpenStack Pipeline)**
4. **Resume (ทำต่อจากงานที่ค้าง)**
5. **Status (ดูสถานะ / Logs / Manifests)**
6. **Cleanup (ลบ Resource / เก็บกวาดของค้าง)**
7. **Exit (ออกจากโปรแกรม)**

---

# 1) Settings (ตั้งค่าและตรวจสอบระบบ)

หน้าที่ของเมนูนี้คือ:

* ตรวจว่า `openrc` ใช้งานได้ไหม
* เลือกค่า OpenStack ที่จำเป็นจากระบบจริง
* ตั้งค่า Guest Access
* ดูค่าปัจจุบัน
* validate ทุกอย่างก่อนเริ่มรัน pipeline

## หน้า Settings Menu

1. **Validate OpenStack Auth (ตรวจสอบ OpenStack Login)**
2. **Select Project (เลือก Project)**
3. **Select Network (เลือก Network)**
4. **Select Flavor (เลือก Flavor)**
5. **Select Volume Type (เลือก Volume Type)**
6. **Select Security Group (เลือก Security Group)**
7. **Select Floating Network (เลือก Floating Network)**
8. **Edit Guest Access (ตั้งค่าวิธีเข้า VM)**
9. **Show Current Settings (ดูค่าที่ตั้งไว้ตอนนี้)**
10. **Validate All Settings (ตรวจสอบค่าทั้งหมดก่อนรัน)**
11. **Save Settings (บันทึกค่า)**
12. **Back (กลับ)**

---

## 1.1 Validate OpenStack Auth (ตรวจสอบ OpenStack Login)

### หน้าที่

เช็กว่า user source `openrc` มาแล้ว และใช้ OpenStack ได้จริง

### สิ่งที่ทำ

* เรียก `openstack token issue`
* ดึง project ปัจจุบัน
* แสดงผลว่า auth ผ่านหรือไม่

### ถ้าผ่าน

แสดงประมาณนี้:

* Auth OK
* Current Project
* Current User / Domain ถ้าต้องการ
* Ready to load resources

### ถ้าไม่ผ่าน

แสดงเหตุผลชัด ๆ เช่น:

* OpenRC not loaded
* Token issue failed
* Network/endpoint problem
* Authentication failed

---

## 1.2 Select Project (เลือก Project)

### หน้าที่

อ่านรายชื่อ project จาก OpenStack แล้วให้ผู้ใช้เลือก

### สิ่งที่ทำ

* เรียก list projects
* แสดงเป็นเมนู numbered list
* ผู้ใช้เลือก 1 รายการ
* save ลง `settings/openstack.env`

### ค่าที่บันทึก

เช่น:

* `OS_PROJECT_NAME`
* หรือ `PROJECT_ID`

### หน้าจอควรแสดง

* project name
* project id
* optional domain ถ้ามี

---

## 1.3 Select Network (เลือก Network)

### หน้าที่

ให้ผู้ใช้เลือก network สำหรับสร้าง VM

### สิ่งที่ทำ

* เรียก list networks
* แสดงชื่อ + id
* ผู้ใช้เลือก
* บันทึกเป็น `NETWORK_ID`

---

## 1.4 Select Flavor (เลือก Flavor)

### หน้าที่

ให้ผู้ใช้เลือก flavor ที่ใช้สร้าง VM

### สิ่งที่ทำ

* list flavors
* แสดงชื่อ + vCPU + RAM + Disk
* ผู้ใช้เลือก
* save เป็น `FLAVOR_ID`

### ทำไมควรแสดง detail

เพราะ user จะได้ไม่ต้องจำว่า flavor ไหนแรงพอ

---

## 1.5 Select Volume Type (เลือก Volume Type)

### หน้าที่

เลือกชนิด volume ที่จะใช้สร้าง boot volume

### สิ่งที่ทำ

* list volume types
* ผู้ใช้เลือก
* save เป็น `VOLUME_TYPE`

---

## 1.6 Select Security Group (เลือก Security Group)

### หน้าที่

เลือก security group ของ VM

### สิ่งที่ทำ

* list security groups
* ผู้ใช้เลือก
* save เป็น `SECURITY_GROUP`

---

## 1.7 Select Floating Network (เลือก Floating Network)

### หน้าที่

เลือก network ที่ใช้ allocate floating IP

### สิ่งที่ทำ

* list external / floating networks
* ผู้ใช้เลือก
* save เป็น `FLOATING_NETWORK`

### หมายเหตุ

ข้อนี้อาจปล่อยว่างได้ ถ้าใช้ fixed IP อย่างเดียว

---

## 1.8 Edit Guest Access (ตั้งค่าวิธีเข้า VM)

อันนี้คือหน้าที่คุณถามเมื่อกี้ ผมจะสรุปให้รวมอยู่ในเมนูใหญ่เลย

### หน้าที่

ตั้งค่า **วิธีที่ระบบจะ SSH เข้า VM** หลังจากสร้างเสร็จ
ใช้กับ phase:

* Configure
* Clean
* Validate
* Reconnect after reboot

## หน้า Edit Guest Access Menu

1. **Set Auth Mode (เลือกรูปแบบการเข้า VM)**
2. **Set SSH User (ตั้งชื่อผู้ใช้ SSH)**
3. **Set SSH Port (ตั้งพอร์ต SSH)**
4. **Set Root Password (ตั้งรหัสผ่าน root)**
5. **Set Private Key Path (ตั้ง path ของ private key)**
6. **Set Root Authorized Key (ตั้ง public key สำหรับ root)**
7. **Set Root SSH Policy (ตั้งค่านโยบาย Root SSH)**
8. **Show Current Guest Access (ดูค่าปัจจุบันของ Guest Access)**
9. **Validate Guest Access Config (ตรวจค่าของ Guest Access)**
10. **Save Guest Access (บันทึกค่า Guest Access)**
11. **Back (กลับ)**

---

### 1.8.1 Set Auth Mode (เลือกรูปแบบการเข้า VM)

ค่า:

* `password` = ใช้รหัสผ่าน
* `key` = ใช้ private key

บันทึกเป็น:

* `SSH_AUTH_MODE`

---

### 1.8.2 Set SSH User (ตั้งชื่อผู้ใช้ SSH)

ปกติใช้:

* `root`

บันทึกเป็น:

* `SSH_USER`

---

### 1.8.3 Set SSH Port (ตั้งพอร์ต SSH)

ปกติ:

* `22`

บันทึกเป็น:

* `SSH_PORT`

---

### 1.8.4 Set Root Password (ตั้งรหัสผ่าน root)

ใช้เมื่อ:

* `SSH_AUTH_MODE=password`

บันทึกเป็น:

* `ROOT_PASSWORD`

---

### 1.8.5 Set Private Key Path (ตั้ง path ของ private key)

ใช้เมื่อ:

* `SSH_AUTH_MODE=key`

บันทึกเป็น:

* `SSH_PRIVATE_KEY`

ตัวอย่างบน Git Bash/Windows:

* `/c/Users/natti/.ssh/id_rsa`

---

### 1.8.6 Set Root Authorized Key (ตั้ง public key สำหรับ root)

ใช้เมื่อ:

* ต้องการให้ guest รับ key เข้า root

บันทึกเป็น:

* `ROOT_AUTHORIZED_KEY`

---

### 1.8.7 Set Root SSH Policy (ตั้งค่านโยบาย Root SSH)

หน้านี้ย่อยควรมี:

1. **Enable Root SSH (อนุญาตให้ root เข้า SSH ได้)**
2. **Permit Root Login (อนุญาตให้ root login ได้)**
3. **Enable Password Authentication (อนุญาต login ด้วยรหัสผ่าน)**
4. **Enable Public Key Authentication (อนุญาต login ด้วย key)**
5. **Back (กลับ)**

ค่าที่บันทึก:

* `ENABLE_ROOT_SSH`
* `SSH_PERMIT_ROOT_LOGIN`
* `SSH_PASSWORD_AUTH`
* `SSH_PUBKEY_AUTH`

---

### 1.8.8 Show Current Guest Access (ดูค่าปัจจุบันของ Guest Access)

ควรแสดง:

* Auth Mode
* SSH User
* SSH Port
* Root Password: hidden/masked
* Private Key Path
* Root Authorized Key: show short preview
* Root SSH Policy

---

### 1.8.9 Validate Guest Access Config (ตรวจค่าของ Guest Access)

logic ที่ควรเช็ก:

* ถ้า mode = `password` ต้องมี `ROOT_PASSWORD`
* ถ้า mode = `key` ต้องมี `SSH_PRIVATE_KEY`
* ถ้า key mode แล้ว `ROOT_AUTHORIZED_KEY` ว่าง ให้ warning
* SSH port ต้องเป็นเลข
* user ต้องไม่ว่าง

---

## 1.9 Show Current Settings (ดูค่าที่ตั้งไว้ตอนนี้)

ควรสรุปเป็นหน้ารวมว่า:

* Project
* Network
* Flavor
* Volume Type
* Security Group
* Floating Network
* Guest Access
* Current auth status

---

## 1.10 Validate All Settings (ตรวจสอบค่าทั้งหมดก่อนรัน)

### หน้าที่

เช็กทุกอย่างทีเดียวก่อนเข้า Sync หรือ Build

### Checklist ที่ควรเช็ก

* OpenStack auth ผ่าน
* Project ถูกเลือกแล้ว
* Network ถูกเลือกแล้ว
* Flavor ถูกเลือกแล้ว
* Volume Type ถูกเลือกแล้ว
* Security Group ถูกเลือกแล้ว
* Guest Access พร้อม
* Path/config ที่จำเป็นครบ

---

## 1.11 Save Settings (บันทึกค่า)

บันทึกลงไฟล์:

* `settings/openstack.env`
* `settings/guest-access.env`

---

# 2) Sync (ค้นหา/ดาวน์โหลด Base Image)

เมนูนี้ใช้กับระบบ auto-discovery download ที่เราคุยกันไว้แล้ว

## หน้า Sync Menu

1. **Dry-run Discover by OS (ลองค้นหา Image ตาม OS แบบไม่โหลดจริง)**
2. **Dry-run Discover by OS and Version (ลองค้นหาแบบระบุ OS และ Version)**
3. **Download by OS (ดาวน์โหลดทุก Version ที่ track ไว้ของ OS นั้น)**
4. **Download by OS and Version (ดาวน์โหลดเฉพาะ OS และ Version ที่เลือก)**
5. **Show Sync Results (ดูผลการค้นหา/ดาวน์โหลดล่าสุด)**
6. **Show Sync Logs (ดู Log ของ Sync)**
7. **Clear Sync Failed State (ล้างสถานะ Sync ที่ fail)**
8. **Back (กลับ)**

---

## 2.1 Dry-run Discover by OS

### หน้าที่

* อ่าน `config/os/<os>/sync.env`
* discovery image candidate
* ไม่โหลดจริง
* เขียน runtime JSON + state

### ควรแสดง

* version
* filename ที่จะเลือก
* format (`img/qcow2`)
* checksum source
* download URL
* status

---

## 2.2 Dry-run Discover by OS and Version

เหมือนข้อบน แต่ให้ user เลือก version เฉพาะ

---

## 2.3 Download by OS

### หน้าที่

* discovery ก่อน
* โหลดจริงทุก tracked versions
* verify checksum
* เขียน state เป็น ready เมื่อสำเร็จ

---

## 2.4 Download by OS and Version

โหลดจริงเฉพาะตัวเดียว

---

## 2.5 Show Sync Results

แสดง:

* discovered/cached/downloaded/failed
* local path
* checksum
* chosen image format

---

## 2.6 Show Sync Logs

อ่าน log ที่เกี่ยวข้อง

---

## 2.7 Clear Sync Failed State

ล้าง flag fail และ state เก่าที่ไม่อยากใช้ต่อ

---

# 3) Build (รัน OpenStack Pipeline)

เมนูนี้คือแกนของระบบ build จริง

## หน้า Build Menu

1. **Run Full Pipeline (รันทั้งเส้นตั้งแต่ Base Image ถึง Final Image)**
2. **Run Step-by-Step (รันทีละขั้น)**
3. **Back (กลับ)**

---

## 3.1 Run Full Pipeline (รันทั้งเส้น)

ควรเรียงตามนี้:

1. Import Base Image
2. Create Volume
3. Create VM
4. Configure Guest
5. Final Clean
6. Publish Final Image

### ก่อนรัน

ควรเช็ก:

* settings พร้อม
* sync result พร้อม
* openrc auth พร้อม

---

## 3.2 Run Step-by-Step (รันทีละขั้น)

หน้าย่อยควรเป็น:

1. **Import Base Image (นำ Base Image เข้า Glance)**
2. **Create Volume (สร้าง Volume จาก Base Image)**
3. **Create VM (สร้าง VM จาก Volume)**
4. **Configure Guest (เข้าไปตั้งค่า Guest OS)**
5. **Final Clean (ล้างเครื่องก่อนทำ Final Image)**
6. **Publish Final Image (อัปโหลดเป็น Final Image)**
7. **Back (กลับ)**

---

## 3.2.1 Import Base Image

ใช้ phase import

* local image -> glance image base

## 3.2.2 Create Volume

* create boot volume จาก base image

## 3.2.3 Create VM

* create server from volume
* attach floating IP ถ้าต้องใช้

## 3.2.4 Configure Guest

* เข้า guest
* baseline official repo
* LEGACY_MIRROR failover
* update/upgrade
* root SSH policy
* locale/timezone/cloud-init policy

## 3.2.5 Final Clean

* clean cloud-init
* clear cache/history/logs
* reset machine-id
* remove host keys
* poweroff

## 3.2.6 Publish Final Image

* delete server if needed
* wait volume available
* `cinder upload-to-image`
* set metadata/tags
* delete volume / base image ตาม policy

---

# 4) Resume (ทำต่อจากงานที่ค้าง)

เมนูนี้สำคัญมาก เพราะ pipeline ของคุณยาวและบางขั้นนาน

## หน้า Resume Menu

1. **Resume Last Failed Run (ทำต่อจากงานล่าสุดที่ fail)**
2. **Resume by OS and Version (เลือก OS/Version ที่จะทำต่อ)**
3. **Resume from Import (เริ่มต่อจาก Import)**
4. **Resume from Create (เริ่มต่อจาก Create)**
5. **Resume from Configure (เริ่มต่อจาก Configure)**
6. **Resume from Publish (เริ่มต่อจาก Publish)**
7. **Back (กลับ)**

---

## หลักคิด

เมนูนี้ต้องอ่านจาก:

* runtime flags
* runtime JSON

แล้วตอบได้ว่า:

* phase ล่าสุดคืออะไร
* พร้อมไปต่อจากตรงไหน
* resource จริงยังอยู่ไหม

---

# 5) Status (ดูสถานะ / Logs / Manifests)

เมนูนี้ไว้ “มองภาพรวม” และ “debug”

## หน้า Status Menu

1. **Dashboard (ดูภาพรวมทั้งหมด)**
2. **Show Sync State (ดูสถานะ Sync)**
3. **Show Build State (ดูสถานะ Build)**
4. **Show Configure State (ดูสถานะ Configure)**
5. **Show Publish State (ดูสถานะ Publish)**
6. **Show Runtime JSON (ดูไฟล์ JSON ของแต่ละ Phase)**
7. **Show Logs (ดู Log ของแต่ละ Phase)**
8. **Back (กลับ)**

---

## 5.1 Dashboard

ควรแสดงแบบย่อว่า:

* OS / version ที่ tracked
* sync state
* base image state
* vm state
* final image state
* last failed phase
* current log path

---

## 5.2 Show Sync State

ดู state/manifest ของ sync phase

## 5.3 Show Build State

ดู state รวมของ import/create/build

## 5.4 Show Configure State

ดู configure JSON และ summary

## 5.5 Show Publish State

ดู final image publish state

## 5.6 Show Runtime JSON

เปิด runtime JSON ตาม phase:

* sync
* import
* create
* configure
* publish

## 5.7 Show Logs

เลือกดู log file ตาม phase

---

# 6) Cleanup (ลบ Resource / เก็บกวาดของค้าง)

เมนูนี้เอาไว้แก้ของค้างใน OpenStack

## หน้า Cleanup Menu

1. **Delete Server (ลบ Server)**
2. **Delete Volume (ลบ Volume)**
3. **Delete Base Image (ลบ Base Image)**
4. **Delete Final Image (ลบ Final Image)**
5. **Cleanup Current Run Resources (ลบ Resource ของรอบล่าสุด)**
6. **Reconcile Orphan Resources (หาของค้างแล้วช่วยจัดการ)**
7. **Back (กลับ)**

---

## 6.1 Delete Server

ให้เลือกจาก:

* current run
* เลือกจาก list
* พิมพ์ชื่อ/ID

## 6.2 Delete Volume

เหมือนกัน

## 6.3 Delete Base Image

ลบ image stage base

## 6.4 Delete Final Image

ลบ final image

## 6.5 Cleanup Current Run Resources

ลบสิ่งที่ผูกกับ runtime ล่าสุด เช่น:

* server
* volume
* base image (optional)
* floating IP (ถ้าจะรองรับในอนาคต)

## 6.6 Reconcile Orphan Resources

ไว้เช็กว่า:

* server ค้างไหม
* volume ค้างไหม
* base image ค้างไหม
* final image มีแต่ state ไม่มีไหม
* state มีแต่ resource หายไหม

---

# 7) Exit (ออกจากโปรแกรม)

ไม่มีอะไรซับซ้อน แค่ออกให้สะอาด

---

# ลำดับการใช้งานของ user ที่ดีที่สุด

## กรณีเริ่มใหม่

1. Settings
2. Validate OpenStack Auth
3. เลือก Project / Network / Flavor / Volume Type / Security Group
4. Edit Guest Access
5. Validate All Settings
6. Sync -> Dry-run
7. Sync -> Download
8. Build -> Run Full Pipeline
9. Status -> Dashboard / Logs

## กรณีงานค้าง

1. Status -> Dashboard
2. Resume
3. เลือก phase ที่จะไปต่อ
4. ถ้าทรัพยากรค้างแปลก ๆ -> Cleanup

---

# สิ่งที่เมนูนี้ดีกว่าเมนูเดิม

เมนูเดิมใน repo ตอนนี้ยังเป็น:

* System
* Run
* Resume
* Cleanup
* Status
  และข้างในมี SSH/Git/jump host เยอะ 

เมนูใหม่ที่ผมสรุปให้:

* ตรงกับ target architecture ใหม่
* ไม่มี jump host
* ไม่มี Git sync / bootstrap
* menu สะท้อน phase จริงของระบบ
* รองรับ OpenStack settings discovery
* รองรับ dry-run
* รองรับ resume และ cleanup แบบ production กว่าเดิม

---

# สรุปสั้นที่สุด

เมนูทั้งหมดที่ผมแนะนำคือ:

* **Settings (ตั้งค่าและตรวจสอบระบบ)**
* **Sync (ค้นหา/ดาวน์โหลด Base Image)**
* **Build (รัน OpenStack Pipeline)**
* **Resume (ทำต่อจากงานที่ค้าง)**
* **Status (ดูสถานะ / Logs / Manifests)**
* **Cleanup (ลบ Resource / เก็บกวาดของค้าง)**
* **Exit (ออกจากโปรแกรม)**

และในหน้า **Edit Guest Access (ตั้งค่าวิธีเข้า VM)** ควรมี:

* Auth Mode
* SSH User
* SSH Port
* Root Password
* Private Key Path
* Root Authorized Key
* Root SSH Policy
* Validate
* Save

