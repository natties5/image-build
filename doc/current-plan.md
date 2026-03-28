# Current Project Plan

## 1) Project overview

โปรเจกต์นี้มีเป้าหมายเพื่อสร้าง **ระบบ build, prepare, validate และ upload image สำหรับ OpenStack แบบกึ่งอัตโนมัติ** ที่ทำงานเป็นขั้นตอนชัดเจน ควบคุมได้ ตรวจสอบย้อนหลังได้ และลดความผิดพลาดจากการ “เดา” หรือการทำงานข้ามขั้นโดยไม่มี state รองรับ

เป้าหมายหลักของระบบไม่ใช่แค่โหลด image แล้วอัปขึ้น cloud แต่คือการสร้าง **pipeline ที่ deterministic, repeatable, auditable และ OS/version-aware** โดยมี dry-run เป็นจุดศูนย์กลางในการวางแผนก่อน execution จริง

ระบบที่ต้องการควรทำได้ครบดังนี้

- ดาวน์โหลด image จาก official source ได้อย่างถูกต้อง
- มีสคริปต์ตรวจจับ version ที่ไม่รวน ไม่มั่ว ไม่เลือกผิด release
- มี dry-run ที่ resolve ทุกอย่างก่อน mutation จริง
- dry-run ต้องเก็บ state/plan ไว้ใช้ต่อในการ execute จริง
- download จริงจะเกิดขึ้นหลัง dry-run ผ่านแล้วเท่านั้น
- ป้องกันการดาวน์โหลดซ้ำและป้องกัน version mismatch
- เก็บ base image จาก official อย่างเป็นระบบ
- มี guideline การใช้งาน OpenStack ที่ชัดเจน ใช้ซ้ำได้หลาย pipeline
- หลัง set OpenRC แล้วสามารถ resolve resource ที่ต้องใช้ได้อย่างเป็นระบบ
- มี logic สำหรับ guest access ภายใน VM ที่สอดคล้องกับ OS และ version
- โครงสร้างไฟล์/config/state/artifact ใช้งานจากหลายจุดได้อย่างเป็นระบบ
- pipeline ของแต่ละ OS/version ต้องถูกต้อง ไม่มั่ว ไม่บั๊ก
- upload image ที่ build เสร็จแล้วเข้าสู่ OpenStack ได้สมบูรณ์
- rerun ได้โดยไม่พัง state เดิม และไม่ทำงานซ้ำแบบไม่มีเหตุผล

---

## 2) Current target statement

### เป้าหมายปัจจุบันของระบบ

ระบบปัจจุบันต้องการให้ flow หลักทำงานได้ดังนี้

1. รับ input ของ target image ที่ต้องการ
2. resolve official source ที่ถูกต้อง
3. ตรวจจับ version อย่างแม่นยำ
4. สร้าง dry-run plan และบันทึก state
5. ใช้ state จาก dry-run เป็นตัวควบคุมการ execute จริง
6. ดาวน์โหลด image เฉพาะเมื่อ plan ผ่านแล้ว
7. build/prepare image ตาม pipeline ของ OS/version นั้น
8. resolve OpenStack context และ resource ที่ต้องใช้
9. upload image เข้า OpenStack อย่างถูกต้อง
10. validate การใช้งานจริงหลัง upload
11. เก็บ final state/report/artifact เพื่อรองรับ rerun และ audit

---

## 3) Core operating principles

### 3.1 Dry-run before mutation
ห้ามทำ mutation จริง เช่น download, build, upload ก่อนที่ dry-run จะ resolve แผนและบันทึก state ไว้เรียบร้อย

### 3.2 State-driven execution
การ execute จริงต้องอิงจาก state/plan ที่สร้างจาก dry-run เท่านั้น ไม่ควร resolve ใหม่แบบลอย ๆ ระหว่างทางจนทำให้ผลลัพธ์ไม่ตรงกับแผน

### 3.3 Strong version discipline
version ต้องถูก resolve อย่าง strict:
- ไม่ใช้ fuzzy match แบบเสี่ยง
- ไม่ใช้ candidate ที่คลุมเครือ
- ถ้าข้อมูลขัดกันต้อง fail
- ถ้ามีหลาย candidate ที่เท่ากันต้องหยุด ไม่เดา

### 3.4 Deterministic pipeline
input เดิม + config เดิม + state เดิม ควรให้ผลลัพธ์เดิม

