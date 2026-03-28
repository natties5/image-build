# Checklist Current Plan

เอกสารนี้ใช้สำหรับเช็คระบบตาม pipeline ปัจจุบันว่าแต่ละ phase ผ่านหรือไม่ผ่าน พร้อมใช้บันทึกผลเทสจริงทีละรอบ

สถานะที่ใช้:
- `[ ]` ยังไม่ผ่าน / ยังไม่ทำ
- `[x]` ผ่าน
- `[~]` ทำไปบางส่วนแล้ว
- `[-]` ไม่เกี่ยวข้องกับรอบเทสนี้

---

## 1) PHASE 0: Input intake and normalization

### 1.1 Input definition
- [ ] มีการกำหนด input หลักของระบบชัดเจน
- [ ] รองรับ os_family
- [ ] รองรับ distro
- [ ] รองรับ version
- [ ] รองรับ release_name หรือ alias
- [ ] รองรับ architecture
- [ ] รองรับ image_format
- [ ] รองรับ image_type
- [ ] รองรับ target_openstack_profile
- [ ] รองรับ execution mode
- [ ] รองรับ dry-run flag
- [ ] รองรับ upload flag
- [ ] รองรับ validation flag

### 1.2 Input normalization
- [ ] แปลง alias เป็น canonical ได้
- [ ] normalize case/spacing/format ได้
- [ ] normalize architecture ได้
- [ ] normalize format ได้
- [ ] normalize release alias ได้
- [ ] ได้ normalized_input object กลาง

### 1.3 Input validation
- [ ] ตรวจ field บังคับครบได้
- [ ] ตรวจ version format ได้
- [ ] ตรวจ distro support ได้
- [ ] ตรวจ arch support ได้
- [ ] ตรวจ target profile มีอยู่จริง
- [ ] reject invalid input ได้อย่างชัดเจน
- [ ] log สาเหตุการ reject ได้

---

## 2) PHASE 1: Policy loading and source mapping

### 2.1 Config loading
- [ ] โหลด global config ได้
- [ ] โหลด OS-specific config ได้
- [ ] โหลด version-specific config ได้เมื่อจำเป็น
- [ ] โหลด profile-specific config ได้
- [ ] merge config เป็น effective_policy ได้
- [ ] override config ทำงานถูกต้อง

### 2.2 Source policy
- [ ] มี mapping OS/version → official source
- [ ] มี mapping checksum source
- [ ] มี mapping filename pattern
- [ ] มี mapping image type/format policy
- [ ] มี mapping pipeline policy
- [ ] policy conflict ถูก detect ได้

### 2.3 Policy validation
- [ ] reject target ที่ไม่มี mapping ได้
- [ ] reject target ที่ policy conflict ได้
- [ ] ระบุได้ว่าต้องใช้ pipeline ไหน
- [ ] ระบุได้ว่าต้องใช้ source channel ไหน

---

## 3) PHASE 2: Official source discovery

### 3.1 Source access
- [ ] เข้าถึง official source endpoint ได้
- [ ] รองรับ HTML/index/manifest/checksum source
- [ ] ดึง candidate list ได้
- [ ] ดึง metadata ที่จำเป็นได้

### 3.2 Candidate extraction
- [ ] extract filename ได้
- [ ] extract URL ได้
- [ ] extract arch ได้
- [ ] extract format ได้
- [ ] extract release/version clues ได้
- [ ] extract checksum reference ได้

### 3.3 Candidate filtering
- [ ] filter ตาม OS family ได้
- [ ] filter ตาม distro ได้
- [ ] filter ตาม version ได้
- [ ] filter ตาม release alias ได้
- [ ] filter ตาม arch ได้
- [ ] filter ตาม format ได้
- [ ] filter ตาม image type ได้

### 3.4 Strict source selection
- [ ] ไม่มี fuzzy match ที่เสี่ยง
- [ ] ไม่มี multiple candidate ที่ปล่อยผ่านแบบเดา
- [ ] เลือก final candidate ได้พร้อมเหตุผล
- [ ] บันทึกเหตุผลการเลือก source ได้
- [ ] reject ambiguity ได้

---

## 4) PHASE 3: Version resolution and version guard

### 4.1 Version extraction
- [ ] parse version จาก filename ได้
- [ ] parse version จาก metadata ได้
- [ ] parse release alias ได้
- [ ] map alias → canonical version ได้

### 4.2 Version normalization
- [ ] normalize major/minor/patch ได้
- [ ] normalize release alias ได้
- [ ] compare version แบบ consistent ได้
- [ ] เทียบ requested version กับ source version ได้

### 4.3 Consistency validation
- [ ] filename version ตรงกับ metadata
- [ ] metadata version ตรงกับ policy
- [ ] release alias ตรงกับ canonical version
- [ ] checksum record ผูกกับ artifact เดียวกันได้

