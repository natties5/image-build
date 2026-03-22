# Image Build Project Design Pack

เอกสารชุดนี้คือการสรุปใหม่ทั้งโปรเจกต์ `image-build` ให้เป็น **portable, menu-driven, OpenStack image build pipeline** สำหรับใช้เป็นฐานให้ AI/Codex เขียนโปรเจกต์ต่อใน VS Code

## เป้าหมายหลัก
- รันได้บน Linux/Bash
- ทดสอบ/พัฒนาผ่าน VS Code + Git Bash บน Windows ได้
- ไม่ผูก jump host
- ไม่มี `deploy/local/*`
- ใช้ `scripts/control.sh` เป็น entrypoint หลัก
- ใช้ `openrc` เฉพาะตอนรัน ไม่เก็บถาวรใน repo
- ใช้ไฟล์ `settings/openstack.env` เป็น OpenStack settings ชุดเดียว
- ใช้ไฟล์ `settings/guest-access.env` สำหรับวิธีเข้า guest VM
- phase แรกที่ต้องเสถียรคือ `sync_download` แบบ dry-run ได้
- ทั้งระบบต้องมี menu, state, log, JSON manifests, cleanup, resume, และ reconcile

## สารบัญเอกสาร
1. `01_START_PROJECT_BLUEPRINT.md`  
   ภาพรวมโครงการ, เป้าหมาย, โครงสร้างไฟล์ final, ทิศทางที่ถูก/ผิด, หลักการตั้งต้นทั้งหมด

2. `02_DOWNLOAD_IMAGE_SYSTEM.md`  
   ระบบ sync/download image แบบ rule-driven auto-discovery พร้อม dry-run, checksum, state, manifest

3. `03_GUEST_OS_CONFIG_SYSTEM.md`  
   ระบบ guest config แยกตาม OS/version, OLS failover, final clean, AI-driven config loop

4. `04_ENV_AND_RUNTIME_MODEL.md`  
   อธิบาย `.env`, `.json`, flag files, state directories, runtime output model

5. `05_CONFIG_SCHEMA_REFERENCE.md`  
   schema ของ `sync.env`, `default.env`, `<version>.env`, `settings/openstack.env`, `settings/guest-access.env`

6. `06_OPENSTACK_PIPELINE_DESIGN.md`  
   OpenStack pipeline แบบ command-by-command ตั้งแต่ preflight ถึง publish และ cleanup

7. `07_MENU_DESIGN.md`  
   เมนูทั้งหมดของระบบ รวม Settings / Sync / Build / Resume / Status / Cleanup และ Edit Guest Access

8. `08_HELPER_LIBRARIES_DESIGN.md`  
   design spec ของ `lib/common_utils.sh` และ `lib/openstack_api.sh`

9. `09_IMPLEMENTATION_ROADMAP.md`  
   ลำดับการลงมือทำ, milestone, dependency order, definition of done

10. `10_AI_IMPLEMENTATION_NOTES.md`  
    หมายเหตุสำหรับใช้กับ AI/Codex, style guide, what to preserve, what to delete, guardrails

## ลำดับอ่านที่แนะนำ
1. `01_START_PROJECT_BLUEPRINT.md`
2. `05_CONFIG_SCHEMA_REFERENCE.md`
3. `07_MENU_DESIGN.md`
4. `02_DOWNLOAD_IMAGE_SYSTEM.md`
5. `03_GUEST_OS_CONFIG_SYSTEM.md`
6. `06_OPENSTACK_PIPELINE_DESIGN.md`
7. `08_HELPER_LIBRARIES_DESIGN.md`
8. `09_IMPLEMENTATION_ROADMAP.md`
9. `10_AI_IMPLEMENTATION_NOTES.md`

## จุดยืนของชุดเอกสารนี้
- ไม่ใช่ jump host architecture
- ไม่เน้น compatibility กับ flow เก่าที่รก
- เน้น portable, local-first, menu-driven
- ใช้ Bash เป็นหลัก แต่แยก responsibility ให้ชัด
- ใช้ `.env` เป็น input config
- ใช้ `.json` เป็น runtime result
- ใช้ flag files เป็น quick state
