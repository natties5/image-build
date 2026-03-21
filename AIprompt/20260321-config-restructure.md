settings/                    ← แก้ที่นี่ที่เดียว
├── jumphost.env             ← jumphost IP/user/branch
├── jumphost.env.example
├── git.env                  ← git URL/branch
├── git.env.example
├── openstack.env            ← network/flavor/project
├── openstack.env.example
├── openrc.env               ← path openrc
├── openrc.env.example
├── credentials.env          ← root password/key
├── credentials.env.example
└── README.md

config/                      ← ไม่ต้องแตะ ยกเว้นเพิ่ม OS
├── os/ubuntu/18.04.env
├── guest/ubuntu-24.04.env
└── pipeline/publish.env
# Config Restructure - Settings & Config Separation
# Date: 2026-03-21
# Purpose: แยก config ส่วนตัวออกจาก config ระบบให้ชัดเจน

---

## สิ่งที่ต้องทำ

แยกโครงสร้าง config ออกเป็น 2 โฟลเดอร์ชัดเจน:

```
settings/   ← ส่วนตัว gitignored ทั้งโฟลเดอร์ แก้บ่อย
config/     ← default ของระบบ track ใน git แก้น้อย
```

---

## 1. โครงสร้าง settings/ ใหม่ (ส่วนตัว gitignored)

### สร้างไฟล์เหล่านี้:

**settings/jumphost.env**
```bash
# Jump Host Connection Settings
# แก้ไฟล์นี้เพื่อเปลี่ยน jumphost

JUMP_HOST_ADDR=
JUMP_HOST_USER=
JUMP_HOST_PORT=22
JUMP_HOST_REPO_PATH=
JUMP_HOST_BRANCH=main
JUMP_SSH_KEY_FILE=
JUMP_SSH_CONFIG_FILE=
```

**settings/jumphost.env.example**
```bash
# Jump Host Connection Settings - TEMPLATE
# Copy this file to settings/jumphost.env and fill in real values

JUMP_HOST_ADDR=10.x.x.x
JUMP_HOST_USER=root
JUMP_HOST_PORT=22
JUMP_HOST_REPO_PATH=/root/image-build
JUMP_HOST_BRANCH=main
JUMP_SSH_KEY_FILE=~/.ssh/id_rsa
JUMP_SSH_CONFIG_FILE=
```

**settings/git.env**
```bash
# Git Repository Settings
# แก้ไฟล์นี้เพื่อเปลี่ยน git URL หรือ branch

REPO_URL=
BRANCH=main
```

**settings/git.env.example**
```bash
# Git Repository Settings - TEMPLATE
# Copy this file to settings/git.env and fill in real values

REPO_URL=https://github.com/yourorg/image-build.git
BRANCH=main
```

**settings/openstack.env**
```bash
# OpenStack Resource Settings
# แก้ไฟล์นี้เพื่อเปลี่ยน OpenStack resource IDs

EXPECTED_PROJECT_NAME=
NETWORK_ID=
FLAVOR_ID=
VOLUME_TYPE=
VOLUME_SIZE_GB=10
SECURITY_GROUP=
KEY_NAME=
FLOATING_NETWORK=
EXISTING_FLOATING_IP=
BASE_IMAGE_NAME_TEMPLATE=ubuntu-{version}-base-official
VM_NAME_TEMPLATE=ubuntu-{version}-ci-{ts}
VOLUME_NAME_TEMPLATE={vm_name}-boot
WAIT_SERVER_ACTIVE_SECS=600
WAIT_VOLUME_SECS=600
```

**settings/openstack.env.example**
```bash
# OpenStack Resource Settings - TEMPLATE
# Copy this file to settings/openstack.env and fill in real values

EXPECTED_PROJECT_NAME=your_project_name
NETWORK_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
FLAVOR_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
VOLUME_TYPE=cinder
VOLUME_SIZE_GB=10
SECURITY_GROUP=allow-any
KEY_NAME=
FLOATING_NETWORK=
EXISTING_FLOATING_IP=
BASE_IMAGE_NAME_TEMPLATE=ubuntu-{version}-base-official
VM_NAME_TEMPLATE=ubuntu-{version}-ci-{ts}
VOLUME_NAME_TEMPLATE={vm_name}-boot
WAIT_SERVER_ACTIVE_SECS=600
WAIT_VOLUME_SECS=600
```

**settings/openrc.env**
```bash
# OpenRC File Path Settings
# แก้ไฟล์นี้เพื่อชี้ไปหา openrc file บน jumphost

OPENRC_FILE=
```

**settings/openrc.env.example**
```bash
# OpenRC File Path Settings - TEMPLATE
# Copy this file to settings/openrc.env and fill in real values

OPENRC_FILE=/root/openrc-projectname
```

**settings/credentials.env**
```bash
# VM Access Credentials
# แก้ไฟล์นี้เพื่อตั้ง password เข้า VM

ROOT_USER=root
ROOT_PASSWORD=
ROOT_AUTHORIZED_KEY=
SSH_PORT=22
```