### 4.4 Version guard
- [ ] reject ambiguous version ได้
- [ ] reject conflicting metadata ได้
- [ ] reject version mismatch ได้
- [ ] reject release alias ที่แมปไม่ชัดได้
- [ ] freeze resolved version ลง state ได้

### 4.5 Version persistence
- [ ] บันทึก resolved_version ได้
- [ ] บันทึก resolved_release_name ได้
- [ ] บันทึก resolved_filename ได้
- [ ] บันทึก resolved_source_url ได้
- [ ] บันทึก resolved_checksum ได้
- [ ] บันทึก evidence ว่า version มาจากอะไรได้

---

## 5) PHASE 4: Dry-run planning and state persistence

### 5.1 Dry-run behavior
- [ ] มีโหมด dry-run จริง
- [ ] dry-run ไม่ download จริง
- [ ] dry-run ไม่ build จริง
- [ ] dry-run ไม่ upload จริง
- [ ] dry-run แสดง execution intent ครบ

### 5.2 Execution plan generation
- [ ] สร้าง download plan ได้
- [ ] สร้าง cache path ได้
- [ ] สร้าง work path ได้
- [ ] สร้าง artifact path ได้
- [ ] สร้าง report path ได้
- [ ] เลือก pipeline id ได้
- [ ] ระบุ OpenStack target ได้
- [ ] ระบุ validation plan ได้

### 5.3 Identity and plan keys
- [ ] สร้าง plan_id ได้
- [ ] สร้าง cache_key ได้
- [ ] สร้าง source_fingerprint ได้
- [ ] สร้าง input_fingerprint ได้
- [ ] key มีความเสถียร

### 5.4 Dry-run persistence
- [ ] save plan ลง state ได้
- [ ] reload plan ได้
- [ ] human-readable dry-run report ถูกสร้างได้
- [ ] detect state mismatch ได้
- [ ] detect input mismatch ได้
- [ ] detect version mismatch หลัง dry-run ได้

---

## 6) PHASE 5: Cache analysis and local storage preparation

### 6.1 Directory structure
- [ ] สร้างโครงสร้างโฟลเดอร์หลักได้
- [ ] แยก cache ออกจาก work ได้
- [ ] แยก artifacts ออกจาก reports ได้
- [ ] แยก state ออกจาก logs ได้
- [ ] path deterministic

### 6.2 Cache lookup
- [ ] หา cache จาก source URL ได้
- [ ] หา cache จาก version ได้
- [ ] หา cache จาก checksum ได้
- [ ] หา cache จาก arch/format ได้

### 6.3 Cache verification
- [ ] verify filename ได้
- [ ] verify checksum ได้
- [ ] verify file readable ได้
- [ ] verify size สมเหตุสมผลได้
- [ ] verify metadata ตรงกับ state ได้

### 6.4 Cache decision
- [ ] ตัดสิน HIT ได้
- [ ] ตัดสิน MISS ได้
- [ ] ตัดสิน INVALID ได้
- [ ] ตัดสิน STALE ได้
- [ ] ไม่ reuse cache ข้าม version
- [ ] ไม่ reuse cache ข้าม arch
- [ ] ไม่ reuse cache ข้าม source โดยไม่ verify

---

## 7) PHASE 6: Controlled download execution

### 7.1 Download gating
- [ ] block การ download ถ้าไม่มี dry-run state
- [ ] block การ download ถ้า state ไม่ครบ
- [ ] block การ download ถ้า source mismatch
- [ ] block การ download ถ้า version mismatch
- [ ] block การ download ถ้า checksum expectation เปลี่ยน

### 7.2 Download execution
- [ ] download ไป temp path ได้
- [ ] retry ได้อย่างปลอดภัย
- [ ] resume ได้เมื่อ policy อนุญาต
- [ ] promote ไฟล์เข้า cache จริงได้หลัง verify

### 7.3 Post-download verification
- [ ] verify checksum หลังโหลดได้
- [ ] verify size หลังโหลดได้
- [ ] verify filename ได้
- [ ] verify readable format ได้
- [ ] verify checksum manifest consistency ได้เมื่อมี

### 7.4 Failure handling
- [ ] fail แล้วไม่ทำให้ state มั่ว
- [ ] fail แล้ว rerun ต่อได้
- [ ] log error ชัดเจน
- [ ] แยก network failure กับ checksum failure ได้
- [ ] แยก source failure กับ state mismatch ได้

---

## 8) PHASE 7: Build / transform / customization pipeline

### 8.1 Pipeline selection
- [ ] เลือก pipeline ตาม OS family ได้
- [ ] เลือก pipeline ตาม distro ได้
- [ ] เลือก pipeline ตาม version ได้
- [ ] เลือก pipeline ตาม source format ได้
- [ ] เลือก pipeline ตาม target artifact format ได้

