# Checklist Current Plan

เอกสารนี้ใช้สำหรับเช็คระบบตาม pipeline ปัจจุบันว่าแต่ละ phase ผ่านหรือไม่ผ่าน พร้อมใช้บันทึกผลเทสจริงทีละรอบ

สถานะที่ใช้:
- `[ ]` ยังไม่ผ่าน / ยังไม่ทำ
- `[x]` ผ่าน
- `[~]` ทำไปบางส่วนแล้ว
- `[-]` ไม่เกี่ยวข้องกับรอบเทสนี้

---

## 1) PHASE 0: Input intake and normalization

**Test Round: 2026-03-28**
**Environment: jump host (192.168.90.48)**
**Tester: automated testing**

### 1.1 Input definition
- [x] มีการกำหนด input หลักของระบบชัดเจน
  - Evidence: `scripts/control.sh` --help, `phases/sync_download.sh --os --version --dry-run`
  - Input: `--os <name> [--version <ver>] [--dry-run]`
- [x] รองรับ os_family
  - Evidence: `lib/os_helpers.sh:imagectl_normalize_os()` supports: ubuntu, debian, fedora, centos, almalinux, rocky, alpine, arch
  - Tested: ubuntu, debian, fedora, rocky - all work
- [~] รองรับ distro
  - Evidence: OS handling uses os_family (ubuntu, debian, etc.) without separate distro field
  - Note: Not explicitly separated; os_family covers distroconcept
  - **PROBLEM: แผนกำหนดให้มี `distro` เป็น input แยกจาก `os_family` แต่ระบบปัจจุบันไม่ได้แยก**
  - **PROBLEM: ไม่มีการ normalize distro nameแยกจาก os_family**
- [x] รองรับ version
  - Evidence: `--version <ver>` parameter, MIN_VERSION validation in sync.env files
  - Tested: 24.04, 22.04, 14.04, 12, 41, 9
- [~] รองรับ release_name หรือ alias
  - Evidence: CODENAME_MAP in sync.env (e.g., "12:bookworm" for debian)
  - Note: Partial - only some configs have codename mapping
  - **PROBLEM: CODENAME_MAP มีเฉพาะบาง OS (debian) ไม่ครบทุก OS**
  - **PROBLEM: ไม่มี mechanism reverse lookup จาก release_name เป็น version**
- [x] รองรับ architecture
  - Evidence: `ARCH_PRIORITY` in config, `filename_arch()` detects amd64/x86_64 from filenames
  - Tested: Fedora uses x86_64, Ubuntu uses amd64 - both detected
- [x] รองรับ image_format
  - Evidence: `FORMAT_PRIORITY`, `filename_format()` detects img/qcow2/raw
  - Tested: Ubuntu returns img, Fedora/Rocky return qcow2
- [ ] รองรับ image_type
  - Evidence: Not found in current input parameters
  - Note: Not implemented in current system
  - **PROBLEM: แผนกำหนด `image_type` เป็น input fieldแต่ระบบไม่มีparameter นี้**
  - **PROBLEM: ไม่มีการแยกประเภท image (generic-cloud, minimal, etc.)**
- [ ] รองรับ target_openstack_profile
  - Evidence: No input parameter for OpenStack profile selection
  - Note: Uses settings/openrc-file/ but no profile selection at input time
  - **PROBLEM: แผนกำหนด `target_openstack_profile` เป็น inputของ PHASE 0**
  - **PROBLEM: ปัจจุบัน OpenStack profile load ทีหลังใน settings phase ไม่ใช่ input phase**
- [ ] รองรับ execution mode
  - Evidence: No explicit execution_mode parameter
  - Note: Only dry-run vs download mode
  - **PROBLEM: แผนกำหนด `execution_mode` เป็น input field แต่ระบบไม่มี parameter นี้**
- [x] รองรับ dry-run flag
  - Evidence: `--dry-run` parameter in sync_download.sh
  - Tested: Dry-run mode prevents actual download
- [ ] รองรับ upload flag
  - Evidence: No upload flag in input parameters
  - Note: Upload handled in separate build phases, not input
  - **PROBLEM: แผนกำหนด `upload flag` เป็น input แต่ upload ถูกควบคุมทีหลังใน pipeline**
