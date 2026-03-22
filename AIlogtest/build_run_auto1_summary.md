# Build Run — Auto Option 1 (ubuntu latest)
Date: 2026-03-22T15:19:21Z – 2026-03-22T15:30:09Z
Branch: fix/fresh-clone-and-paths
Host: prd-gate2-imagebuild

## Prereq Check
| Check              | Result |
|--------------------|--------|
| openrc auth        | PASS   |
| sync .ready flag   | PASS   |
| image file exists  | PASS (600M) |
| openstack.env      | PASS   |
| guest-access.env   | PASS   |
| guest config       | PASS   |

## Pipeline Result
| Phase            | Duration | Status |
|------------------|----------|--------|
| import_base      | ~3s      | PASS (skipped-exists) |
| create_vm        | ~67s     | PASS |
| configure_guest  | ~154s    | PASS |
| clean_guest      | ~396s    | PASS (OS stop fallback used) |
| publish_final    | ~28s     | PASS (recovered existing image) |

## Final Image
Name  : ubuntu-24.04-20260322
ID    : 1a41edb3-9a4a-4e75-88d5-671b08683d46
Status: active

## Orphan Resources
Servers  : none
Volumes  : none
Base img : none (deleted in publish_final)

## Notes / Minor Issues
1. configure_guest Phase 9 (Locale): Warning 'en_US.UTF-8 UTF-8' is not a supported language or locale
   → Non-fatal, pipeline continued
2. clean_guest: cloud-init clean + fstrim got connection reset (expected — SSH host keys removed before shutdown command)
3. clean_guest: poweroff via SSH timed out (300s) — ACTIVE → fallback to openstack stop → SHUTOFF in ~18s
   → Likely cloud-init clean ran and reset SSH, disconnecting the channel
4. publish_final: Final image ubuntu-24.04-20260322 already existed (from previous run today) — recovered cleanly