### 8.2 Work area preparation
- [ ] สร้าง work directory แยกต่อ plan/job ได้
- [ ] ไม่ชนกับงานอื่น
- [ ] cleanup ได้เมื่อจำเป็น

### 8.3 Build steps
- [ ] decompress ได้
- [ ] convert format ได้
- [ ] resize ได้เมื่อจำเป็น
- [ ] inject config ได้
- [ ] apply OS-specific customization ได้
- [ ] ป้องกัน cross-distro misuse ได้

### 8.4 Intermediate validation
- [ ] ตรวจว่า image ยังอ่านได้
- [ ] ตรวจว่า format ถูกต้อง
- [ ] ตรวจว่าไม่มี corruption
- [ ] ตรวจว่า expected config อยู่ครบ

### 8.5 Artifact generation
- [ ] สร้าง final artifact ได้
- [ ] ตั้งชื่อ artifact ได้เป็นระบบ
- [ ] ผูก artifact กับ source/version ได้
- [ ] คำนวณ artifact checksum ได้
- [ ] สร้าง build manifest ได้
- [ ] สร้าง build report ได้

### 8.6 Build safety
- [ ] ไม่ใช้ pipeline ผิด OS/version
- [ ] ไม่ทำให้ image boot พังโดยไม่รู้ตัว
- [ ] ไม่ทำลาย metadata สำคัญ
- [ ] fail ได้อย่างชัดเจนเมื่อ customization ขัดกับ guest OS

---

## 9) PHASE 8: Guest OS profile and access resolution

### 9.1 Guest mapping
- [ ] map OS/version → default username ได้
- [ ] map OS/version → auth mode ได้
- [ ] map OS/version → cloud-init expectation ได้
- [ ] map OS/version → guest-agent expectation ได้

### 9.2 Guest profile generation
- [ ] สร้าง guest_profile object ได้
- [ ] ระบุ access_strategy ได้
- [ ] ระบุ fallback path ได้
- [ ] ระบุ console fallback ได้เมื่อเกี่ยวข้อง

### 9.3 Access validation readiness
- [ ] ตรวจได้ว่าขั้นตอน build ไม่ทำลาย access profile
- [ ] authorized key path ถูกต้อง
- [ ] cloud-init expectation ยังใช้ได้
- [ ] network config ไม่ขัดกับ first boot

### 9.4 Guest validation outputs
- [ ] มี guest_validation_expectation สำหรับ phase ทดสอบจริง
- [ ] มี evidence ว่าทำไมเลือก access method นี้

---

## 10) PHASE 9: OpenRC and OpenStack context resolution

### 10.1 OpenRC handling
- [ ] load OpenRC ได้
- [ ] อ่าน auth URL ได้
- [ ] อ่าน username/user domain ได้
- [ ] อ่าน project/project domain ได้
- [ ] อ่าน region ได้
- [ ] อ่าน interface/endpoint scope ได้เมื่อมี

### 10.2 Authentication
- [ ] auth ผ่านจริง
- [ ] token/context ใช้งานได้
- [ ] fail เร็วเมื่อ auth ไม่ผ่าน

### 10.3 Context model
- [ ] สร้าง openstack_context ได้
- [ ] bind context กับ plan ได้
- [ ] bind context กับ profile config ได้
- [ ] เก็บ context ลง state ได้

---

## 11) PHASE 10: OpenStack resource resolution

### 11.1 Identity/project
- [ ] resolve project ได้
- [ ] resolve domain ได้เมื่อจำเป็น
- [ ] resolve region ได้
- [ ] resolve visibility default ได้

### 11.2 Network
- [ ] resolve network ได้
- [ ] resolve subnet ได้เมื่อจำเป็น
- [ ] resolve floating IP policy ได้
- [ ] resolve router dependency ได้เมื่อเกี่ยวข้อง

### 11.3 Security
- [ ] resolve security group ได้
- [ ] security group รองรับ access method ที่ต้องการ
- [ ] ระบุได้ว่ากฎไม่พอเมื่อจำเป็น

### 11.4 Compute/storage
- [ ] resolve flavor ได้
- [ ] resolve keypair ได้
- [ ] resolve volume type ได้
- [ ] resolve boot policy ได้

### 11.5 Resource validation
- [ ] resource มีอยู่จริง
- [ ] resource ใช้งานได้จริง
- [ ] log การเลือก resource ได้
- [ ] สร้าง instance_test_blueprint ได้

---

## 12) PHASE 11: Image upload execution

### 12.1 Upload readiness
- [ ] final artifact มีอยู่จริง
- [ ] artifact checksum มี
- [ ] state พร้อม
- [ ] openstack_context พร้อม
- [ ] resolved resources พร้อม

