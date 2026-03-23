# Fix: Repo Driver + Restore — configure_guest + clean_guest
Date: 2026-03-23T00:00:00Z
Branch: fix/fresh-clone-and-paths

## Root Cause
configure_guest.sh defaulted to apt-get for ALL OS families.
dnf-family OS (Rocky/AlmaLinux/Fedora) got wrong commands →
official repo falsely degraded → vault used unnecessarily.
clean_guest.sh never restored official repo before poweroff →
final image had vault/OLS repo instead of official.

## Fixes Applied
| Fix | Location | Before | After |
|-----|----------|--------|-------|
| 1 | Phase 3 baseline | apt-get update | dnf makecache / apt-get update |
| 2 | Phase 5c last resort | apt-get update | dnf makecache / apt-get update |
| 3 | Phase 6 update | apt-get update | dnf makecache / apt-get update |
| 4 | Phase 6 upgrade | apt-get dist-upgrade | dnf upgrade --nobest / apt-get dist-upgrade |
| 5 | vault validation | apt-get | dnf makecache / apt-get |
| 6 | clean_guest | (missing) | restore official repo before poweroff |

## Impact
After this fix:
- dnf OS baseline test uses dnf → official repo correctly detected
- update/upgrade uses correct package manager
- final image always has official repo (not vault/OLS)
- ubuntu/debian unaffected

## Needs Rebuild
almalinux 8/9/10, rocky 8/9/10 (vault repo was in final image)
ubuntu 24.04 — NOT affected

## Test Results
| Test | Result |
|------|--------|
| FIX 1 baseline dnf | PASS |
| FIX 2 last resort dnf | PASS |
| FIX 3 update dnf | PASS |
| FIX 4 upgrade dnf | PASS |
| FIX 5 vault val dnf | PASS |
| FIX 6 restore in clean | PASS |
| git diff stat (only 2 files) | PASS |
| apt-get count < dnf count | PASS (11 vs 18) |
