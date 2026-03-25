# 02 - Download Image System (sync_download)

Last updated: 2026-03-25
Primary source: `phases/sync_download.sh`

## 1) Purpose
`sync_download.sh` discovers and selects upstream cloud images by rules in `config/os/<os>/sync.env`.
It supports:
- dry-run discovery (`.dryrun-ok`)
- real download with checksum verification (`.ready`)
- failure manifests (`.failed`)

## 2) Inputs
Per-OS `sync.env` keys used by runtime:
- `OS_FAMILY`
- `MIN_VERSION`
- `TRACKED_VERSIONS`
- `DISCOVERY_MODE` (`checksum_driven` or `index_scan`)
- `LATEST_LOGIC` (`current_folder` or `sort_version`)
- `INDEX_URL_TEMPLATE`
- `INDEX_URL_FALLBACK` (optional; active for Fedora)
- `CHECKSUM_FILE`
- `HASH_ALGO`
- `ARCH_PRIORITY`
- `FORMAT_PRIORITY`
- `IMAGE_REGEX`
- `CODENAME_MAP` (Debian)

## 3) OS-Specific Highlights
- Ubuntu: release directories, sha256, tracked includes `24.04 25.04`
- Debian: codename map (`13=trixie`, etc.), sha512
- Fedora: primary releases URL + archive fallback URL
- Rocky/AlmaLinux: checksum-driven GenericCloud selection
- Alpine: index scan with hash-only `.sha512` normalization
- Arch: latest rolling image (`latest`)

## 4) Selection Flow
1. Load sync config
2. Choose version(s): explicit `--version` or `TRACKED_VERSIONS`
3. Resolve URL template tokens (`{VERSION}`, `{CODENAME}`)
4. Fetch checksum source (primary then fallback if configured)
5. Parse checksum formats (GNU + BSD; hash-only normalization)
6. Filter by `IMAGE_REGEX`
7. Score by `ARCH_PRIORITY` then `FORMAT_PRIORITY`
8. Select winner image URL/hash
9. Dry-run or download path

## 5) Output Model
Per `os/version`:
- JSON: `runtime/state/sync/<os>-<version>.json`
- Flags:
  - `.dryrun-ok` for dry-run success
  - `.ready` for verified download success
  - `.failed` for failure
- Log: `runtime/logs/sync/<os>-<version>.log`

## 6) Integrity Guarantees
- `.ready` is written only after checksum verification passes.
- Corrupt downloaded file is removed on hash mismatch.
- Cached local file is reused only if checksum matches.

## 7) Control Surface
CLI examples:
- `bash scripts/control.sh sync dry-run --os ubuntu`
- `bash scripts/control.sh sync download --os fedora --version 41`
- `bash scripts/control.sh sync download --all`

Menu and helper functions for sync lives in:
- `scripts/control.sh`
- `lib/common_utils.sh` (`_sync_*` helpers)