### 12.2 Upload execution
- [ ] upload image สำเร็จ
- [ ] ตั้ง image name ได้ถูกต้อง
- [ ] ตั้ง disk format ได้ถูกต้อง
- [ ] ตั้ง container format ได้ถูกต้อง
- [ ] ตั้ง visibility ได้ถูกต้อง

### 12.3 Metadata enrichment
- [ ] ตั้ง os_distro ได้
- [ ] ตั้ง os_version ได้
- [ ] ตั้ง architecture ได้
- [ ] ตั้ง source/build reference ได้
- [ ] ตั้ง custom properties ได้เมื่อจำเป็น

### 12.4 Upload persistence
- [ ] ได้ uploaded_image_id
- [ ] บันทึก uploaded image metadata ได้
- [ ] บันทึก upload status ลง state ได้
- [ ] สร้าง upload report ได้

---

## 13) PHASE 12: Post-upload validation

### 13.1 Test instance creation
- [ ] สร้าง test instance จาก uploaded image ได้
- [ ] ใช้ network ที่ resolve ไว้ได้
- [ ] ใช้ security group ที่ resolve ไว้ได้
- [ ] ใช้ flavor ที่ resolve ไว้ได้
- [ ] ใช้ keypair/credential ที่ resolve ไว้ได้

### 13.2 Boot validation
- [ ] instance boot สำเร็จ
- [ ] detect ACTIVE/ERROR/timeout ได้
- [ ] network path ใช้งานได้
- [ ] guest response ตรงตาม expectation

### 13.3 Access validation
- [ ] SSH ผ่านเมื่อควรผ่าน
- [ ] cloud-init status ผ่านเมื่อเกี่ยวข้อง
- [ ] guest-agent ใช้งานได้เมื่อเกี่ยวข้อง
- [ ] console fallback ใช้งานได้เมื่อจำเป็น

### 13.4 OS correctness
- [ ] OS family ตรง
- [ ] version ตรง
- [ ] access profile ที่เดาไว้ใช้งานได้จริง
- [ ] image ใช้งานจริงใน environment เป้าหมายได้

### 13.5 Validation reporting
- [ ] เก็บ validation_status ได้
- [ ] แยก boot failure / network failure / credential failure ได้
- [ ] สร้าง post_upload_validation_report ได้
- [ ] cleanup resource ทดสอบได้ตาม policy

---

## 14) PHASE 13: Finalization, reporting, audit, rerun safety

### 14.1 Final state
- [ ] เขียน final_state ได้
- [ ] state สอดคล้องกับผลจริง
- [ ] state ระบุ phase ล่าสุดได้

### 14.2 Manifest/report
- [ ] สร้าง final_manifest ได้
- [ ] สร้าง final_report ได้
- [ ] report รวม input/source/version/build/upload/validation ได้ครบ
- [ ] ผูก report กับ plan_id/request_id ได้

### 14.3 Rerun safety
- [ ] ระบุได้ว่า cache ใช้ต่อได้หรือไม่
- [ ] ระบุได้ว่า build artifact ใช้ต่อได้หรือไม่
- [ ] ระบุได้ว่า upload complete หรือไม่
- [ ] ระบุได้ว่า validation complete หรือไม่
- [ ] rerun ต่อจาก phase ที่เหมาะสมได้

### 14.4 Recovery
- [ ] partial failure ไม่ทำให้ระบบมั่ว
- [ ] resume ได้
- [ ] cleanup ได้เมื่อจำเป็น
- [ ] มี marker บอก phase ที่ค้างอยู่

---

## 15) Definition of Done for current target

ระบบถือว่าผ่าน current target เมื่อ:

- [ ] resolve official image ได้ถูกต้อง
- [ ] resolve version ได้อย่างแม่นยำ
- [ ] dry-run สร้าง plan ที่ใช้จริงได้
- [ ] execution จริงยึดตาม dry-run state
- [ ] cache ไม่ทำให้เกิด duplicate/mismatch
- [ ] download ถูกควบคุมและ verify ได้
- [ ] build pipeline ตรงตาม OS/version
- [ ] guest profile และ access strategy ใช้งานได้จริง
- [ ] OpenRC / OpenStack context ใช้งานได้จริง
- [ ] OpenStack resource resolution ถูกต้อง
- [ ] upload image สำเร็จ
- [ ] test instance boot ได้
- [ ] access validation ผ่าน
- [ ] report/state/manifest ครบ
- [ ] rerun ได้อย่างปลอดภัย

---

## 16) Test execution notes

### Test round
- วันที่:
- ผู้ทดสอบ:
- environment:
- target profile:
- target OS/version:
- image format:
- plan_id:
- result summary:

### Findings
- 
- 
- 

### Blocking issues
- 
- 
- 

### Fix ideas
- 
- 
- 

### Next phase to test
- 
- 
- 