### 3.5 OS-aware implementation
แต่ละ OS / distro / version ต้องมี pipeline ที่เหมาะสมกับตัวเอง ไม่เอา logic ของอีกตัวมาใช้ข้ามกันแบบเดา

### 3.6 Centralized configuration
ควรมี config กลางหรือ schema กลางที่ทุก phase อ้างอิงร่วมกันได้

### 3.7 Observable and auditable
ทุก decision สำคัญควรมี log, manifest, state, report และเหตุผลประกอบที่ตรวจย้อนหลังได้

### 3.8 Safe rerun
rerun ได้อย่างปลอดภัย:
- ไม่โหลดซ้ำโดยไม่จำเป็น
- ไม่ build ซ้ำโดยไม่จำเป็น
- ไม่ upload ซ้ำโดยไม่จำเป็น
- ตรวจจับ mismatch ได้ก่อนทำงานต่อ

---

## 4) End-to-end pipeline summary

ระบบเป้าหมายควรถูกออกแบบเป็น phase ตามลำดับดังนี้

- Phase 0: Input intake and normalization
- Phase 1: Policy loading and source mapping
- Phase 2: Official source discovery
- Phase 3: Version resolution and guard
- Phase 4: Dry-run planning and state persistence
- Phase 5: Cache analysis and local storage preparation
- Phase 6: Controlled download execution
- Phase 7: Build / transform / customization pipeline
- Phase 8: Guest OS profile and access resolution
- Phase 9: OpenRC and OpenStack context resolution
- Phase 10: OpenStack resource resolution
- Phase 11: Image upload execution
- Phase 12: Post-upload validation
- Phase 13: Finalization, reporting, audit, rerun safety

ด้านล่างคือรายละเอียดแบบลึกของแต่ละ phase

---

## 5) Detailed pipeline flow

## PHASE 0: Input intake and normalization

### Objective
รับค่าที่ต้องใช้กับ pipeline และทำให้ข้อมูลอยู่ในรูปแบบมาตรฐานก่อนส่งต่อไป phase อื่น

### Required input examples
- os_family
- distro
- version
- release_name
- architecture
- image_format
- image_type
- source_channel
- target_openstack_profile
- execution_mode
- dry_run flag
- upload flag
- validation flag

### Step 0.1 Input intake
ระบบต้องรับค่าที่จำเป็นของ target image อย่างครบถ้วน เช่น:
- Ubuntu 22.04 x86_64 qcow2
- Debian 12 generic cloud image
- target cloud profile = prod-openstack-a

### Step 0.2 Input normalization
ทำ normalization ให้ข้อมูลอยู่ใน canonical form เช่น:
- jammy → ubuntu 22.04
- amd64 → x86_64
- qcow → qcow2
- lower-case / trim / normalize separators

### Step 0.3 Input validation
ตรวจว่า:
- fields บังคับมีครบ
- format ถูกต้อง
- version parse ได้
- architecture รองรับ
- image_type รองรับ
- target profile มีอยู่จริง

### Step 0.4 Canonical request object
สร้าง object กลาง เช่น `normalized_input` เพื่อให้ทุก phase ใช้ข้อมูลจาก object นี้ร่วมกัน

### Outputs
- normalized_input
- input_validation_result
- request_id หรือ execution seed

### Failure conditions
- input ขาด
- version parse ไม่ได้
- unsupported distro/version/arch
- target profile ไม่รู้จัก

---

## PHASE 1: Policy loading and source mapping

### Objective
โหลด policy/config ที่ใช้กำหนดว่า target นี้ควรใช้ source ไหน version rule แบบไหน และ pipeline ไหน

### Step 1.1 Load global config
โหลด config กลางของระบบ เช่น:
- default directories
- cache strategy
- checksum policy
- retry policy
- upload policy
- validation defaults

### Step 1.2 Load OS-specific config
โหลด config ที่ผูกกับ OS family / distro / version เช่น:
- official source base URL
- naming conventions
- checksum location
- default guest username
- required pipeline variant

### Step 1.3 Load environment / profile config
โหลด config ตาม OpenStack target profile เช่น:
- default network
- default security group
- default flavor
- default image visibility
- upload preferences
- validation boot policy

### Step 1.4 Build effective policy
merge ค่าจาก:
- global config
- os config
- version config
- profile config
- runtime overrides

ให้กลายเป็น `effective_policy`

