# Sync Menu Redesign — Test Summary
Date: 2026-03-22T02:45:00Z
Branch: fix/fresh-clone-and-paths
Commit: 42df877

## Changes Made
- `scripts/control.sh`: replaced `menu_sync()` and old helpers with new 7-option menu
  + `_menu_sync_all_dry_run`, `_menu_sync_os_dry_run`, `_menu_sync_os_version_download`,
    `_menu_sync_os_all_versions_download`, `_menu_sync_all_download`, `_menu_sync_show_results`
  + Updated `dispatch_command()` sync section to support all new subcommand signatures
  + Updated `show_help()` with new sync subcommands
- `lib/common_utils.sh`: added helpers:
  + `_sync_list_oses()` — returns supported OS names
  + `_sync_select_os()` — numbered OS list, reads user choice (prompts → stderr, result → stdout)
  + `_sync_list_versions_for_os(os)` — reads state JSON + sync.env TRACKED_VERSIONS, returns VERSION [STATUS] lines
  + `_sync_select_version(os)` — numbered version list with status tags, reads user choice

## New Menu Structure
```
--- Sync ---
  1) Dry-run Discover  (all OS, all tracked versions)
  2) Dry-run Discover  (select OS)
  3) Download          (select OS → select version)
  4) Download          (select OS → all versions in that OS)
  5) Download ALL      (all OS, all tracked versions)
  6) Show Sync Results
  7) Back
```

## Test Results
| Test | Description                            | Result | Notes |
|------|----------------------------------------|--------|-------|
| 1    | --help entrypoint                      | PASS   | New sync subcommands listed in help |
| 2    | sync dry-run ubuntu (direct)           | PASS   | All 4 tracked versions processed |
| 3    | sync dry-run debian (direct)           | PASS   | debian-12 dry-run complete |
| 4    | menu → Sync → Show Results             | PASS   | Full table with OS/VERSION/FORMAT/SIZE/HASH_OK/STATUS |
| 5    | menu → Sync → Dry-run select ubuntu    | PASS   | Numbered OS list shown, ubuntu selected, dry-run ran |
| 6    | menu → Sync → Dry-run all              | PASS   | All 5 OS dry-ran via option 1 |
| 7    | menu → Download → version list display | PASS   | OS list + version list with [status] tags shown |
| 8    | _sync_list_versions_for_os direct call | PASS   | ubuntu: 24.4 [failed], 24.04 [dry-run ok], 22.04 [dry-run ok], 20.04 [dry-run ok], 18.04 [dry-run ok] |
| 9    | shellcheck                             | WARN   | shellcheck not installed in this environment |
| 10   | state files readable                   | PASS   | 22 files found: 10 .json, 10 .dryrun-ok, 1 .failed |

## Version List Sample Output (ubuntu)
```
24.4 [failed]
24.04 [dry-run ok]
22.04 [dry-run ok]
20.04 [dry-run ok]
18.04 [dry-run ok]
```
Notes:
- `24.4` appears due to a previous failed run artifact (not in TRACKED_VERSIONS)
- Status reflects current state: all were re-dry-run'd during testing, clearing .ready flags
- `.ready` flag → [downloaded], `.dryrun-ok` → [dry-run ok], `.failed` → [failed], else → [not yet]

## Sync Results Table Sample (TEST 4 output)
```
=== Sync Results ===
OS            VERSION   FORMAT    SIZE        HASH_OK   STATUS
──────────  ───────  ──────  ─────────  ───────  ──────────
almalinux     8         qcow2     -           -         dry-run ok
almalinux     9         qcow2     563M        YES       downloaded  ← was downloaded before re-dry-run
debian        12        qcow2     425M        -         dry-run ok
fedora        41        qcow2     469M        YES       downloaded
rocky         8         qcow2     -           -         dry-run ok
rocky         9         qcow2     619M        YES       downloaded
ubuntu        18.04     img       387M        -         dry-run ok
ubuntu        20.04     img       618M        YES       downloaded
ubuntu        22.04     img       661M        YES       downloaded
ubuntu        24.04     img       600M        YES       downloaded
ubuntu        24.4      ?         -           NO        failed
```

## dispatch_command() New Sync Signatures
| Command                                  | Action                        |
|------------------------------------------|-------------------------------|
| `sync dry-run`                           | dry-run all OS                |
| `sync dry-run --os <os>`                 | dry-run one OS                |
| `sync dry-run --os <os> --version <v>`   | dry-run one version           |
| `sync download --os <os> --version <v>`  | download one version          |
| `sync download --os <os>`               | download all versions in OS   |
| `sync download --all`                    | download all OS, all versions |

## Download Test Note
Downloads were NOT executed during tests — only UI/navigation was tested.
Option 3 test used `timeout 5` to avoid actual download; version list UI verified.
One spurious download attempt for ubuntu-24.4 (invalid/artifact version) was triggered
by the timeout test selecting item 1 — it failed immediately (correct, expected).

## Files Modified
- `scripts/control.sh` (~120 lines changed/added in sync section)
- `lib/common_utils.sh` (~80 lines added for sync UI helpers)
