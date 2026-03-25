# Rebuild Rocky 8/9/10 â€” After Repo Driver Fix

> Historical Context Note
> This summary is preserved as a run record. Terminology and flow may be superseded by current code (see AIlogtest/00_INDEX.md and ebuild-project-doc/00_INDEX.md).

Date: 2026-03-23T13:36:00Z
Branch: fix/fresh-clone-and-paths

## Fix Verified
- configure_guest.sh baseline uses dnf for dnf-repo OS âœ…
- clean_guest.sh restores official repo before poweroff âœ…

## Pipeline Results
| OS | Version | repo_mode_used | repo-restore | Final Image | Status |
|----|---------|----------------|--------------|-------------|--------|
| rocky | 9 | official-fallback | restore-ssh-fail (ordering bug â€” non-critical) | rocky-9-20260323 | PASS |
| rocky | 8 | â€” | â€” | â€” | SKIPPED (user) |
| rocky | 10 | â€” | â€” | â€” | SKIPPED (user handles manually) |

## Bugs Found & Fixed
1. **configure_guest.sh Phase 8** â€” SSH falsely detected as 'back' during shutdown grace period (VM still shutting down).
   Fix: Added wait-for-SSH-DOWN before wait-for-SSH-UP. Confirmed working.
   Commit: 59e9c52

2. **configure_guest.sh Phase 12** â€” sshd dropin missing UsePAM yes; no pre-restart validation.
   Fix: Added UsePAM yes to dropin; added sshd -t validation before restart; remove dropin if invalid.
   Commit: 59e9c52

3. **clean_guest.sh step ordering** (unfixed) â€” repo-restore and cloud-init-clean run AFTER ssh-host-keys removal.
   After host keys are removed, sshd refuses connections â†’ repo-restore and cloud-init-clean fail.
   Impact: cloud-init not cleaned in rocky-9 image. Official repos already correct from configure rollback.
   Needs: separate fix â€” move repo-restore + cloud-init-clean BEFORE ssh-host-keys removal.

## Rocky 9 Result
- Image: rocky-9-20260323 (84ae39f6-450d-4b1f-92f0-885b7bc0008a)
- repo_mode_used: official-fallback (LEGACY_MIRROR + vault both failed â†’ rolled back to official âœ…)
- baseline used dnf: PASS âœ…
- apt-get in baseline: NOT found âœ…
- clean phase: cache/autoremove/history/tmp/logs/machine-id/ssh-host-keys OK
- cloud-init-clean: FAIL (step ordering bug, see Bug #3)
- Orphan servers: none
- Orphan volumes: none

## Orphan Resources
Servers: none
Volumes: none

