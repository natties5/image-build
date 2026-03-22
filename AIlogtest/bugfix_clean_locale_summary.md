# Bug Fix — clean_guest poweroff + locale
Date: 2026-03-22T00:00:00Z
Branch: fix/fresh-clone-and-paths

## Fix 1 — clean_guest.sh poweroff
Before: SSH run "shutdown -h now" → unreliable after host keys removed
After : openstack_cmd server stop "$server_id"
Affects: ALL OS (ubuntu/debian/rocky/almalinux/fedora)
Lines changed: 5 (3 removed, 5 added — net +2 with comments)

## Fix 2 — GUEST_LOCALE_GENERATION
Before: "en_US.UTF-8 UTF-8"
After : "en_US.UTF-8"
Files : config/guest/ubuntu/24.04.env
        config/guest/ubuntu/default.env (exists, same fix applied)

## Verify Results
| Check                        | Result |
|------------------------------|--------|
| SSH shutdown removed         | PASS   |
| openstack server stop added  | PASS   |
| locale string fixed          | PASS   |
| git diff minimal             | PASS   |
| shellcheck clean_guest       | SKIP (shellcheck not on Windows; run on Linux) |

## Other Logic Unchanged
- cleanup steps order: unchanged
- cloud-init clean: unchanged
- machine-id truncate: unchanged
- ssh host keys removal: unchanged
- fstrim: unchanged
- wait SHUTOFF polling logic: unchanged