### Outputs
- effective_policy
- source_policy
- os_pipeline_policy
- openstack_profile_policy

### Failure conditions
- config ไม่ครบ
- policy conflict
- ไม่มี source mapping สำหรับ target นี้
- ไม่มี pipeline mapping สำหรับ OS/version

---

## PHASE 2: Official source discovery

### Objective
ค้นหา official source ของ image และ metadata ที่เกี่ยวข้องจาก upstream ที่เชื่อถือได้

### สิ่งที่ต้องหา
- official download URL
- checksum source
- release metadata
- filename candidates
- build date/release date (ถ้ามี)
- architecture and format mapping

### Step 2.1 Connect to official source endpoint
source อาจเป็น:
- HTML page
- index listing
- JSON API
- release page
- static manifest
- checksum file

### Step 2.2 Collect raw candidates
ดึง candidate ทุกตัวที่อาจตรงกับ target โดยเก็บข้อมูล:
- filename
- URL
- checksum source
- size (ถ้ามี)
- release label
- arch
- format
- publish/build identifier

### Step 2.3 Candidate filtering
กรองตาม:
- OS family
- distro
- version
- release alias
- architecture
- image format
- image type

### Step 2.4 Candidate ranking by strict rules
จัดลำดับ candidate ตามกติกาที่ explicit เช่น:
- exact version match มาก่อน
- exact arch match มาก่อน
- exact format match มาก่อน
- official release channel ที่ policy ระบุเท่านั้น

### Step 2.5 Final strict selection
เลือก candidate สุดท้ายได้ก็ต่อเมื่อ:
- มี candidate เดียวที่ผ่าน rule
- metadata ไม่ขัดกัน
- checksum source สอดคล้อง
- naming pattern ถูกต้อง

### Outputs
- resolved_source_candidate
- source_candidates_report
- source_selection_reason

### Failure conditions
- ไม่เจอ candidate
- เจอหลาย candidate ที่ตัดสินไม่ได้
- source ไม่ใช่ official ตาม policy
- metadata สำคัญไม่ครบ

---

## PHASE 3: Version resolution and version guard

### Objective
resolve version ให้แม่นยำ และป้องกัน pipeline จาก version mismatch

### Step 3.1 Version extraction
ดึง version จากหลายแหล่ง:
- filename
- metadata
- release page
- checksum manifest
- explicit mapping ใน policy

### Step 3.2 Version normalization
normalize version ให้เทียบกันได้ เช่น:
- 22.04
- 22.04.1
- 22.04 LTS
- jammy

### Step 3.3 Cross-source consistency check
ตรวจว่าข้อมูล version จากทุก source ตรงกัน
ตัวอย่าง:
- filename บอก 22.04
- metadata บอก jammy
- policy map jammy → 22.04
ถือว่าตรงกันได้ถ้ามี mapping ชัดเจน

### Step 3.4 Version guard rules
ระบบต้อง reject ทันทีเมื่อ:
- version parse ไม่ได้
- metadata ขัดกัน
- candidate เดียวกันแต่ version คนละตัว
- release alias แมปไม่ชัด
- expected version ไม่ตรง request

### Step 3.5 Freeze resolved version
เมื่อ resolve แล้ว ให้ lock ลง state:
- resolved_version
- resolved_release_name
- resolved_filename
- resolved_source_url
- resolved_checksum

### Outputs
- resolved_version
- resolved_release_name
- resolved_checksum
- resolved_filename
- version_resolution_evidence

### Failure conditions
- ambiguous version
- conflicting metadata
- version mismatch with requested input
- checksum record ไม่ผูกกับ artifact เดียวกัน

---

## PHASE 4: Dry-run planning and state persistence

### Objective
สร้างแผน execution ที่ครบทุกขั้นโดยยังไม่ทำ mutation จริง และบันทึก plan/state ไว้เป็นฐานของ execution

### Step 4.1 Build execution intent
กำหนดงานที่จะทำทั้งหมด:
- จะ download อะไร
- จะเก็บไว้ที่ไหน
- จะ build ด้วย pipeline ไหน
- จะได้ artifact ชื่ออะไร
- จะ upload เข้า OpenStack โปรไฟล์ไหน
- จะ validate ยังไง

### Step 4.2 Compute deterministic paths
คำนวณ path ที่ชัดเจน เช่น:
- cache path
- checksum path
- work path
- artifact path
- report path
- log path

