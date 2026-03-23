# Build Run — AlmaLinux 9
Date: 2026-03-23T03:26:22Z – 2026-03-23T04:22:24Z
Branch: fix/fresh-clone-and-paths
Host: prd-gate2-imagebuild

## Prereq Check
| Check | Result |
|-------|--------|
| openrc auth | PASS |
| sync .ready | PASS |
| image file | PASS (563M) |
| guest config | PASS |
| almalinux repo pattern | FIXED |

## Pipeline Result
| Phase | Duration | Status |
|-------|----------|--------|
| import_base | 15s | PASS |
| create_vm | 71s | PASS |
| configure_guest | ~530s (re-run after VPN drop) | PASS |
| clean_guest | 38s | PASS |
| publish_final | ~276s | PASS |

## Final Image
Name  : almalinux-9-20260323
ID    : 781a60aa-1ca2-443e-8693-b047eb6ea416
Status: active

## AlmaLinux-specific Notes
- repo baseurl pattern: FIXED — added almalinux OLS injection patterns to configure_guest.sh
- OLS injection: attempted, validation failed (OLS mirror has no AlmaLinux path) → rolled back correctly
- vault attempted: YES — validation failed (Cannot find valid baseurl for appstream) → rolled back
- official fallback: OK — used as final repo (all 3: OLS + vault + official-fallback)
- repo_mode_used: official-fallback / reason: ols_and_vault_failed_official_ok
- sshd service: OK
- Locale via localectl: OK
- Firewall (firewalld) disabled: OK
- Auto-update timers disabled: OK

## Bugs Found & Fixed
1. configure_guest.sh line 195 — OLS injection (dnf-repo branch) was missing AlmaLinux baseurl patterns
   Before: only had  and 
   Fixed : added  and
            patterns

## Incident — VPN Dropout
- configure_guest.sh was launched from Windows→build-host SSH session
- VPN dropped at ~03:28 UTC → SSH session killed → configure process received SIGHUP
- Host unreachable for ~36 min (TTL expired in transit from 10.88.88.1)
- Guest VM (5450d973) remained ACTIVE throughout — unaffected
- Mitigation: re-launched configure with nohup to survive future VPN drops
- Note about auto-promote warn: default.env lacks GUEST_OS_VERSION — non-critical

## Orphan Resources
Servers  : none
Volumes  : none
Base img : none (deleted in publish_final)
