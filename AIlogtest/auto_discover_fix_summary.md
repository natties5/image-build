# Auto-Discover Fix — 3 Bugs Fixed
Date: 2026-03-23T07:51:00Z
Branch: fix/fresh-clone-and-paths

## Fix 1 — Ubuntu LTS filter
Before: [[ "$ver" =~ ^[0-9]+\.04$ ]] only
After : even year check added (year % 2 == 0)
Result: 25.04 filtered out ✅ 24.04 kept ✅

## Fix 2 — Debian verify before add
Before: add version based on codename map only
After : curl HTTP 200 check on image directory
Result: debian 14 (forky) filtered until images exist ✅
Note  : Already correctly implemented in previous commit — no code change needed

## Fix 3 — Fedora verify before add
Before: HTTP 200 check on archive directory (directory exists but may have no images)
After : grep for CHECKSUM file in archives/ directory listing
Result: fedora 42/43 filtered — not in archives yet → correctly excluded ✅

## Discovered Versions After Fix
| OS | Before fix | After fix |
|----|------------|-----------|
| ubuntu | 24.04 25.04 | 24.04 only |
| debian | 13 14 | 13 only |
| fedora | 41 42 43 | 41 only |
| rocky | 8 9 10 | 8 9 10 |
| almalinux | 8 9 10 | 8 9 10 |

## Self-maintaining behavior
- Ubuntu 26.04 releases → even year → passes filter → auto-add ✅
- Debian 14 releases → HTTP 200 → auto-add ✅
- Fedora 42 moves to archives → CHECKSUM found → auto-add ✅
- No manual changes needed in future

## Test Results
| Test | Description | Result |
|------|-------------|--------|
| 1 | Ubuntu 25.04 filtered | PASS |
| 2 | Debian 14 filtered | PASS |
| 3 | Fedora 42/43 filtered | PASS |
| 4 | Rocky 10 present | PASS |
| 5 | AlmaLinux 10 present | PASS |
| 6 | Full dry-run | PARTIAL — failures from pre-existing wrong TRACKED_VERSIONS in sync.env (separate issue) |
| 7 | git diff targeted | PASS — only lib/common_utils.sh changed |

## Note on dry-run failures
sync_download.sh reads TRACKED_VERSIONS from sync.env directly.
The pre-existing uncommitted sync.env changes contain incorrect entries (ubuntu 25.04, debian 14, fedora 42/43).
These were added by a previous auto-discover run BEFORE this fix.
The auto-discover function now correctly excludes them → future _sync_update_tracked_versions runs will not add them again.
Fixing TRACKED_VERSIONS in sync.env requires a separate cleanup commit.
