# 09 — Implementation Roadmap

เอกสารนี้สรุปลำดับการลงมือทำที่แนะนำ

---

## 1. Phase ordering

### Milestone 1 — Foundation
- create `scripts/control.sh`
- create `lib/core_paths.sh`
- create `lib/common_utils.sh`
- create `lib/openstack_api.sh`
- create `settings/` templates
- create runtime directories and path helpers

### Milestone 2 — Sync
- implement `phases/sync_download.sh`
- support dry-run first
- support JSON/flags/logs
- add one working OS rule set first (Ubuntu)
- then add Debian / Rocky / Alma / Fedora

### Milestone 3 — Settings menu
- validate openrc/auth
- list/select project/network/flavor/volume type/security group/floating network
- edit/save guest access
- write `settings/openstack.env` and `settings/guest-access.env`

### Milestone 4 — Import/Create
- implement import base image
- implement create volume
- implement create VM
- write create manifests / configure input env/json

### Milestone 5 — Configure/Clean
- implement guest configure from new config model
- implement OLS failover
- implement final clean
- implement runtime JSON and flags

### Milestone 6 — Publish
- implement delete server / wait volume available
- implement upload-to-image
- implement final metadata/tags
- implement cleanup and partial success logic

### Milestone 7 — Resume / Status / Cleanup menus
- runtime dashboard
- resume by state
- cleanup current run
- orphan reconcile

### Milestone 8 — Tests / CI
- ShellCheck
- shfmt
- Bats
- sync dry-run tests
- config merge tests
- state path tests
- openstack wrapper mock tests

---

## 2. First target OS
Start with:
- Ubuntu 24.04
Then:
- Ubuntu 22.04
- Debian 12
- Rocky 9
- AlmaLinux 9
- Fedora 40

Reason:
- Ubuntu path helps validate the entire architecture fastest

---

## 3. What should be rewritten vs reused

### Reuse ideas / partial code
- existing path layer concepts
- existing wait loops and OpenStack command patterns
- existing configure remote script ideas
- existing publish recovery/cleanup logic
- existing menu idea of run/resume/status/cleanup

### Rewrite / remove
- jump host SSH menu
- git bootstrap/sync to jump host
- `deploy/local/*`
- inconsistent config fallback layers
- phase files with embedded duplicated helpers

---

## 4. Minimum viable end-to-end flow

The first successful vertical slice should be:
1. Settings auth/resource selection works
2. Sync dry-run works
3. Sync download works for Ubuntu 24.04
4. Import base image works
5. Create volume + VM works
6. Configure guest works with OLS failover
7. Final clean works
8. Publish final image works
9. Cleanup leaves no important resource leak

---

## 5. Definition of done by subsystem

### Sync
- dry-run works
- JSON + flags + logs written
- download verifies hash
- ready status only after verification

### Settings
- menu can select resources from OpenStack
- saves to `settings/openstack.env`
- guest access editor works
- validation catches missing data

### Import/Create
- base image import works with exists policy
- volume create waits properly
- server create returns login IP
- create state written correctly

### Configure
- default + version config merge works
- OLS fallback works
- update/reboot/reconnect works
- root SSH policy works
- final validation works

### Publish
- server delete before upload works
- upload-to-image works
- recover/replace policy works
- cleanup warnings do not destroy final success

---

## 6. Migration notes

Remove or phase out:
- `deploy/local/*`
- jump host only assumptions
- old `control_*` files tied to remote host logic
- legacy path assumptions

Keep compatibility only if:
- it does not clutter the new model
- it does not reintroduce ambiguity
- it is clearly marked as temporary