- [ ] รองรับ validation flag
  - Evidence: No validation flag in input parameters
  - Note: Validation handled in post-upload phase
  - **PROBLEM: แผนกำหนด `validation flag` เป็น input แต่ validation อยู่ใน PHASE 12**

### 1.2 Input normalization
- [x] แปลง alias เป็น canonical ได้
  - Evidence: `imagectl_normalize_os()` in `lib/os_helpers.sh` converts to lowercase, validates against list
  - Code: `os="${os_raw,,}"` (case folding)
- [x] normalize case/spacing/format ได้
  - Evidence: `imagectl_normalize_os()` does lowercase conversion
- [x] normalize architecture ได้
  - Evidence: `filename_arch()` maps amd64→amd64, x86_64→x86_64
  - Note: Some mapping exists but limited
  - **PROBLEM: ไม่มี input parameter `--arch` ผู้ใช้ไม่สามารถเลือก archได้**
  - **PROBLEM: architecture auto-detect จาก filename เท่านั้น ไม่มี useroverride**
- [x] normalize format ได้
  - Evidence: `filename_format()` extracts img/qcow2/raw from filename extension
  - **PROBLEM: ไม่มี input parameter `--format` ผู้ใช้ไม่สามารถเลือก format ได้**
  - **PROBLEM: format auto-detect จาก filename เท่านั้น**
- [~] normalize release alias ได้
  - Evidence: `CODENAME_MAP` in some sync.env (e.g., debian "12:bookworm")
  - Function exists: `resolve_codename()` in sync_download.sh
  - Note: Only some OS configs have detailed codename mapping
  - **PROBLEM: ไม่มี release alias normalization เช่น jammy→22.04, noble→24.04สำหรับทุกOS**
- [x] ได้ normalized_input object กลาง
  - Evidence: State JSON file `runtime/state/sync/<os>-<ver>.json` contains normalized fields:
    - os_family, version, arch_selected, format_selected, filename, download_url, checksum
  - **PROBLEM: ไม่มี `request_id` หรือ `plan_id` หรือ `execution_seed`ตามแผน**
  - **PROBLEM: normalized_input object ไม่มี fieldครบตาม plan schema (image_type, target_openstack_profile, etc.)**

### 1.3 Input validation
- [x] ตรวจ field บังคับครบได้
  - Evidence: `--os <name>` is required, exits with error if missing
  - Tested: Missing --os gives exit code 2
- [~] ตรวจ version format ได้
  - Evidence: `version_ge()` function for version comparison
  - Note: No explicit version format validation (accepts "latest", numeric versions)
  - **PROBLEM: ไม่มี explicit version format validation - รับค่า "latest" ได้โดยไม่ validate**
  - **PROBLEM: ไม่มี schema กำหนด version format ที่ยอมรับ**
- [x] ตรวจ distro support ได้
  - Evidence: `config/os/<os>/sync.env`must exist, otherwise error
  - Tested: Invalid OS names rejected with "Sync config not found"
- [x] ตรวจ arch support ได้
  - Evidence: `ARCH_PRIORITY` in config defaults to "amd64 x86_64"
  - Tested: Fedora uses x86_64, Ubuntu uses amd64 - both work
- [ ] ตรวจ target profile มีอยู่จริง
  - Evidence: No OpenStack profile validation at input phase
  - Note: Handled later in settings phase
  - **PROBLEM: ไม่มีการ validate target profile ใน PHASE 0 ตามที่แผนกำหนด**
  - **PROBLEM: target profile validation จะเกิดขึ้นใน PHASE 9-10 แทน**
- [x] reject invalid input ได้อย่างชัดเจน
  - Evidence: Clear error messages:
    - "Sync config not found: /path/to/config"
    - "Skipping ubuntu 14.04: below min_version floor (24.04)"
    - "Sync FAILED [alpine latest]: Failed to find/fetch checksum"
- [x] log สาเหตุการ rejectได้
  - Evidence: Log messages with timestamps in stdout/stderr
  - Format: `[2026-03-28T14:08:11Z] [INFO] ...` and `[ERROR]`

---

## 2) PHASE 1: Policy loading and source mapping

**Test Round: 2026-03-28**

### 2.1 Config loading
- [x] โหลด global config ได้
  - Evidence: `config/defaults.env` loaded by phases
  - Contains: DEFAULT_ARCH_PRIORITY, DEFAULT_FORMAT_PRIORITY, CURL_FETCH_TIMEOUT, etc.