### Step 4.3 Compute identity keys
เช่น:
- plan_id
- cache_key
- artifact_key
- source_fingerprint
- input_fingerprint

### Step 4.4 Create execution plan object
plan ควรมีอย่างน้อย:
- normalized_input
- effective_policy
- resolved_source
- resolved_version
- expected checksum
- cache path
- work path
- artifact path
- selected pipeline id
- guest profile expectation
- OpenStack target profile
- upload options
- validation plan

### Step 4.5 Persist dry-run state
บันทึกลงไฟล์/state store เช่น:
- state/plan/<plan_id>.json
- state/current/<request_id>.json

### Step 4.6 Dry-run report generation
สร้าง report ที่มนุษย์อ่านได้ ว่าระบบ “ตั้งใจจะทำอะไร”

### Outputs
- execution_plan
- plan_id
- dry_run_state
- dry_run_report

### Failure conditions
- plan สร้างไม่ครบ
- path conflict
- identity key ไม่เสถียร
- dry-run ไม่มีข้อมูลเพียงพอจะไปต่อ

---

## PHASE 5: Cache analysis and local storage preparation

### Objective
ตรวจสถานะ cache ที่มีอยู่และเตรียม local storage สำหรับ execution จริง

### Step 5.1 Directory preparation
เตรียมโฟลเดอร์หลัก:
- configs/
- state/
- cache/official/
- cache/checksums/
- work/
- artifacts/
- reports/
- logs/
- manifests/

### Step 5.2 Cache lookup
ดูว่า official image ที่ต้องใช้ถูกโหลดไว้แล้วหรือยัง โดยอิงจาก:
- source URL
- resolved version
- checksum
- arch
- format

### Step 5.3 Cache integrity verification
ถ้ามี cache อยู่แล้ว ต้องตรวจว่า:
- filename ตรง
- checksum ตรง
- file readable
- size สมเหตุสมผล
- metadata file ตรงกับ state

### Step 5.4 Cache decision
สถานะที่เป็นไปได้:
- HIT = มีไฟล์ครบและ valid
- MISS = ยังไม่มี
- INVALID = มีแต่ใช้ไม่ได้
- STALE = มีแต่ไม่ตรงกับ state ใหม่

### Outputs
- cache_status
- cache_validation_report
- prepared_directories

### Failure conditions
- path permission problem
- cache metadata mismatch
- cache file corrupt
- cache file belongs to another version/arch

---

## PHASE 6: Controlled download execution

### Objective
ดาวน์โหลด official image อย่างปลอดภัยภายใต้เงื่อนไขที่ dry-run ผ่านแล้วเท่านั้น

### Hard gate
จะเข้า phase นี้ได้ก็ต่อเมื่อ:
- มี dry-run state
- state สมบูรณ์
- execution mode อนุญาต
- resolved source ยัง valid
- expected checksum ยังชัดเจน

### Step 6.1 Pre-download validation
ตรวจอีกครั้งว่า:
- source URL ตรงกับ plan
- filename expectation ตรง
- version expectation ตรง
- checksum expectation ตรง

### Step 6.2 Download execution
ดาวน์โหลดไปยัง temp path ก่อน เช่น:
- `.partial`
- `.downloading`

### Step 6.3 Download retry / resume policy
รองรับ retry อย่างปลอดภัยโดยไม่ทำให้ state เพี้ยน

### Step 6.4 Post-download verification
ตรวจ:
- checksum
- size
- filename
- readable format
- optional signature/checksum manifest consistency

### Step 6.5 Promote to official cache
ถ้าตรวจผ่าน ค่อยย้ายไป official cache path จริง

### Outputs
- download_status
- downloaded_file_path
- download_report

### Failure conditions
- source unreachable
- checksum mismatch
- size mismatch
- filename mismatch
- state mismatch กับ dry-run

---

## PHASE 7: Build / transform / customization pipeline

### Objective
เตรียม image ที่ดาวน์โหลดมาให้พร้อมใช้งานจริงตาม OS/version และ target pipeline

### Step 7.1 Select pipeline implementation
เลือก pipeline ตาม:
- OS family
- distro
- version
- source image format
- target artifact format
- customization profile

### Step 7.2 Prepare work area
แยก work directory ต่อ plan/job เพื่อไม่ชนกัน

