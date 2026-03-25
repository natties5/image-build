# Build Run â€” Rocky Linux 9

> Historical Context Note
> This summary is preserved as a run record. Terminology and flow may be superseded by current code (see AIlogtest/00_INDEX.md and ebuild-project-doc/00_INDEX.md).

Date: 2026-03-22T15:58:26Z â€“ 2026-03-22T16:14:10Z
Branch: fix/fresh-clone-and-paths
Host: prd-gate2-imagebuild

## Git Status Before Run
Branch: fix/fresh-clone-and-paths
Last commit: aaf330a fix(clean): use openstack API for poweroff + fix locale string
Working tree: clean

## Prereq Check
| Check              | Result    |
|--------------------|-----------|
| openrc auth        | PASS      |
| sync .ready flag   | PASS      |
| image file exists  | PASS (619M) |
| openstack.env      | PASS      |
| guest-access.env   | PASS      |
| guest config       | PASS      |
| configure dnf/rhel | ADDED (3 fixes applied) |

## configure_guest.sh RHEL Fixes Applied
1. PHASE 4 â€” Repo Backup: added dnf-repo branch (backs up /etc/yum.repos.d/*.repo)
2. PHASE 5 â€” LEGACY_MIRROR Injection: added dnf-repo branch (disables mirrorlist/metalink, enables baseurl)
            LEGACY_MIRROR Rollback: added dnf-repo branch (restores .repo + dnf clean + makecache)
3. PHASE 9 â€” Locale: added localectl branch (uses GUEST_LOCALE_METHOD=localectl for RHEL)

## Pipeline Result
| Phase            | Duration | Status    |
|------------------|----------|-----------|
| import_base      | 15s      | PASS      |
| create_vm        | 69s      | PASS      |
| configure_guest  | 370s     | PASS      |
| clean_guest      | 76s      | PASS      |
| publish_final    | 310s     | PASS      |

## Final Image
Name  : rocky-9-20260322
ID    : 91da84df-a21b-45c2-bbbf-7f4fbdbb346b
Status: active

## RHEL-specific Notes
- dnf support: ADDED (3 fixes to configure_guest.sh)
- LEGACY_MIRROR injection: injected via dnf-repo driver â€” validation failed (404 on rocky path) â†’ rolled back to official repo correctly
- sshd service restart: OK (GUEST_SSH_SERVICE=sshd read from 9.env)
- Locale via localectl: OK (GUEST_LOCALE_METHOD=localectl read from 9.env)
- Firewall (firewalld) disabled: OK
- Auto-update timers disabled: OK
- Packages installed: wget (others already present)

## Orphan Resources
Servers  : none
Volumes  : none
Base img : none (deleted in publish_final)

## Notes / Minor Issues
1. configure_guest Phase 3 (Baseline Repo): DNS resolve warning (dns-warn) â€” non-fatal, direct IP connectivity OK
2. configure_guest Phase 5 (LEGACY_MIRROR): LEGACY_MIRROR reachable but Rocky path returns 404 (/pub/rocky/9/...) â†’ correct rollback to official repo
3. clean_guest: cloud-init clean + fstrim got connection reset (expected â€” SSH host keys removed before shutdown)
4. clean_guest: openstack API stop worked cleanly (SHUTOFF in ~14s)