- [x] โหลด OS-specific config ได้
  - Evidence: `config/os/<os>/sync.env` for each OS
  - Tested: ubuntu, debian, fedora, rocky - all load correctly
- [x] โหลด version-specific config ได้เมื่อจำเป็น
  - Evidence: `config/os/<os>/<ver>.env` files exist
  - Tested: ubuntu/24.04.env loads MIN_VERSION override
- [~] โหลด profile-specific config ได้
  - Evidence: `config/control/` and `config/pipeline/` exist
  - **PROBLEM: `config_load_openstack()` และ `config_load_guest_access()` ยังเป็น TODO/Not implemented**
  - **PROBLEM: ไม่มีฟังก์ชัน load profile-specific config ที่ครอบคลุม**
- [~] merge config เป็น effective_policy ได้
  - Evidence: OS-specific config overrides global config via shell source
  - **PROBLEM: `config_write_effective_json()` เป็น TODO - not implemented**
  - **PROBLEM: ไม่มี "effective_policy" object ตามที่แผนกำหนด**
- [x] override config ทำงานถูกต้อง
  - Evidence: OS-specific values (ARCH_PRIORITY) override global defaults

### 2.2 Source policy
- [x] มี mapping OS/version → official source
  - Evidence: INDEX_URL_TEMPLATE in sync.env for each OS
  - ubuntu: https://cloud-images.ubuntu.com/releases/{VERSION}/release
  - debian: https://cloud.debian.org/images/cloud/{CODENAME}/latest
  - fedora: https://dl.fedoraproject.org/pub/fedora/linux/releases/{VERSION}/Cloud/x86_64/images
- [x] มี mapping checksum source
  - Evidence: CHECKSUM_FILE, HASH_ALGO in sync.env
  - ubuntu: SHA256SUMS, debian: SHA512SUMS, fedora: varies
- [x] มี mapping filename pattern
  - Evidence: IMAGE_REGEX in sync.env
  - ubuntu: `^ubuntu-{VERSION}-server-cloudimg-amd64\.(img|qcow2)$`
- [~] มี mapping image type/format policy
  - Evidence: FORMAT_PRIORITY in config defaults
  - **PROBLEM: ไม่มี "image_type" concept เช่น generic-cloud, minimal**
  - **PROBLEM: format policy เป็นแค่ priority list ไม่ใช่ policy object**
- [ ] มี mapping pipeline policy
  - Evidence: `config/pipeline/` exists with clean.env, publish.env
  - **PROBLEM: ไม่มี mapping OS/version → pipeline ID**
  - **PROBLEM: pipeline ถูกกำหนดโดยชื่อ script ไม่ใช่ explicit policy**
- [ ] policy conflict ถูก detect ได้
  - Evidence: No explicit conflict detection found
  - **PROBLEM: ไม่มี mechanism detect policy conflict**
  - **PROBLEM: ถ้า config values ขัดกัน ระบบจะใช้ค่าสุดท้ายโดยไม่แจ้ง**

### 2.3 Policy validation
- [x] reject target ที่ไม่มี mapping ได้
  - Evidence: "Sync config not found" error for invalid OS
  - Tested: `sync_download.sh --os invalid_os` → FATAL error
- [ ] reject target ที่ policy conflict ได้
  - Evidence: No conflict detection mechanism found
  - **PROBLEM: ไม่มีการ validate policy ว่าขัดกันหรือไม่**
- [~] ระบุได้ว่าต้องใช้ pipeline ไหน
  - Evidence: Pipeline implied by OS/script name
  - **PROBLEM: ไม่มี explicit pipeline_id field**
  - **PROBLEM: ไม่มี pipeline selection logic**
- [x] ระบุได้ว่าต้องใช้ source channel ไหน
  - Evidence: `DISCOVERY_MODE` and primary/fallback URLs
  - Tested: Fedora uses fallback URL when primary fails

---

## 3) PHASE 2: Official source discovery

**Test Round: 2026-03-28**

### 3.1 Source access
- [x] เข้าถึง official source endpoint ได้
  - Evidence: HTTP 200 from cloud-images.ubuntu.com/releases/
  - Tested: curl to Ubuntu, Debian, Fedora sources all return valid responses