### Step 7.3 Transform / conversion steps
อาจมีขั้นตอนเช่น:
- decompress
- unpack
- convert qcow2 ↔ raw
- resize image
- prepare partition/layout
- inject metadata
- tune cloud image settings

### Step 7.4 OS-specific customization steps
เช่น:
- cloud-init adjustments
- network configuration policy
- guest-agent handling
- access defaults
- cleanup machine identity
- reset temp files / logs / SSH host identity ตาม policy

### Step 7.5 Intermediate validation
ตรวจระหว่างทางว่า:
- image เปิดอ่านได้
- format ถูก
- ไม่มี corruption
- expected files/config อยู่ครบ

### Step 7.6 Produce final artifact
สร้าง artifact สุดท้ายพร้อม upload เช่น:
- qcow2
- raw
- compressed artifact

### Step 7.7 Build manifest
บันทึกว่า pipeline ทำอะไรไปบ้าง:
- base image อะไร
- apply steps อะไร
- outputs อะไร
- checksums อะไร

### Outputs
- final_artifact
- artifact_checksum
- build_manifest
- build_report

### Failure conditions
- ใช้ pipeline ผิด OS/version
- conversion fail
- image เสีย
- customization ขัดกับ guest OS
- artifact ไม่ตรง format ที่จะ upload

---

## PHASE 8: Guest OS profile and access resolution

### Objective
กำหนดและยืนยันรูปแบบการเข้าถึง guest VM ที่คาดว่าจะใช้ได้จริง

### สิ่งที่ต้อง resolve
- default username
- auth mode
- ssh key usage
- password expectation
- cloud-init expectation
- guest agent expectation
- console fallback
- root login policy
- serial console behavior (ถ้ามี)

### Step 8.1 Guest OS mapping
อิงจาก OS/version เพื่อเลือก access profile ที่เหมาะสม

### Step 8.2 Build guest access profile
เช่น:
- username = ubuntu
- auth = ssh-key
- cloud-init = required
- guest-agent = optional
- fallback = console

### Step 8.3 Access assumptions validation
ตรวจว่าขั้นตอน build ไม่ได้ทำลาย assumption เหล่านี้ เช่น:
- cloud-init ถูก disable โดยไม่ตั้งใจ
- authorized keys path ผิด
- network config ขัดกับการ boot ครั้งแรก

### Outputs
- guest_profile
- access_strategy
- guest_validation_expectation

### Failure conditions
- ไม่รู้ว่าจะเข้าเครื่องอย่างไร
- pipeline ทำให้ access profile ใช้ไม่ได้
- guest OS policy ขัดกับ validation plan

---

## PHASE 9: OpenRC and OpenStack context resolution

### Objective
หลัง set OpenRC แล้ว สร้าง OpenStack context ที่ใช้ต่อใน pipeline ได้อย่างชัดเจน

### Step 9.1 Load and validate OpenRC
ตรวจว่า environment สำคัญมีครบ เช่น:
- auth URL
- username / user domain
- project / project domain
- region
- interface / endpoint type (ถ้ามี)

### Step 9.2 Authentication check
ตรวจว่า token/auth ใช้งานได้จริง

### Step 9.3 Build OpenStack context object
ควรมีข้อมูลเช่น:
- cloud profile name
- region
- project
- domain
- API endpoint scope
- visibility defaults
- resource defaults

### Outputs
- openstack_context
- auth_validation_result

### Failure conditions
- OpenRC ไม่ครบ
- auth ไม่ผ่าน
- region/project resolve ไม่ได้
- profile config conflict กับ environment

---

## PHASE 10: OpenStack resource resolution

### Objective
resolve resource ทุกตัวที่จำเป็นต่อ upload และ post-upload validation

### กลุ่ม resource สำคัญ
- project
- network
- subnet
- security group
- router (ถ้าเกี่ยวข้อง)
- flavor
- keypair
- volume type
- image visibility
- boot mode policy
- instance test policy

### Step 10.1 Identity and project resolution
ระบุ project ที่ถูกต้องสำหรับงานนี้

### Step 10.2 Network resolution
เลือก network/subnet/floating IP policy ที่จะใช้กับ test instance

### Step 10.3 Security resolution
เลือก security group ที่เพียงพอสำหรับ access method ที่คาดไว้

### Step 10.4 Compute and storage resolution
เลือก flavor, keypair, volume type และ boot options ให้ตรง policy

