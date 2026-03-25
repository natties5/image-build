# Summary: Rocky 8/9/10 Repo Recovery and Clean Stage Success

> Historical Context Note
> This summary is preserved as a run record. Terminology and flow may be superseded by current code (see AIlogtest/00_INDEX.md and ebuild-project-doc/00_INDEX.md).

**Timestamp:** 2026-03-23T17:40:00Z
**Host:** prd-gate2-imagebuild (192.168.90.48)
**Scope:** Rocky Linux 8, 9, 10

## Starting State
- Rocky 8/9/10 VMs were already created and ACTIVE.
- Local environment (Windows) was missing state JSON files, requiring manual recovery of Server IDs and IPs from OpenStack API.
- Rocky 9 had partial history of repo failures (apt-get usage on DNF system).

## Problem(s) Encountered
1. **Missing State Files:** Local \untime/state/create/\ was empty, blocking pipeline progression.
2. **Incorrect Repo Logic:** Rocky path was incorrectly falling back to \pt-get\ or missing DNF-specific variables.
3. **OpenRC Mismatch:** Hardcoded \openrc-nutpri.sh\ vs \openrc-natties.sh\ caused API failures during \clean\ stage.
4. **CRLF Issues:** Scripts uploaded from Windows had Windows line endings, breaking execution on Linux.

## Root Cause Analysis
- **Repo Driver:** \configure_guest.sh\ defaulted to \pt\ if \GUEST_REPO_DRIVER\ was not explicitly set to \dnf-repo\.
- **Environment:** Inconsistency between local \.env\ files and jump host files.
- **Pathing:** CRLF line endings from Windows environment.

## Files Changed
1. **config/guest/rocky/default.env:** Overwritten with full DNF-repo schema and standard GUEST_* variables.
2. **config/guest/rocky/8.env & 10.env:** Created version-specific configs for Rocky 8 and 10.
3. **phases/*.sh:** Reverted hardcoded OpenRC to \openrc-nutpri.sh\ to match jump host environment.
4. **runtime/state/**: Manually reconstructed \import\ and \create\ state files for Rocky 8, 9, 10 on the jump host.

## Stages Rerun
1. **configure_guest:** Rerun for Rocky 8, 9, 10.
   - All three versions successfully fell back to Official Repos after LEGACY_MIRROR/Vault 404s.
   - Full upgrade and configuration completed.
2. **clean_guest:** Rerun for Rocky 8, 9, 10.
   - Package cache cleaned.
   - Machine-id truncated.
   - SSH host keys removed.
   - Cloud-init cleaned.
   - Fstrim executed.
   - Servers successfully reached **SHUTOFF** status via OpenStack API.

## Results per OS Version
| OS Version | Configure Result | Clean Result | Status |
|------------|------------------|--------------|--------|
| Rocky 8    | PASS (Official)  | PASS         | SHUTOFF|
| Rocky 9    | PASS (Official)  | PASS         | SHUTOFF|
| Rocky 10   | PASS (Official)  | PASS         | SHUTOFF|

## Remaining Caveats
- LEGACY_MIRROR and Vault for Rocky 8/9/10 are currently returning 404 at the expected paths. Pipeline successfully handles this via official fallback.
- Publish stage was intentionally NOT run per instructions.