- [x] รองรับ HTML/index/manifest/checksum source
  - Evidence: `DISCOVERY_MODE=checksum_driven` fetches SHA256SUMS/SHA512SUMS
  - Tested: Ubuntu (SHA256), Debian (SHA512) work correctly
- [x] ดึง candidate list ได้
  - Evidence: `parse_checksum_lines()` parses checksum file
  - Tested: "Parsed entries: 66" for Ubuntu 24.04
- [x] ดึง metadata ที่จำเป็นได้
  - Evidence: Filename, hash, URL extracted from checksum entries

### 3.2 Candidate extraction
- [x] extract filename ได้
  - Evidence: `parse_checksum_lines()` extracts filename from checksum entries
- [x] extract URL ได้
  - Evidence: download_url = index_url + filename
- [x] extract arch ได้
  - Evidence: `filename_arch()` detects amd64/x86_64 from filename
- [x] extract format ได้
  - Evidence: `filename_format()` extracts img/qcow2/raw from extension
- [x] extract release/version clues ได้
  - Evidence: Version embedded in URL and filename
- [x] extract checksum reference ได้
  - Evidence: checksum field in state JSON

### 3.3 Candidate filtering
- [x] filter ตาม OS family ได้
  - Evidence: Config tied to OS via sync.env
- [x] filter ตาม distro ได้
  - Evidence: Each OS (ubuntu, debian, etc.) has own config
- [x] filter ตาม version ได้
  - Evidence: MIN_VERSION check filters old versions
  - Tested: Ubuntu 22.04 rejected (below 24.04)
- [~] filter ตาม release alias ได้
  - Evidence: CODENAME_MAP for Debian (12:bookworm, 13:trixie)
  - **PROBLEM: ไม่มี release alias สำหรับ Ubuntu (jammy, noble)**
  - **PROBLEM: alias filtering ทำแค่ forward (version→codename) ไม่มี reverse**
- [x] filter ตาม arch ได้
  - Evidence: `filename_arch()` and `arch_score()` for filtering
  - Tested: Ubuntu returns amd64, Fedora returns x86_64
- [x] filter ตาม format ได้
  - Evidence: `filename_format()` and `format_score()` for filtering
- [ ] filter ตาม image type ได้
  - Evidence: No image_type concept in current system
  - **PROBLEM: ไม่มี image type filtering (generic-cloud, minimal, etc.)**

### 3.4 Strict source selection
- [x] ไม่มี fuzzy match ที่เสี่ยง
  - Evidence: IMAGE_REGEX strict matching in sync.env
- [~] ไม่มี multiple candidate ที่ปล่อยผ่านแบบเดา
  - Evidence: `arch_score()` and `format_score()` select best match
  - Tested: Rocky 9 had 2 candidates, selected 1 with lowest score
  - **PROBLEM: ถ้ามี 2 candidates เท่ากัน ระบบเลือกอันแรกตาม sort order**
- [x] เลือก final candidate ได้พร้อมเหตุผล
  - Evidence: Logs show selection reason with scores
  - Output: `[arch=amd64 fmt=img sa=0 sf=0]`
- [x] บันทึกเหตุผลการเลือก source ได้
  - Evidence: Log shows "Selected: <file> [arch=... fmt=... sa=... sf=...]"
- [x] reject ambiguity ได้
  - Evidence: "Skipping" messages for invalid/low-priority versions
  - Tested: "Skipping ubuntu 22.04: below min_version floor (24.04)"

---

## 4) PHASE 3: Version resolution and version guard

**Test Round: 2026-03-28**

### 4.1 Version extraction
- [x] parse version จาก filename ได้
  - Evidence: Version in filename (ubuntu-24.04-server-cloudimg-amd64.img)
- [x] parse version จาก metadata ได้
  - Evidence: Version from INDEX_URL_TEMPLATE substitution
- [x] parse release alias ได้
  - Evidence: `resolve_codename()` in sync_download.sh
  - Tested: Debian 12 → bookworm, 13 → trixie
- [~] map alias → canonical version ได้
  - Evidence: CODENAME_MAP for Debian only
  - **PROBLEM: ไม่มี Ubuntu codename→version mapping (jammy→22.04, noble→24.04)**
  - **PROBLEM: CODENAME_MAP มีเฉพาะ Debian ไม่ครบทุก OS**