### Step 10.5 Resource validation
ตรวจว่า resource เหล่านี้มีอยู่จริงและใช้งานได้จริง

### Outputs
- resolved_resources
- resource_resolution_report
- instance_test_blueprint

### Failure conditions
- resource ขาด
- security group ไม่พอสำหรับ validation
- network ไม่เหมาะกับ guest access test
- keypair/flavor/volume type resolve ไม่ได้

---

## PHASE 11: Image upload execution

### Objective
อัปโหลด image ที่ build สำเร็จแล้วเข้าสู่ OpenStack พร้อม metadata ที่ถูกต้อง

### Step 11.1 Upload readiness check
ตรวจว่า:
- final artifact มีอยู่จริง
- checksum มี
- state ครบ
- OpenStack context valid
- resolved resources สำหรับ validation พร้อม

### Step 11.2 Upload image
อัปโหลดโดยระบุ:
- image name
- disk format
- container format
- visibility
- tags/properties

### Step 11.3 Metadata enrichment
ตั้ง metadata เช่น:
- os_distro
- os_version
- architecture
- source reference
- build id
- pipeline id
- visibility flags
- custom properties เฉพาะระบบ

### Step 11.4 Capture upload result
เก็บ:
- image id
- status
- timestamps
- final image metadata

### Outputs
- upload_status
- uploaded_image_id
- uploaded_image_metadata
- upload_report

### Failure conditions
- artifact ไม่พร้อม
- format ไม่รองรับ
- upload fail
- metadata ไม่ครบ
- uploaded image status ไม่ usable

---

## PHASE 12: Post-upload validation

### Objective
ทดสอบว่า image ที่อัปแล้วนำไปใช้งานได้จริงใน OpenStack environment เป้าหมาย

### Step 12.1 Create test instance
สร้าง instance จาก uploaded image โดยใช้ resource ที่ resolve ไว้แล้ว

### Step 12.2 Wait for boot
ตรวจสถานะจนกว่าจะ:
- ACTIVE
- ERROR
- timeout

### Step 12.3 Validate networking
ตรวจว่า instance มี network path ตามที่ต้องการ

### Step 12.4 Validate guest access
ทดสอบตาม guest profile:
- SSH
- cloud-init completion
- guest agent response
- console fallback (ถ้าจำเป็น)

### Step 12.5 Validate OS correctness
ตรวจว่า instance ที่บูตขึ้นมาตรงกับ OS/version ที่คาดไว้

### Step 12.6 Optional cleanup
ลบ test instance / volume / floating IP ตาม policy

### Outputs
- validation_status
- boot_validation_result
- access_validation_result
- post_upload_validation_report

### Failure conditions
- instance boot ไม่ขึ้น
- network ใช้งานไม่ได้
- ssh/access ไม่ผ่าน
- guest profile ไม่ตรงกับของจริง
- image ใช้งานใน environment จริงไม่ได้

---

## PHASE 13: Finalization, reporting, audit, rerun safety

### Objective
ปิดงานอย่างเป็นระบบและทำให้รองรับ audit / recovery / rerun

### Step 13.1 Write final state
สรุป phase ทั้งหมดลง state กลาง

### Step 13.2 Generate final manifest
รวมข้อมูล:
- input
- source
- version
- checksum
- build pipeline
- artifact
- upload result
- validation result

### Step 13.3 Generate human-readable report
สรุปให้คนอ่านได้ว่าระบบทำอะไรไปบ้าง ผ่าน/ไม่ผ่านตรงไหน

### Step 13.4 Rerun markers
ระบุว่า:
- official image ถูก cache แล้วหรือยัง
- build artifact usable หรือยัง
- upload complete หรือยัง
- validation complete หรือยัง
- phase ไหนสามารถ skip ได้ในการ rerun

### Step 13.5 Final lock / release policy
ถ้ามี release process ภายใน ให้ mark ว่า artifact นี้พร้อมใช้งานแล้ว

### Outputs
- final_state
- final_manifest
- final_report
- rerun_resume_info

### Failure conditions
- report/state ไม่สอดคล้องกัน
- final state ขาดข้อมูล
- rerun marker ไม่ชัดเจน

---

## 6) Recommended system components

ระบบควรมี component อย่างน้อยดังนี้

