# Summary: AlmaLinux 8/9/10 Repo Recovery and Clean Stage Success
**Timestamp:** 2026-03-23T21:20:00Z
**Host:** prd-gate2-imagebuild (192.168.90.48)
**Scope:** AlmaLinux 8, 9, 10

## Starting State
- AlmaLinux 8/9/10 VMs were already created and ACTIVE.
- `config/guest/almalinux/default.env` was in TODO state (old schema).
- `config/guest/almalinux/9.env` existed but versions 8 and 10 were missing or inconsistent.
- Previous attempts at `configure_guest` had partial history of hangs or CRLF issues.

## Problem(s) Encountered
1. **Script Hang during DNF:** `configure_guest.sh` was capturing large output from `dnf upgrade` into a variable, causing it to appear hung and eventually timeout.
2. **CRLF Issues:** Configuration files created/uploaded had Windows line endings, breaking shell execution on the jump host.
3. **Repo Driver Mismatch:** AlmaLinux path needed explicit `GUEST_REPO_DRIVER=dnf-repo` to avoid silent fallback to `apt`.
4. **OLS/Vault 404:** OpenLandscape and AlmaLinux Vault mirrors returned 404 for the requested paths.

## Root Cause Analysis
- **Logging Logic:** The script's `_OUT="$(_gssh ...)"` pattern is unsuitable for long-running commands with high-volume output.
- **Line Endings:** Windows-based environment during file creation.
- **Mirror Availability:** The specific URLs for OLS/Vault are either incorrect for Alma or currently offline.

## Files Changed / Created
1. **config/guest/almalinux/default.env:** Upgraded to full `GUEST_*` schema (DNF-based).
2. **config/guest/almalinux/8.env, 9.env, 10.env:** Created/Updated with correct version-specific identity and inherited defaults.
3. **phases/configure_guest.sh:** 
   - Added `_gssh_log` helper to stream output line-by-line to `util_log_info`.
   - Updated Baseline, OLS, Vault, Update, Upgrade, and Package stages to use streaming logs.
   - Fixed CRLF in the script itself.

## Stages Rerun
1. **configure_guest:** Rerun for AlmaLinux 8, 9, 10.
   - All three versions successfully fell back to Official Repos after OLS/Vault 404s.
   - Full `dnf upgrade` and package installation (`wget`, etc.) completed.
   - Output was streamed successfully, preventing hangs.
2. **clean_guest:** Rerun for AlmaLinux 8, 9, 10.
   - Package cache cleaned.
   - Machine-id truncated.
   - SSH host keys removed.
   - Cloud-init cleaned.
   - Fstrim executed.
   - Servers successfully reached **SHUTOFF** status via OpenStack API.

## Results per OS Version
| OS Version | Configure Result | Clean Result | Status | Repo Used |
|------------|------------------|--------------|--------|-----------|
| AlmaLinux 8| PASS             | PASS         | SHUTOFF| Official  |
| AlmaLinux 9| PASS             | PASS         | SHUTOFF| Official  |
| AlmaLinux 10| PASS            | PASS         | SHUTOFF| Official  |

## Final Verification
- [x] AlmaLinux 8 succeeds through clean
- [x] AlmaLinux 9 succeeds through clean
- [x] AlmaLinux 10 succeeds through clean
- [x] No `apt` commands incorrectly invoked
- [x] Logging is now streaming and reliable
- [x] All VMs are in SHUTOFF state ready for capture/publish

## Git Workflow
- All changes applied to `/mnt/vol-image/image-build` on the jump host.
- Committing and pushing from the authoritative environment.
