# Fix Pipeline Menu Bugs
# Date: 2026-03-21
# File: lib/control_pipeline.sh
# Priority: CRITICAL — ทุก Run menu หลุดออก shell ก่อนทำงานจริง

---

## คำสั่งสำหรับ AI

```
Read this file completely before making any changes.
Fix ONLY the issues described here.
Do NOT refactor or reorganize anything else.
Do NOT change pipeline behavior or phase logic.
After fixing, run: bash -n lib/control_pipeline.sh
```

---

## Root Cause หลัก

`imagectl_die()` เรียก `exit 1` ซึ่ง kill ทั้ง process
ทำให้เมื่อ `runtime_prepare` fail → script หลุดออก shell ทันที
แทนที่จะแสดง error แล้วกลับ menu

---

## Bug 1: imagectl_auto_by_os — หลุดหลัง download

### อาการ
```
เลือก Run → By OS → ubuntu
→ download สำเร็จ
→ หลุดออก shell ทันที ไม่มี error message
```

### สาเหตุ
`imagectl_runtime_prepare_for_full_pipeline()` ถูกเรียกหลัง discover
แต่ fail เพราะ settings/ files ไม่ครบหรือ remote validate ไม่ผ่าน
→ imagectl_die() → exit 1 → หลุด

### แก้ไข
ใน `imagectl_auto_by_os()`:
เปลี่ยนจาก:
```bash
imagectl_runtime_prepare_for_full_pipeline
```
เป็น:
```bash
if ! imagectl_runtime_prepare_for_full_pipeline; then
  imagectl_log "ERROR: runtime prepare failed — check settings/ files"
  return 1
fi
```

---

## Bug 2: imagectl_pipeline_full_run — หลุดทันทีก่อน discover

### อาการ
```
เลือก Run → Full Run
→ หลุดออก shell ทันที
```

### สาเหตุ
`imagectl_runtime_prepare_for_full_pipeline()` ถูกเรียกก่อน discover
ทั้งที่ยังไม่รู้ว่า OS ไหน version ไหนจะรัน

### แก้ไข
ใน `imagectl_pipeline_full_run()`:
ย้าย `imagectl_runtime_prepare_for_full_pipeline` ออกจากต้น function
แล้วเรียกแทนที่ภายใน loop แต่ละ version:

```bash
imagectl_pipeline_full_run() {
  imagectl_prepare_remote_pipeline_context

  local oses=() os versions=() version
  local -a results=()
  mapfile -t oses < <(imagectl_list_supported_oses)

  # discover ทุก OS ก่อน ยังไม่ prepare
  for os in "${oses[@]}"; do
    imagectl_os_is_implemented "$os" || continue
    imagectl_log "full-run: discover os=$os"
    imagectl_run_discover_for_os "$os"
  done

  # prepare ครั้งเดียวหลัง discover ทั้งหมด
  if ! imagectl_runtime_prepare_for_full_pipeline; then
    imagectl_log "ERROR: runtime prepare failed — check settings/ files"
    return 1
  fi

  for os in "${oses[@]}"; do
    imagectl_os_is_implemented "$os" || continue
    mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")

    for version in "${versions[@]}"; do
      imagectl_log "full-run: start os=$os version=$version"
      if imagectl_auto_run_phase_sequence "$os" "$version" "no"; then
        results+=("$os $version: SUCCESS")
      else
        results+=("$os $version: FAILED")
      fi
    done
  done

  imagectl_log "full-run summary:"
  printf '%s\n' "${results[@]}" | sed 's/^/  /'
}
```

---

## Bug 3: imagectl_auto_by_os_version — หลุดหลัง download ก่อนเลือก version

### อาการ
```
เลือก Run → By Version → ubuntu
→ download สำเร็จ
→ หลุดออก shell ก่อนแสดงให้เลือก version
```

### สาเหตุ
`imagectl_runtime_prepare_for_full_pipeline()` ถูกเรียกก่อน version selection
แต่ fail → exit 1 → หลุด

### แก้ไข
ใน `imagectl_auto_by_os_version()`:
เปลี่ยนจาก:
```bash
imagectl_runtime_prepare_for_full_pipeline
```
เป็น:
```bash
if ! imagectl_runtime_prepare_for_full_pipeline; then
  imagectl_log "ERROR: runtime prepare failed — check settings/ files"
  return 1
fi
```

---

## Bug 4: imagectl_pipeline_by_phase — หลุดหลังเลือก phase

### อาการ
```
เลือก Run → By Phase → ubuntu → 18.04 → import
→ หลุดออก shell ทันที
```

### สาเหตุ
`imagectl_runtime_prepare_for_action()` ถูกเรียกสำหรับ mutating phase
แต่ fail → exit 1 → หลุด

