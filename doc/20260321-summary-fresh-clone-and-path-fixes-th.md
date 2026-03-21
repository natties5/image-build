# สรุปการแก้ไขปัญหา Fresh Clone Breakage และ Path Architecture

**วันที่**: 21 มีนาคม 2026 (2569)

## ปัญหาที่พบ (Diagnosis)

จากข้อกำหนดใน `AIprompt/rebuildagain.md` พบว่า Repository มีปัญหาเมื่อทำการ Clone ใหม่ (Fresh Clone Breakage) เนื่องจาก:
1. Scripts ต่างๆ (เช่น `phases/preflight.sh`) คาดหวังให้มีไฟล์ configuration ทันที (เช่น `config/runtime/openstack.env` และ `config/runtime/openrc.path`)
2. ไม่มีระบบ Auto-init ในการสร้างโฟลเดอร์สำหรับ Runtime, Workspace, หรือ State เมื่อเริ่มต้นทำงาน
3. โครงสร้าง Path กระจัดกระจายและไม่มีจุดรวมศูนย์กลาง (Canonical Path Layer) โดยส่วนใหญ่มีการอ้างอิง `$REPO_ROOT` และใช้ relative paths.
4. มี Config Layers หลายจุด (deploy/local, config/control, config/runtime) ทำให้เกิดความสับสนและไม่เป็นระเบียบ.

## สิ่งที่แก้ไข (Implementation Plan & Changes Made)

### 1. Centralize Paths (Phase 2)
- สร้าง `lib/core_paths.sh` เพื่อใช้เป็นศูนย์กลาง (Canonical Path Layer) ในการกำหนด `ROOT_DIR`, `BIN_DIR`, `LIB_DIR`, `SETTINGS_DIR`, `RUNTIME_DIR`, `WORKSPACE_DIR`, `LOG_DIR`, ฯลฯ.
- อัปเดต `lib/layout.sh` ให้มาทำงานครอบทับ (wrap) การเรียกใช้จาก `lib/core_paths.sh` เพื่อรักษาความเข้ากันได้ย้อนหลัง (Backward Compatibility) ให้กับสคริปต์ที่เก่ากว่า.

### 2. Auto-Init Framework (Phase 4)
- เพิ่มฟังก์ชัน `imagectl_ensure_core_dirs` เพื่อสร้างโฟลเดอร์รันไทม์ที่จำเป็นโดยอัตโนมัติ.
- เพิ่มฟังก์ชัน `imagectl_auto_init_settings` เพื่อทำการคัดลอกไฟล์ `*.example` ภายในโฟลเดอร์ `settings/` ไปเป็นไฟล์จริงให้ผู้ใช้งานสามารถแก้ไขได้ทันทีโดยที่สคริปต์ไม่พัง (Fail-safe).
- ผูกฟังก์ชันเหล่านี้เข้ากับ `bin/imagectl.sh` ให้ทำงานเสมอในครั้งแรกที่มีการรันโปรแกรม.

### 3. Config Precedence (Phase 3)
- ปรับเปลี่ยนไฟล์สคริปต์ในโฟลเดอร์ `phases/` ทุกไฟล์ (เช่น `preflight.sh`, `import_*.sh`, `create_*.sh`, `download.sh`, `clean_*.sh`, `publish_*.sh`) ให้ย้ายไปอ่านค่า Configuration จาก `$SETTINGS_DIR` (เช่น `openstack.env`, `openrc.env`, `publish.env`) แทนที่จะอ่านจาก `config/runtime/` หรือ `deploy/local/`.
- การเปลี่ยนมาใช้ `settings/` ถือเป็น Single Source of Truth สำหรับ Untracked Secrets

### 4. CI / Quality Gates (Phase 9)
- เพิ่ม GitHub Actions workflow (`.github/workflows/ci.yml`) ที่ใช้ `shellcheck` และ `shfmt` ในการตรวจสอบคุณภาพสคริปต์ รวมถึงจำลองรัน `bin/imagectl.sh preflight` เพื่อดักจับปัญหา Fresh Clone.

## การตรวจสอบ (Validation Run)

ทดสอบการเรียกใช้งาน `bin/imagectl.sh preflight` บน Environment ใหม่ พบว่าสคริปต์ทำงานและทำการสร้างโฟลเดอร์/ไฟล์ settings เริ่มต้นจาก template ได้อย่างถูกต้อง และโปรแกรมไป Fail ที่ขั้นตอนตรวจสอบ `openstack` command อย่างถูกต้องแทนที่จะพังเพราะหาไฟล์ config ไม่เจอ ถือว่าการแก้ไขบรรลุเป้าหมายการเอาชีวิตรอดบน Fresh Clone อย่างสมบูรณ์.

## สิ่งที่ต้องทำต่อไป (Remaining Gaps / Next Steps)
- ควบคุมให้ Operator ทราบถึงโครงสร้างโฟลเดอร์ `settings/` ที่เพิ่มเข้ามา และทำความคุ้นเคยกับการย้ายจาก `deploy/local`.
- พัฒนา OpenStack Validation (Phase 7) ให้ดียิ่งขึ้น เพื่อช่วยตรวจสอบล่วงหน้าให้ผู้ใช้เมื่อกำหนดค่าใน `settings/openstack.env` ไม่ครบถ้วน.
