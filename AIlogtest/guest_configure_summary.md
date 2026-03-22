# Guest Configure — Full Phase Test (Ubuntu 24.04)
Date: 2026-03-22T14:01:13Z
Branch: fix/fresh-clone-and-paths

## Config Files Placed
| File | Path | Fixes Applied |
|------|------|---------------|
| ubuntu-24.04.env | config/guest/ubuntu/24.04.env | GUEST_INITIAL_SSH_AS_ROOT=1, GUEST_OLS_SKIP_IF_UNAVAILABLE=1 |
| ubuntu/default.env | config/guest/ubuntu/default.env | copy of 24.04.env |
| debian-12.env    | config/guest/debian/12.env    | GUEST_NETWORK_STACK=ifupdown (was netplan), GUEST_OLS_SKIP_IF_UNAVAILABLE=1 |
| rocky-9.env      | config/guest/rocky/9.env      | GUEST_OLS_SKIP_IF_UNAVAILABLE=1 |
| almalinux-9.env  | config/guest/almalinux/9.env  | GUEST_OLS_SKIP_IF_UNAVAILABLE=1 |
| fedora-41.env    | config/guest/fedora/41.env    | GUEST_OLS_SKIP_IF_UNAVAILABLE=1 |

## Pipeline Results (publish skipped)
| Phase     | Exit | Duration | Status |
|-----------|------|----------|--------|
| import    | 0    | 14s      | PASS   |
| create    | 0    | 68s      | PASS   |
| configure | 0    | 160s     | PASS   |
| clean     | 0    | 397s     | PASS   |

## Configure Phase Detail
- OLS available: YES (OLS was reachable — used)
- Reboot completed: YES (SSH back after 15s)
- Packages installed: qemu-guest-agent (new), liburing2 (dep); cloud-init, sudo, curl, wget, rsync, ca-certificates, cloud-guest-utils already current
- SSH policy applied: YES (/etc/ssh/sshd_config.d/99-image-build.conf)
- Steps completed: preflight, cloud-init-wait, baseline-repo, repo-backup, ols, update, upgrade, packages, reboot, timezone, locale, disable-autoupdate, disable-firewall, ssh-policy, services
- Locale note: locale-gen ran; update-locale had a minor warning (format mismatch) — non-fatal

## Errors (if any)
- Locale warning: 
  → locale-gen format passed to update-locale; non-fatal, timezone was set correctly
- Clean: SSH connection reset after cloud-init clean (SSH host keys removed) — expected behavior
  → fstrim/shutdown via SSH failed; fallback: os_stop_server (OpenStack API) succeeded

## State Files
runtime/state/import/ubuntu-24.04.json   (READY)
runtime/state/create/ubuntu-24.04.json   (READY)
runtime/state/configure/ubuntu-24.04.json (READY)
runtime/state/clean/ubuntu-24.04.json    (READY)

## Remaining Resources (publish skipped — clean up manually or run publish)
- Server: build-ubuntu-24.04-20260322205007 (id: 99d631e2-16bf-41b9-b18d-0d2005bbebe2) — SHUTOFF
- Volume: vol-ubuntu-24.04-20260322205007 (id: eddb8a54-3b6d-4ee2-8bd5-0252e4f6ee86) — in-use (attached to SHUTOFF server)