**settings/credentials.env.example**
```bash
# VM Access Credentials - TEMPLATE
# Copy this file to settings/credentials.env and fill in real values

ROOT_USER=root
ROOT_PASSWORD=
ROOT_AUTHORIZED_KEY=
SSH_PORT=22
```

---

## 2. โครงสร้าง config/ ที่ปรับปรุง (track ใน git)

### config/os/ — ไม่เปลี่ยน โครงสร้างเดิม

ยังคงมี:
- `config/os/ubuntu/base.env`
- `config/os/ubuntu/18.04.env`
- `config/os/ubuntu/22.04.env`
- `config/os/ubuntu/24.04.env`
- `config/os/debian/base.env` ฯลฯ

### config/guest/ — ไม่เปลี่ยน โครงสร้างเดิม

ยังคงมี:
- `config/guest/base.env`
- `config/guest/ubuntu-18.04.env`
- `config/guest/ubuntu-24.04.env`

### config/pipeline/ — ไม่เปลี่ยน โครงสร้างเดิม

ยังคงมี:
- `config/pipeline/publish.env`
- `config/pipeline/clean.env`

---

## 3. สิ่งที่ต้องลบออก

ลบหรือย้ายไฟล์เหล่านี้ที่ซ้ำซ้อนกับ settings/ ใหม่:

```
ลบออก:
- config/jumphost/jumphost.env        ← ย้ายไป settings/jumphost.env
- config/git/git.env                  ← ย้ายไป settings/git.env
- config/openstack/project-natties.env ← ย้ายไป settings/openstack.env
- config/openstack/openrc.path        ← ย้ายไป settings/openrc.env
- config/credentials/guest-access.env.example ← ย้ายไป settings/credentials.env.example
- deploy/local/control.env            ← รวมเข้า settings/jumphost.env
- deploy/local/openstack.env          ← รวมเข้า settings/openstack.env
- deploy/local/openrc.path            ← รวมเข้า settings/openrc.env
- deploy/local/guest-access.env       ← รวมเข้า settings/credentials.env
```

---

## 4. อัปเดต .gitignore

```gitignore
# Settings (private - never commit)
settings/
!settings/*.env.example

# เก่าที่ยังต้องเก็บ
deploy/local/**
!deploy/local/.gitkeep

# Runtime artifacts
cache/**
tmp/**
runtime/state/**
logs/*.log
logs/**/*.log
manifests/**/*.tsv
manifests/**/*.json

# Node
node_modules/
package.json
package-lock.json

# OS
.DS_Store
```

---

## 5. อัปเดต lib/control_jump_host.sh

แก้ loading order ให้อ่านจาก settings/ แทน deploy/local/:

```bash
imagectl_load_jump_host_config() {
  local settings_dir="$IMAGECTL_REPO_ROOT/settings"

  # โหลด settings ส่วนตัวก่อน
  local files=(
    "$settings_dir/jumphost.env"
    "$settings_dir/git.env"
    "$settings_dir/openstack.env"
    "$settings_dir/openrc.env"
    "$settings_dir/credentials.env"
  )

  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      # shellcheck disable=SC1090
      source "$f"
    fi
  done

  # fallback: ถ้า settings/ ไม่มี ให้ดู deploy/local/ เดิม (backward compat)
  local local_file="$IMAGECTL_REPO_ROOT/deploy/local/control.env"
  if [[ -f "$local_file" ]]; then
    source "$local_file"
  fi

  # ตั้งค่า default
  JUMP_HOST_PORT="${JUMP_HOST_PORT:-22}"
  JUMP_HOST_BRANCH="${JUMP_HOST_BRANCH:-main}"
  JUMP_HOST_REPO_URL="${JUMP_HOST_REPO_URL:-$(imagectl_default_repo_url)}"

  # trim whitespace/CRLF
  JUMP_HOST_ADDR="$(imagectl_trim_value "${JUMP_HOST_ADDR:-}")"
  JUMP_HOST_USER="$(imagectl_trim_value "${JUMP_HOST_USER:-}")"
  JUMP_HOST_REPO_PATH="$(imagectl_trim_value "${JUMP_HOST_REPO_PATH:-}")"
  JUMP_HOST_BRANCH="$(imagectl_trim_value "${JUMP_HOST_BRANCH:-}")"

  # validate required
  [[ -n "$JUMP_HOST_REPO_PATH" ]] || imagectl_die "JUMP_HOST_REPO_PATH is empty. Set settings/jumphost.env"
  [[ -n "$JUMP_HOST_BRANCH" ]]    || imagectl_die "JUMP_HOST_BRANCH is empty. Set settings/jumphost.env"
  [[ -n "$JUMP_HOST_REPO_URL" ]]  || imagectl_die "JUMP_HOST_REPO_URL is empty. Set settings/git.env"

  if [[ -z "${JUMP_HOST_ALIAS:-}" ]]; then
    [[ -n "$JUMP_HOST_USER" ]] || imagectl_die "JUMP_HOST_USER is empty. Set settings/jumphost.env"
    [[ -n "$JUMP_HOST_ADDR" ]] || imagectl_die "JUMP_HOST_ADDR is empty. Set settings/jumphost.env"
  fi
}
```