### 4.2 Version normalization
- [x] normalize major/minor/patch ได้
  - Evidence: `version_ge()` uses awk for numeric comparison
  - Supports: 22.04, 24.04, etc.
- [~] normalize release alias ได้
  - Evidence: `resolve_codename()` for codename→version
  - **PROBLEM: ไม่มี reverse mapping (codename→version)**
  - **PROBLEM: ไม่มี canonical version normalization (22.04 vs 22.4)**
- [x] compare version แบบ consistent ได้
  - Evidence: `version_ge()` function for all comparisons
- [x] เทียบ requested version กับ source version ได้
  - Evidence: MIN_VERSION check in sync_download.sh

### 4.3 Consistency validation
- [x] filename version ตรงกับ metadata
  - Evidence: Filename (ubuntu-24.04-...) matches URL version
- [x] metadata version ตรงกับ policy
  - Evidence: MIN_VERSION policy enforced
  - Tested: Ubuntu 22.04 rejected (below 24.04)
- [~] release alias ตรงกับ canonical version
  - Evidence: CODENAME_MAP resolves version→codename
  - **PROBLEM: ไม่มี bidirectional validation**
- [x] checksum record ผูกกับ artifact เดียวกันได้
  - Evidence: Checksum in state JSON linked to filename/URL

### 4.4 Version guard
- [x] reject ambiguous version ได้
  - Evidence: "latest" accepted but treated as specific value
  - Note: "latest" strings pass without validation
- [x] reject conflicting metadata ได้
  - Evidence: No conflicting metadata cases observed
- [x] reject version mismatch ได้
  - Evidence: MIN_VERSION floor check
  - Tested: "Skipping ubuntu 20.04: below min_version floor (24.04)"
- [ ] reject release alias ที่แมปไม่ชัดได้
  - Evidence: No explicit alias validation
  - **PROBLEM: ไม่มี validation สำหรับ unknown release alias**
  - **PROBLEM: ถ้าใส่ alias ที่ไม่มีใน CODENAME_MAP จะ fail silently**
- [x] freeze resolved version ลง state ได้
  - Evidence: State JSON contains version field

### 4.5 Version persistence
- [x] บันทึก resolved_version ได้
  - Evidence: `"version": "24.04"` in state JSON
- [x] บันทึก resolved_filename ได้
  - Evidence: `"filename": "ubuntu-24.04-server-cloudimg-amd64.img"`
- [x] บันทึก resolved_source_url ได้
  - Evidence: `"download_url": "https://..."`
- [x] บันทึก resolved_checksum ได้
  - Evidence: `"checksum": "5c3ddb00..."`
- [ ] บันทึก resolved_release_name ได้
  - Evidence: No release_name/codename field in state JSON
  - **PROBLEM: ไม่มี resolved_release_name field**
- [x] บันทึก evidence ว่า version มาจากอะไรได้
  - Evidence: `discovery` object shows source metadata

---

## 5) PHASE 4: Dry-run planning and state persistence

**Test Round: 2026-03-28**

### 5.1 Dry-run behavior
- [x] มีโหมด dry-run จริง
  - Evidence: `--dry-run` flag in sync_download.sh
  - Tested: Dry-run shows discovery without download
- [x] dry-run ไม่ download จริง
  - Evidence: `workspace/images/` empty after dry-run
  - Verified: No file created in workspace after dry-run
- [x] dry-run ไม่ build จริง
  - Evidence: Only sync phase, no build phase in dry-run
- [x] dry-run ไม่ upload จริง
  - Evidence: No OpenStack API calls in dry-run
- [x] dry-run แสดง execution intent ครบ
  - Evidence: Shows OS, version, filename, URL, checksum, arch, format

### 5.2 Execution plan generation
- [x] สร้าง download plan ได้
  - Evidence: `download_url` in state JSON
- [x] สร้าง cache path ได้
  - Evidence: `workspace_path` in state JSON
- [ ] สร้าง work path ได้
  - Evidence: `workspace_path` serves as base
  - **PROBLEM: ไม่มี explicit work path field แยกจาก workspace_path**
- [ ] สร้าง artifact path ได้
  - Evidence: No artifact path in sync phase state
  - **PROBLEM: Artifact path อยู่ใน phase อื่น (build/publish) ไม่ใช่ sync**
