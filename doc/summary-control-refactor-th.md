# สรุปการแก้บั๊ก Runtime Config Sync (สำหรับ Operator)

## บั๊กคืออะไร

จากการรันจริงใน `Pipeline -> Auto by OS -> ubuntu` พบว่า:

- `download/discover` ผ่าน
- `preflight` ผ่าน
- `import` ผ่าน
- `create` ล้มเหลวด้วย `ERROR: ROOT_PASSWORD is empty`

## ทำไมถึงเกิด

Controller เดิม bootstrap/sync เฉพาะโค้ด repo บน jump host ผ่าน git
แต่ไฟล์ local-only ใต้ `deploy/local/` เป็น gitignored จึงไม่ถูก clone/sync ไปที่ jump host

phase บน remote จะ `source` ค่าใน `deploy/local/*.env` (เช่น `guest-access.env`)
เมื่อไฟล์นี้ไม่มีบน jump host ค่า `ROOT_PASSWORD` จึงว่าง แล้ว fail ตอน `create`

## แก้อะไรไปแล้ว

1. เพิ่มแนวคิด **remote runtime config sync** ใน controller
2. เพิ่มการตรวจสอบ dependency ก่อน phase ที่เปลี่ยนระบบ (mutating phases)
3. เพิ่มการ sync ไฟล์ runtime config ที่จำเป็นจาก local ไป remote อย่างจำกัดและปลอดภัย
4. เพิ่มการตรวจสอบฝั่ง remote หลัง sync ว่าไฟล์/ค่าจำเป็นมีจริงก่อนรัน pipeline ต่อ

## ตอนนี้ sync อะไรไป jump host บ้าง

Controller จะ sync เฉพาะไฟล์ runtime config ที่จำเป็น (ถ้ามีไฟล์นั้นใน local):

- `deploy/local/guest-access.env`
- `deploy/local/openstack.env`
- `deploy/local/openrc.path`
- `deploy/local/publish.env`
- `deploy/local/clean.env`

ปลายทางบน jump host:

- `<JUMP_HOST_REPO_PATH>/deploy/local/`

## อะไรที่ยัง local-only และจะไม่ถูก copy เด็ดขาด

- `deploy/local/ssh_config`
- `deploy/local/ssh/*` (private keys)

Controller ไม่ sync SSH private key และไม่ sync local SSH config ไป jump host

## พฤติกรรมใหม่ของ flow

### Auto by OS

ก่อนเริ่มรัน phase แบบเต็ม Controller จะ:

1. validate local runtime config (รวม `ROOT_PASSWORD`)
2. sync runtime config ที่จำเป็นไป jump host
3. validate ฝั่ง remote ว่าไฟล์/ค่าจำเป็นพร้อม
4. ค่อยเริ่ม phase pipeline (`preflight -> import -> create -> configure -> clean -> publish`)

ผลคือ ถ้า `ROOT_PASSWORD` หาย จะ fail ก่อน `import` ไม่ใช่ไปรันสร้าง resource ก่อนแล้วค่อยพัง

### Auto by OS Version

ใช้หลักเดียวกัน: validate local -> sync -> validate remote -> แล้วค่อยรัน full pipeline ของเวอร์ชันที่เลือก

### Manual

สำหรับ action ที่ต้องใช้ guest access (`create`, `configure`) Controller จะ validate+sync ก่อนรัน
ถ้าค่าจำเป็นหาย จะแจ้งชัดเจนว่าไฟล์/ค่าที่ขาดคืออะไรและต้องแก้ที่ไหน

## วิธีใช้งานสำหรับ Operator

1. กรอกไฟล์ local-only ให้ครบ โดยเฉพาะ `deploy/local/guest-access.env` และ `ROOT_PASSWORD`
2. ใช้ flow ปกติผ่าน `scripts/control.sh` (SSH/Git/Pipeline)
3. Controller จะจัดการ validate/sync runtime config อัตโนมัติก่อน phase ที่จำเป็น
4. ถ้าขึ้น error ว่าขาดไฟล์/ค่า ให้แก้ใน `deploy/local/*.env` ฝั่ง local แล้วรันใหม่
