# Sync Download — Test Run Summary

Date: 2026-03-21T19:01:30Z
Branch: main

---

## Files Created (new architecture)

```
scripts/control.sh                  ← single entrypoint (real, with arg dispatch + interactive menu)
lib/core_paths.sh                   ← rewritten (canonical path exports)
lib/common_utils.sh                 ← new (logging, retry, timeout, SSH, JSON helpers)
lib/openstack_api.sh                ← new (skeleton stubs)
lib/config_store.sh                 ← new (skeleton)
lib/state_store.sh                  ← new (skeleton)
phases/sync_download.sh             ← new (REAL implementation)
phases/import_base.sh               ← new (skeleton)
phases/create_vm.sh                 ← new (skeleton)
phases/configure_guest.sh           ← new (skeleton)
phases/clean_guest.sh               ← new (skeleton)
phases/publish_final.sh             ← new (skeleton)
config/defaults.env                 ← new
config/os/ubuntu/sync.env           ← new (real)
config/os/debian/sync.env           ← new (real)
config/os/fedora/sync.env           ← new (real)
config/os/almalinux/sync.env        ← new (real)
config/os/rocky/sync.env            ← new (real)
config/guest/ubuntu/default.env     ← new (skeleton)
config/guest/ubuntu/22.04.env       ← new (skeleton)
config/guest/ubuntu/24.04.env       ← new (skeleton)
config/guest/debian/default.env     ← new (skeleton)
config/guest/debian/12.env          ← new (skeleton)
config/guest/rocky/default.env      ← new (skeleton)
config/guest/rocky/9.env            ← new (skeleton)
config/guest/almalinux/default.env  ← new (skeleton)
config/guest/almalinux/9.env        ← new (skeleton)
config/guest/fedora/default.env     ← new (skeleton)
config/guest/fedora/40.env          ← new (skeleton)
settings/openstack.env.template     ← new (real template)
settings/guest-access.env.template  ← new (real template)
.gitignore                          ← updated
README.md                           ← updated
```

---

## Test Results

| Test                        | Result | Notes |
|-----------------------------|--------|-------|
| control.sh --help           | PASS   | Displays full help with all commands |
| sync dry-run ubuntu         | PASS   | 4 versions (18.04/20.04/22.04/24.04), all discovered |
| sync dry-run debian         | PASS   | v12 bookworm, generic-amd64.qcow2 selected |
| sync dry-run fedora         | PASS   | v41 from archives.fedoraproject.org, BSD checksum parsed |
| sync dry-run almalinux      | PASS   | v8+v9, GenericCloud-latest selected |
| sync dry-run rocky          | PASS   | v8+v9, GenericCloud.latest selected |
| state files written         | PASS   | 10 .json + 10 .dryrun-ok flags in runtime/state/sync/ |
| shellcheck                  | N/A    | shellcheck not installed in this environment |

---

## Discovered Images (from dry-run manifests)

| OS        | Version | Filename                                              | Hash (algo) | Format |
|-----------|---------|-------------------------------------------------------|-------------|--------|
| ubuntu    | 18.04   | ubuntu-18.04-server-cloudimg-amd64.img                | sha256: 8dd2e6b5... | img |
| ubuntu    | 20.04   | ubuntu-20.04-server-cloudimg-amd64.img                | sha256: 18f2977d... | img |
| ubuntu    | 22.04   | ubuntu-22.04-server-cloudimg-amd64.img                | sha256: ea85b16f... | img |
| ubuntu    | 24.04   | ubuntu-24.04-server-cloudimg-amd64.img                | sha256: 7aa6d9f5... | img |
| debian    | 12      | debian-12-generic-amd64.qcow2                         | sha512: 8a2b235b... | qcow2 |
| fedora    | 41      | Fedora-Cloud-Base-Generic-41-1.4.x86_64.qcow2         | sha256: 6205ae0c... | qcow2 |
| almalinux | 8       | AlmaLinux-8-GenericCloud-latest.x86_64.qcow2          | sha256: 669bd580... | qcow2 |
| almalinux | 9       | AlmaLinux-9-GenericCloud-latest.x86_64.qcow2          | sha256: 5ff9c048... | qcow2 |
| rocky     | 8       | Rocky-8-GenericCloud.latest.x86_64.qcow2              | sha256: e56066c5... | qcow2 |
| rocky     | 9       | Rocky-9-GenericCloud.latest.x86_64.qcow2              | sha256: 15d81d34... | qcow2 |

All discovered via upstream checksum files — no hardcoded URLs.

---

## Errors / Warnings

Initial runs required 2 config fixes before all tests passed:

1. **debian sync.env** — IMAGE_REGEX had wrong date-stamp pattern.
   - Was: `^debian-[0-9]+-generic-amd64-[0-9]+-[0-9]+\.(qcow2|raw)$`
   - Fixed: `^debian-[0-9]+-generic-amd64\.(qcow2|raw)$`
   - Reason: Debian does not include build date in the main filename at latest/.

2. **fedora sync.env** — INDEX_URL_TEMPLATE pointed to wrong mirror.
   - Was: `https://dl.fedoraproject.org/pub/fedora/linux/releases/{VERSION}/Cloud/x86_64/images`
   - Fixed: `https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/{VERSION}/Cloud/x86_64/images`
   - Also fixed IMAGE_REGEX to match `Fedora-Cloud-Base-Generic-{VERSION}-X.Y.x86_64.qcow2` format.

---

## Skeleton Phases (not yet implemented)

- phases/import_base.sh
- phases/create_vm.sh
- phases/configure_guest.sh
- phases/clean_guest.sh
- phases/publish_final.sh

All contain proper shebang, set -Eeuo pipefail, source core libraries, and stub functions
with `util_log_info "NOT IMPLEMENTED: ..."` placeholders.

---

## Log Files

See AIlogtest/logs/ for full timestamped logs per OS/version:
- ubuntu-18.04.log, ubuntu-20.04.log, ubuntu-22.04.log, ubuntu-24.04.log
- debian-12.log
- fedora-41.log
- almalinux-8.log, almalinux-9.log
- rocky-8.log, rocky-9.log