1. Input normalizer
2. Policy resolver
3. Official source resolver
4. Version detector / normalizer
5. Dry-run planner
6. State store
7. Cache manager
8. Download manager
9. Download verifier
10. Build pipeline runner
11. Guest profile resolver
12. OpenRC loader
13. OpenStack context resolver
14. OpenStack resource resolver
15. Image uploader
16. Post-upload validator
17. Report / manifest generator
18. Recovery / rerun controller

---

## 7) Suggested state model

state ควรเก็บอย่างน้อย:

- request_id
- plan_id
- execution_mode
- requested_input
- normalized_input
- effective_policy
- resolved_source
- resolved_version
- resolved_release_name
- resolved_filename
- resolved_checksum
- source_fingerprint
- cache_key
- cache_status
- download_status
- downloaded_file_path
- build_pipeline_id
- build_status
- final_artifact_path
- artifact_checksum
- guest_profile
- openstack_context
- resolved_resources
- upload_status
- uploaded_image_id
- validation_status
- final_report_path
- timestamps by phase

---

## 8) Suggested directory model

ตัวอย่างโครงสร้างไฟล์ที่แนะนำ

```text
configs/
state/
state/plan/
state/run/
cache/
cache/official/
cache/checksums/
work/
artifacts/
reports/
reports/dry-run/
reports/final/
logs/
manifests/
pipelines/
```

### ความหมาย
- `configs/` เก็บ config และ policy
- `state/plan/` เก็บ dry-run plans
- `state/run/` เก็บ runtime/final state
- `cache/official/` เก็บ official image
- `cache/checksums/` เก็บ checksum และ metadata
- `work/` เก็บไฟล์ชั่วคราวระหว่าง execution
- `artifacts/` เก็บ output สุดท้าย
- `reports/` เก็บ dry-run/final reports
- `logs/` เก็บ execution logs
- `manifests/` เก็บ machine-readable summaries
- `pipelines/` เก็บ logic ตาม OS/version

---

## 9) Rules that must not be broken

- ห้าม download จริงก่อน dry-run
- ห้าม build โดยไม่มี resolved source/version ที่ถูก lock แล้ว
- ห้าม upload artifact ที่ยังไม่ผ่าน build validation
- ห้าม validate guest access โดยไม่รู้ guest profile
- ห้ามใช้ OpenStack resource แบบ implicit ถ้ายัง resolve ไม่ครบ
- ห้าม rerun ข้าม state mismatch
- ห้ามใช้ cache ข้าม version/arch/source โดยไม่มี verification
- ห้ามเดา version เมื่อข้อมูลคลุมเครือ
- ห้ามใช้ pipeline ข้าม OS/version แบบ blind reuse

---

## 10) Definition of success

ระบบถือว่าไปตาม current plan เมื่อ:

- resolve official image ได้จริงและอธิบายได้ว่าทำไมเลือก source นี้
- resolve version ได้แม่นยำและ reject ambiguity ได้
- dry-run สร้าง plan ที่ใช้ execute จริงได้
- state จาก dry-run ถูกใช้เป็น source of truth
- cache ไม่ทำให้เกิด duplicate/mismatch
- download ควบคุมได้และ verify ได้
- build pipeline ถูกต้องตาม OS/version
- guest profile ใช้ทดสอบได้จริง
- OpenRC / OpenStack context ใช้งานได้จริง
- resource ที่ต้องใช้ resolve ได้ครบ
- image upload สำเร็จ
- instance test boot สำเร็จ
- access validation สำเร็จ
- report/state/manifest ครบ
- rerun ได้อย่างปลอดภัย

---

## 11) Current testing direction

การเทสควรแบ่งตาม phase ดังนี้

1. input normalization test
2. policy loading test
3. source discovery test
4. version resolution test
5. dry-run persistence test
6. cache behavior test
7. controlled download test
8. build pipeline correctness test
9. guest profile test
10. OpenRC/context test
11. resource resolution test
12. upload execution test
13. post-upload validation test
14. rerun/idempotency/recovery test

---

## 12) Notes for implementation direction

เอกสารนี้ตั้งใจให้เป็น baseline ที่ “ลงมือ implement ได้จริง” ไม่ใช่แค่ภาพรวมเชิงไอเดีย

ดังนั้นทุก phase ควรถูกแตกต่อได้เป็น:
- module
- script
- function groups
- schema/state
- test cases
- acceptance criteria

และควรใช้เอกสารนี้เป็นแกนกลางก่อนแตกเป็น:
- task list
- script layout
- JSON state schema
- per-phase test checklist
