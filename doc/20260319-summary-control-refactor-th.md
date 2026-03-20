# สรุปการแก้ Controller ให้ใช้งาน Ubuntu 24.04 แบบ End-to-End

## ปัญหาที่พังก่อนแก้
- Controller มีจุดที่ยังหลุดเงื่อนไข ทำให้ flow ใช้งานจริงสะดุดแม้เมนูหลักดูครบ
- Manual แบบระบุ `--action` และ `--version` สามารถหลุดการตรวจว่าเวอร์ชันมีใน manifest จริง
- Runtime config ตรวจไม่ครบ ทำให้บางเคสไปพังช้าใน phase ที่มี side effect แล้ว
- ค่าจากไฟล์ local บางตัวมีอักขระปน (เช่น CRLF) ทำให้ `git sync-safe` บน jump host ล้มเหลว
- การ parse project name ใน preflight มีความเสี่ยงปน log/noise แล้วเทียบชื่อคลาดเคลื่อน

## Regression ที่แก้แล้ว
- เพิ่มการบังคับตรวจเวอร์ชันจาก manifest สำหรับทุก phase ที่ต้องใช้ version (`import/create/configure/clean/publish`)
- ปรับ Manual direct action ให้ run discover ก่อนเมื่อ action นั้นต้องใช้ version
- เพิ่ม runtime validation แบบชัดเจน (local + remote + phase mutating) ให้ fail เร็วก่อน phase ที่แก้ทรัพยากร
- เพิ่ม runtime overlay sync ที่เติมค่า default ที่พิสูจน์แล้วเมื่อค่า local ว่าง
- sanitize ค่า jump-host config ตอนโหลด เพื่อตัด `\r`/space ปลายบรรทัด
- harden preflight project-name parsing ให้ตัด ANSI/log-prefix และเทียบค่า normalized แบบตรงตัว

## Flow สุดท้าย (ใช้งานจริง)
- Main menu คงเดิม: `SSH`, `Git`, `Pipeline`, `Exit`
- Pipeline menu คงเดิม: `Manual`, `Auto by OS`, `Auto by OS Version`, `Status`, `Logs`, `Back`
- ลำดับที่ถูกต้อง:
  1. เตรียม remote repo
  2. download/discover
  3. อ่าน version จาก manifest/summary
  4. ตรวจ/เลือก version
  5. ค่อยรัน phase

## Runtime Config Sync ที่ใช้งานจริง
ไฟล์ที่ sync ไป jump host (เฉพาะ whitelist):
- `deploy/local/guest-access.env`
- `deploy/local/openstack.env`
- `deploy/local/openrc.path`
- `deploy/local/publish.env`
- `deploy/local/clean.env`

สิ่งที่ **ไม่คัดลอกเด็ดขาด**:
- `deploy/local/ssh_config`
- private key ใต้ `deploy/local/ssh/*`

ค่า default ที่เติมเมื่อค่าว่าง:
- `EXPECTED_PROJECT_NAME=natties_op`
- `OPENRC_FILE=/root/openrc-nut`
- `ROOT_USER=root`
- `ROOT_PASSWORD=mis@Pass01`
- `NETWORK_ID=PUBLIC2956`
- `FLAVOR_ID=2-2-0`
- `SECURITY_GROUP=allow-any`
- `VOLUME_TYPE=cinder`
- `VOLUME_SIZE_GB=10`

หมายเหตุ: default ถูกใช้ใน runtime overlay ที่ sync เท่านั้น ไม่ได้เขียนลงไฟล์ tracked

## วิธีใช้หลักสำหรับ Operator
### Git
- `bash scripts/control.sh git bootstrap`
- `bash scripts/control.sh git sync-safe`
- `bash scripts/control.sh git sync-code-overwrite --yes`
- `bash scripts/control.sh git sync-clean --yes`
- `bash scripts/control.sh git status`
- `bash scripts/control.sh git branch`

### Manual (Ubuntu 24.04)
- โหมดเมนู: `bash scripts/control.sh pipeline manual`
- โหมด direct:
  - `bash scripts/control.sh pipeline manual --os ubuntu --action import --version 24.04`

### Auto by OS Version (Ubuntu 24.04)
- `bash scripts/control.sh pipeline auto-by-os-version --os ubuntu --version 24.04`

## สถานะการรองรับ OS
- Implemented จริง: `ubuntu`
- Skeleton / not implemented: `debian`, `centos`, `almalinux`, `rocky`

## ข้อจำกัดที่ยังมี
- หาก infrastructure บังคับให้บางฟิลด์ต้องเป็น UUID เท่านั้น (ไม่รับชื่อ) ต้องระบุ UUID ให้ชัดเจนใน config นั้นโดยตรง
- pipeline จริงยังขึ้นกับสภาพแวดล้อม OpenStack และ resource quota ฝั่งใช้งาน