### แก้ไข
ใน `imagectl_pipeline_by_phase()`:
เปลี่ยนจาก:
```bash
if imagectl_phase_is_mutating "$phase"; then
  imagectl_runtime_prepare_for_action "$phase"
fi
```
เป็น:
```bash
if imagectl_phase_is_mutating "$phase"; then
  if ! imagectl_runtime_prepare_for_action "$phase"; then
    imagectl_log "ERROR: runtime prepare failed for phase=$phase — check settings/ files"
    return 1
  fi
fi
```

---

## Bug 5: menu loop ไม่ดัก error — หลุดออก shell แทนกลับ menu

### อาการ
หลังจากแก้ Bug 1-4 แล้ว ถ้ายังมี error อื่น
ระบบควรกลับ menu ไม่ใช่หลุด shell

### แก้ไข
ใน `imagectl_menu_run()` ใน lib/control_pipeline.sh:
ทุก case ที่เรียก function ให้ใส่ error handling:

```bash
imagectl_menu_run() {
  imagectl_select_project_interactive >/dev/null

  while true; do
    local label="Run (รัน pipeline)"
    [[ -z "$_IMAGECTL_CURRENT_PROJECT" ]] || label+=" — project: $_IMAGECTL_CURRENT_PROJECT"

    local choice
    choice="$(imagectl_select_from_list "$label" \
      "Full Run        (ทุก OS ทุก version)" \
      "By OS           (เลือก OS)" \
      "By Version      (เลือก OS + version)" \
      "By Phase        (เลือก OS + version + phase)" \
      "Change Project  (เปลี่ยน project)" \
      "Back            (กลับ)")"

    case "$choice" in
      "Full Run"*)
        imagectl_pipeline_full_run || imagectl_log "full-run ended with error"
        ;;
      "By OS"*)
        imagectl_auto_by_os || imagectl_log "by-os ended with error"
        ;;
      "By Version"*)
        imagectl_auto_by_os_version || imagectl_log "by-version ended with error"
        ;;
      "By Phase"*)
        imagectl_pipeline_by_phase || imagectl_log "by-phase ended with error"
        ;;
      "Change Project"*)
        imagectl_select_project_interactive >/dev/null
        ;;
      "Back"*) break ;;
    esac
  done
}
```

---

## Bug 6: imagectl_menu_system — Git Sync หลุดถ้า connection fail

### อาการ
เลือก System → Git Sync → fail → หลุด shell

### แก้ไข
ใน `imagectl_menu_system()` ใน lib/control_main.sh:

```bash
"Git Sync"*) imagectl_git_dispatch sync-safe || imagectl_log "git sync failed" ;;
```

และทุก SSH/Git case เหมือนกัน:
```bash
"SSH Connect"*)   imagectl_ssh_dispatch connect   || imagectl_log "ssh connect failed" ;;
"SSH Validate"*)  imagectl_ssh_dispatch validate  || imagectl_log "ssh validate failed" ;;
"SSH Info"*)      imagectl_ssh_dispatch info      || imagectl_log "ssh info failed" ;;
"Git Bootstrap"*) imagectl_git_dispatch bootstrap || imagectl_log "git bootstrap failed" ;;
"Git Sync"*)      imagectl_git_dispatch sync-safe || imagectl_log "git sync failed" ;;
"Git Status"*)    imagectl_git_dispatch status    || imagectl_log "git status failed" ;;
```

---

## ไฟล์ที่ต้องแก้

```
lib/control_pipeline.sh   ← Bug 1, 2, 3, 4, 5
lib/control_main.sh       ← Bug 6
```

---

## สิ่งที่ห้ามแก้

```
DO NOT change phases/
DO NOT change phase execution logic
DO NOT change imagectl_die() behavior
DO NOT change config loading
DO NOT change runtime_helpers.sh validation logic
```

---

## ทดสอบหลังแก้

```bash
# ตรวจ syntax
bash -n lib/control_pipeline.sh
bash -n lib/control_main.sh

# ทดสอบ manual
bash scripts/control.sh --help
```

---

## พฤติกรรมที่ถูกต้องหลังแก้

### By OS (ubuntu ทั้งหมด)
```
Run → By OS → ubuntu
→ download/discover
→ validate settings (ถ้า fail → แสดง error → กลับ menu Run)
→ sync to jumphost
→ รัน: 18.04, 20.04, 22.04, 24.04 full pipeline
→ แสดงสรุป
→ กลับ menu Run  ← ต้องกลับ ไม่ใช่หลุด
```

### By Version (ubuntu 18.04)
```
Run → By Version → ubuntu → 18.04
→ download/discover
→ validate settings (ถ้า fail → แสดง error → กลับ menu Run)
→ sync to jumphost
→ รัน: 18.04 full pipeline
→ แสดงสรุป
→ กลับ menu Run  ← ต้องกลับ ไม่ใช่หลุด
```