---

## 6. อัปเดต lib/runtime_helpers.sh

แก้ให้อ่านจาก settings/ แทน deploy/local/:

```bash
imagectl_runtime_merge_sources_local() {
  local repo_root="$IMAGECTL_REPO_ROOT"
  local settings_dir="$repo_root/settings"

  # โหลด config OS และ guest ก่อน (tracked)
  for f in \
    "$repo_root/config/guest/base.env" \
    "$repo_root/config/pipeline/publish.env" \
    "$repo_root/config/pipeline/clean.env"
  do
    [[ -f "$f" ]] && source "$f"
  done

  # โหลด settings ส่วนตัว (gitignored)
  for f in \
    "$settings_dir/jumphost.env" \
    "$settings_dir/git.env" \
    "$settings_dir/openstack.env" \
    "$settings_dir/openrc.env" \
    "$settings_dir/credentials.env"
  do
    [[ -f "$f" ]] && source "$f"
  done

  # fallback deploy/local/ สำหรับ backward compatibility
  for f in \
    "$repo_root/deploy/local/control.env" \
    "$repo_root/deploy/local/openstack.env" \
    "$repo_root/deploy/local/openrc.path" \
    "$repo_root/deploy/local/guest-access.env"
  do
    [[ -f "$f" ]] && source "$f"
  done
}
```

---

## 7. อัปเดต lib/runtime_helpers.sh — sync list

แก้ไฟล์ที่ sync ไป jumphost ให้รวม settings/:

```bash
imagectl_runtime_config_items() {
  cat <<'EOF'
settings/jumphost.env
settings/git.env
settings/openstack.env
settings/openrc.env
settings/credentials.env
EOF
}

imagectl_runtime_required_remote_files() {
  cat <<'EOF'
settings/openstack.env
settings/openrc.env
settings/credentials.env
EOF
}
```

---

## 8. README สำหรับ settings/

สร้าง **settings/README.md**:

```markdown
# Settings (Private Configuration)

โฟลเดอร์นี้เก็บ config ส่วนตัวทั้งหมด gitignored ทั้งหมดยกเว้น *.env.example

## Setup เริ่มต้น

Copy ทุกไฟล์ .example แล้วแก้ค่าจริง:

```bash
cp settings/jumphost.env.example   settings/jumphost.env
cp settings/git.env.example        settings/git.env
cp settings/openstack.env.example  settings/openstack.env
cp settings/openrc.env.example     settings/openrc.env
cp settings/credentials.env.example settings/credentials.env
```

## ไฟล์และความหมาย

| ไฟล์ | แก้เมื่อ |
|------|---------|
| jumphost.env | เปลี่ยน jumphost IP/user/port/branch |
| git.env | เปลี่ยน git repo URL หรือ branch |
| openstack.env | เปลี่ยน network/flavor/project |
| openrc.env | เปลี่ยน path ของ openrc บน jumphost |
| credentials.env | เปลี่ยน root password/key ของ VM |
```

---

## 9. ตารางสรุป "แก้อะไร ไปที่ไหน"

| อยากแก้อะไร | ไฟล์ที่ต้องแก้ |
|-------------|--------------|
| jumphost IP/user/port | `settings/jumphost.env` |
| git URL/branch | `settings/git.env` |
| openstack network/flavor | `settings/openstack.env` |
| path ของ openrc | `settings/openrc.env` |
| root password VM | `settings/credentials.env` |
| mirror ubuntu 18.04 | `config/guest/ubuntu-18.04.env` |
| mirror ubuntu 24.04 | `config/guest/ubuntu-24.04.env` |
| เพิ่ม ubuntu 25.04 | สร้าง `config/os/ubuntu/25.04.env` |
| policy publish image | `config/pipeline/publish.env` |
| policy clean VM | `config/pipeline/clean.env` |

---

## 10. ลำดับการทำงาน

```
STEP 1: สร้างโฟลเดอร์ settings/ และไฟล์ทั้งหมด (*.env และ *.env.example)
STEP 2: อัปเดต .gitignore
STEP 3: อัปเดต lib/control_jump_host.sh ให้อ่านจาก settings/
STEP 4: อัปเดต lib/runtime_helpers.sh ให้อ่านจาก settings/
STEP 5: ลบโฟลเดอร์ที่ซ้ำซ้อน (config/jumphost/, config/git/, config/credentials/)
STEP 6: เก็บ config/openstack/project-natties.env ไว้เป็น reference แต่ย้ายค่าจริงไป settings/openstack.env
STEP 7: สร้าง settings/README.md
STEP 8: ทดสอบ bash -n ทุก .sh file
STEP 9: ทดสอบ bash scripts/control.sh --help
```

---

## ข้อสำคัญ

```
DO NOT break existing pipeline behavior
DO NOT change config/os/ structure
DO NOT change config/guest/ structure
DO NOT change config/pipeline/ structure
DO keep deploy/local/ as fallback for backward compatibility
DO test bash -n on every .sh file after changes
```