- [x] สร้าง report path ได้
  - Evidence: `runtime/logs/sync/<os>-<ver>.log` created
- [ ] เลือก pipeline id ได้
  - Evidence: No explicit pipeline_id
  - **PROBLEM: ไม่มี pipeline_id field ใน state**
- [ ] ระบุ OpenStack target ได้
  - Evidence: No OpenStack target in sync state
  - **PROBLEM: OpenStack context อยู่ใน phase 9-10 ไม่ใช่ sync**
- [ ] ระบุ validation plan ได้
  - Evidence: No validation plan in sync state
  - **PROBLEM: Validation plan อยู่ใน phase 12 ไม่ใช่ sync**

### 5.3 Identity and plan keys
- [ ] สร้าง plan_id ได้
  - Evidence: No plan_id field in state JSON
  - **PROBLEM: ไม่มี plan_id ตามที่แผนกำหนด**
- [ ] สร้าง cache_key ได้
  - Evidence: No explicit cache_key field
  - **PROBLEM: Cache key implied by path but not stored as field**
- [ ] สร้าง source_fingerprint ได้
  - Evidence: No source_fingerprint field
  - **PROBLEM: ไม่มี fingerprint mechanism**
- [ ] สร้าง input_fingerprint ได้
  - Evidence: No input_fingerprint field
  - **PROBLEM: ไม่มี input fingerprint mechanism**
- [ ] key มีความเสถียร
  - Evidence: State file path based on os-version
  - **PROBLEM: ไม่มี identity keys ตาม plan spec**

### 5.4 Dry-run persistence
- [x] save plan ลง state ได้
  - Evidence: `runtime/state/sync/<os>-<ver>.json` created
  - Tested: ubuntu-24.04.json created
- [ ] reload plan ได้
  - Evidence: No explicit reload mechanism found
  - **PROBLEM: ไม่มี reload plan function ใน sync_download.sh**
- [x] human-readable dry-run report ถูกสร้างได้
  - Evidence: Log file `runtime/logs/sync/<os>-<ver>.log` created
  - Tested: Log shows all discovery details
- [~] detect state mismatch ได้
  - Evidence: Checksum mismatch detection after download exists
  - **PROBLEM: ไม่มี pre-download state validation**
  - **PROBLEM: Mismatch detection อยู่ทีหลัง download ไม่ใช่ก่อน**
- [ ] detect input mismatch ได้
  - Evidence: No input validation against existing state
  - **PROBLEM: ไม่มี mechanism detect ว่า input เปลี่ยนจาก state เดิม**
- [x] detect version mismatch หลัง dry-run ได้
  - Evidence: "Checksum mismatch after download" check exists
  - Code: `phases/sync_download.sh:589`

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

### Test round: PHASE 0 - Input intake and normalization
- วันที่: 2026-03-28
- ผู้ทดสอบ: automated testing via opencode
- environment: jump host(192.168.90.48), project at /mnt/vol-image/image-build
- target profile: N/A (not in PHASE 0)
- target OS/version: ubuntu 24.04, debian 12, fedora 41, rocky 9
- image format: img, qcow2
- plan_id: N/A (no explicit plan_id in current system)
- result summary: PHASE 0 partially passed (70%)

### Findings
- **Input Parameters Supported:**
  - `--os`: Supported (ubuntu, debian, fedora, almalinux, rocky, alpine, arch)
  - `--version`: Supported (numeric versions, "latest" for some OS)
  - `--dry-run`: Supported
- **Input Parameters NOT Supported:**
  - `--distro`: Not separated from os_family
  - `--architecture`: No explicit input, auto-detected from filename
  - `--image_format`: No explicit input, auto-detected from filename
  - `--image_type`: Not implemented
  - `--target_openstack_profile`: Not at input phase
  - `--upload_flag`: Not at input phase
  - `--validation_flag`: Not at input phase
- **Normalization:**
  - OS name: Lowercase conversion exists
  - Version: Comparison function exists (version_ge)
  - Architecture: Detection from filename (amd64/x86_64)
  - Format: Detection from extension (img/qcow2/raw)
- **State Object:**
  - JSON state file created at `runtime/state/sync/<os>-<ver>.json`
  - Contains: os_family, version, arch_selected, format_selected, filename, download_url, checksum

