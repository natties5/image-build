# Pipeline Milestone 4 — Import/Create/Configure/Clean/Publish

Date: 2026-03-22T10:47:35Z
Branch: fix/fresh-clone-and-paths
Host: prd-gate2-imagebuild (192.168.90.48)

## Pipeline Results

| Phase     | Exit Code | Duration | Status |
|-----------|-----------|----------|--------|
| import    | 0         | 13s      | PASS   |
| create    | 0         | 69s      | PASS   |
| configure | 0         | 21s      | PASS   |
| clean     | 0         | 27s      | PASS   |
| publish   | 0         | ~870s    | PASS   |

## Final Image

Name   : ubuntu-24.04-20260322
ID     : 1a41edb3-9a4a-4e75-88d5-671b08683d46
Status : active

## Resources Cleaned Up

- Server deleted: YES (a591275a-9415-4493-8116-b804374e519f)
- Volume deleted: YES (857eff98-917e-43c0-a1ee-d520be3cf4ee)
- Base image deleted: YES (1cf9b612-0304-448e-ade4-a8c2048386bb)

## Bugs Fixed During Run

1. Ubuntu cloud image blocks password auth by default
   - Fix: inject cloud-init #cloud-config user_data on server create
   - Sets root password, enables ssh_pwauth, patches sshd_config

2. `openstack image create --volume` does not support --property or --private
   - Fix: create image first (no flags), then `openstack image set` separately

3. `openstack image create --volume -c id` returns volume UUID, not image UUID
   - Fix: ignore stdout, search Glance by name after upload to get real image ID

## State Files Written

runtime/state/import/ubuntu-24.04.json   ✓
runtime/state/import/ubuntu-24.04.ready  ✓
runtime/state/create/ubuntu-24.04.json   ✓
runtime/state/create/ubuntu-24.04.ready  ✓
runtime/state/configure/ubuntu-24.04.json ✓
runtime/state/configure/ubuntu-24.04.ready ✓
runtime/state/clean/ubuntu-24.04.json    ✓
runtime/state/clean/ubuntu-24.04.ready   ✓
runtime/state/publish/ubuntu-24.04.json  ✓
runtime/state/publish/ubuntu-24.04.ready ✓

## Log Files Written

runtime/logs/import/ubuntu-24.04.log
runtime/logs/create/ubuntu-24.04.log
runtime/logs/configure/ubuntu-24.04.log
runtime/logs/clean/ubuntu-24.04.log
runtime/logs/publish/ubuntu-24.04.log
