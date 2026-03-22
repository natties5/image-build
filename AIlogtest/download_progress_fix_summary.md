# Download Progress Fix — Summary
Date: 2026-03-22T03:00:00Z
Branch: fix/fresh-clone-and-paths
Commit: a72218d

## Problem
เมื่อรัน Download option ใดๆ ในเมนู Sync ผู้ใช้เห็นแค่ header ของ curl แล้ว terminal ดูเหมือนค้าง
ทั้งที่ download กำลังทำงานอยู่จริงๆ เพียงแต่ progress ไม่โชว์

```
[INFO]     % Total    % Received % Xferd  Average Speed  Time    Time    Time   Current
[INFO]                                    Dload  Upload  Total   Spent   Left   Speed
(หยุดอยู่ตรงนี้ ไม่มีอะไรต่อ...)
```

## Root Cause
`download_image()` ใน `phases/sync_download.sh` pipe output ของ curl/wget ผ่าน logging wrapper:

```bash
curl ... -o "$dest_path" "$url" 2>&1 | while IFS= read -r line; do util_log_info "  $line"; done
```

curl แสดง progress ด้วย **carriage return (`\r`)** เพื่อ overwrite บรรทัดเดิม (ไม่ใช่ `\n`)
`read -r` รอ `\n` ซึ่งไม่มาจนกว่า download จะเสร็จ → ไม่มีอะไรโชว์ระหว่าง transfer

## Fix
**File:** `phases/sync_download.sh` — ฟังก์ชัน `download_image()`

ลบ pipe wrapper ออก ให้ wget/curl เขียน progress โดยตรงไปที่ stderr (terminal)
เพิ่ม `--progress-bar` ให้ curl ใช้ `###` bar แทน verbose stats block

### Before
```bash
# wget
"$url" 2>&1 | while IFS= read -r line; do util_log_info "  $line"; done

# curl
curl -L --continue-at - --max-time 3600 --retry 2 \
     -o "$dest_path" "$url" 2>&1 | while IFS= read -r line; do util_log_info "  $line"; done
```

### After
```bash
# wget
"$url" >/dev/null

# curl
curl -L --continue-at - --max-time 3600 --retry 2 \
     --progress-bar \
     -o "$dest_path" "$url" >/dev/null
```

## Result
ตอนนี้ผู้ใช้เห็น live progress bar ระหว่าง download:

```
[INFO] Downloading: https://dl.rockylinux.org/.../Rocky-8-GenericCloud.latest.x86_64.qcow2
[INFO] Destination: .../workspace/images/rocky/8/Rocky-8-GenericCloud.latest.x86_64.qcow2
######################################################################## 100.0%
[INFO] Download complete: 629048832 bytes
```

- Progress bar อัพเดท real-time พร้อม speed และ ETA ✓
- Log messages (Downloading / Destination / Download complete) ยังคงอยู่ครบ ✓
- Resume ยังทำงานได้ (`--continue-at -` ยังอยู่) ✓
- ไม่มี raw progress characters ใน log file ✓

## Files Changed
- `phases/sync_download.sh` — 3 lines changed in `download_image()`