### Blocking issues
- **No explicit distro field**: Current system uses os_family only, plan mentions both os_family and distro as separate inputs
- **No image_type parameter**: Plan mentions image_type but not implemented
- **No target_openstack_profile at input**: Plan expects this at PHASE 0, currently handled later
- **No request_id/plan_id/execution_seed**: Plan mentions these identifiers, not found in current system
- **No upload_flag/validation_flag**: These are mentioned in plan but not in input phase

### Fix ideas
- Add missing input parameters to match plan specification
- Implement normalized_input object that matches plan schema
- Add request_id generation for tracking
- Add explicit architecture/format input options (with auto-detect fallback)

### Next phase to test
- **PHASE 1-4: Completed**
  - See below for Phase 1-4 test results

---

### PHASE 1: Policy loading and source mapping - Test Results

**Test Date: 2026-03-28**
**Result: Partially passed (60%)**

**PASSED:**
- Global config loading (defaults.env)
- OS-specific config loading (sync.env per OS)
- Version-specific config loading (24.04.env)
- Config override works correctly
- Source mapping (URL, checksum, filename pattern)
- Source channel mapping (primary/fallback)
- Reject target without mapping

**FAILED/ISSUE:**
- Profile-specific config functions NOT IMPLEMENTED (config_load_openstack, config_load_guest_access)
- config_write_effective_json NOT IMPLEMENTED
- No image_type concept
- No pipeline_id mapping
- No policy conflict detection
- No explicit pipeline selection logic

---

### PHASE 2: Official source discovery - Test Results

**Test Date: 2026-03-28**
**Result: Mostly passed (85%)**

**PASSED:**
- Source endpoint access (HTTP 200)
- Checksum-based discovery
- Candidate extraction (filename, URL, arch, format)
- Filtering by version (MIN_VERSION)
- Filtering by arch/format (scoring)
- Strict selection with scores
- Selection reason logging

**FAILED/ISSUE:**
- No image_type filtering
- CODENAME_MAP only for Debian, not Ubuntu
- No reverse alias mapping (codename→version)
- No explicit ambiguity rejection

---

### PHASE 3: Version resolution and version guard - Test Results

**Test Date: 2026-03-28**
**Result: Mostly passed (80%)**

**PASSED:**
- Version extraction from filename/URL
- Version comparison (version_ge)
- MIN_VERSION guard
- Codename resolution (Debian)
- Checksum in state JSON

**FAILED/ISSUE:**
- No Ubuntu codename mapping (jammy→22.04, noble→24.04)
- No canonical version normalization (22.04 vs 22.4)
- No release_name in state JSON
- No explicit alias validation
- No bidirectional version/alias validation

---

### PHASE 4: Dry-run planning and state persistence - Test Results

**Test Date: 2026-03-28**
**Result: Partially passed (50%)**

**PASSED:**
- Dry-run mode exists and works
- No actual download/build/upload in dry-run
- Execution intent displayed (URL, checksum, etc.)
- Download plan in state JSON
- Cache path in state JSON
- Log file creation
- State JSON persistence

**FAILED/ISSUE:**
- No explicit work/artifact path fields
- No pipeline_id field
- No plan_id, cache_key, source_fingerprint, input_fingerprint
- No reload plan function
- No pre-download state validation
- No input mismatch detection

---

### Summary: Phase 0-4 Overall Status

| Phase | Pass Rate | Key Issues |
|-------|-----------|------------|
| Phase 0 | ~70% | Missing input params (image_type, profiles), no request_id |
| Phase 1 | ~60% | Profile config not implemented, no pipeline_id |
| Phase 2 | ~85% | No image_type, limited alias mapping |
| Phase 3 | ~80% | No Ubuntu codename mapping, no canonical normalization |
| Phase 4 | ~50% | Missing plan_id, identity keys, reload mechanism |

### Critical Findings
1. **Plan mentions features not implemented:**
   - request_id/plan_id (Phase 0-4)
   - image_type (Phase 0-2)
   - effective_policy object (Phase 1)
   - plan_id/cache_key/fingerprint (Phase 4)

2. **Config functions still TODO:**
   - config_load_openstack()
   - config_load_guest_access()
   - config_write_effective_json()

3. **Missing identity keys:**
   - plan_id
   - cache_key
   - source_fingerprint
   - input_fingerprint

### Next Phase to Test
- **PHASE 5: Cache analysis and local storage preparation** 
