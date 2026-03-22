# Download Test Summary — Latest Version Per OS
Date: 2026-03-22T01:18:55Z
Branch: fix/fresh-clone-and-paths
Commit: 9238213

## Test Matrix
| OS        | Version | Filename                                        | Size    | Hash OK | Status |
|-----------|---------|--------------------------------------------------|---------|---------|--------|
| ubuntu    | 24.04   | ubuntu-24.04-server-cloudimg-amd64.img           | 600 MB  | YES     | PASS   |
| debian    | 12      | debian-12-generic-amd64.qcow2                    | 425 MB  | YES     | PASS   |
| fedora    | 41      | Fedora-Cloud-Base-Generic-41-1.4.x86_64.qcow2    | 469 MB  | YES     | PASS   |
| almalinux | 9       | AlmaLinux-9-GenericCloud-latest.x86_64.qcow2     | 563 MB  | YES     | PASS   |
| rocky     | 9       | Rocky-9-GenericCloud.latest.x86_64.qcow2         | 619 MB  | YES     | PASS   |

All 5 downloads completed with hash verification passed. No failures.

## State Files Written
```
runtime/state/sync/almalinux-8.dryrun-ok
runtime/state/sync/almalinux-8.json
runtime/state/sync/almalinux-9.json
runtime/state/sync/almalinux-9.ready
runtime/state/sync/debian-12.json
runtime/state/sync/debian-12.ready
runtime/state/sync/fedora-41.json
runtime/state/sync/fedora-41.ready
runtime/state/sync/rocky-8.dryrun-ok
runtime/state/sync/rocky-8.json
runtime/state/sync/rocky-9.json
runtime/state/sync/rocky-9.ready
runtime/state/sync/ubuntu-18.04.dryrun-ok
runtime/state/sync/ubuntu-18.04.json
runtime/state/sync/ubuntu-20.04.dryrun-ok
runtime/state/sync/ubuntu-20.04.json
runtime/state/sync/ubuntu-22.04.dryrun-ok
runtime/state/sync/ubuntu-22.04.json
runtime/state/sync/ubuntu-24.04.json
runtime/state/sync/ubuntu-24.04.ready
runtime/state/sync/ubuntu-24.4.failed
runtime/state/sync/ubuntu-24.4.json
```

Note: `ubuntu-24.4.failed` / `ubuntu-24.4.json` are leftover from a stale failed test with typo version "24.4" (not "24.04"). Not from this run.

## Errors Detail

### ubuntu
PASS - no errors
Hash: sha256 7aa6d9f5e8a3a55c7445b138d31a73d1187871211b2b7da9da2e1a6cbf169b21

### debian
PASS - no errors
Hash: sha512 8a2b235b5a08db8475997301c294d0466d738b945c3f1e4abf625f0b005b081a71fe72625c586ba52d4d8b5a29ee514864bf47ffec1288921c71b5311beaa1fb

### fedora
PASS - no errors
Hash: sha256 6205ae0c524b4d1816dbd3573ce29b5c44ed26c9fbc874fbe48c41c89dd0bac2

### almalinux
PASS - no errors
Hash: sha256 5ff9c048859046f41db4a33b1f1a96675711288078aac66b47d0be023af270d1

### rocky
PASS - no errors
Hash: sha256 15d81d3434b298142b2fdd8fb54aef2662684db5c082cc191c3c79762ed6360c

## Fixes Applied (from previous /AIlogtest failures)
No fixes required. All previous dry-run failures were resolved in the prior session:
1. `config/os/debian/sync.env` — IMAGE_REGEX fixed (no build date in filename)
2. `config/os/fedora/sync.env` — INDEX_URL_TEMPLATE changed to archives.fedoraproject.org + IMAGE_REGEX updated

This download run ran cleanly against already-fixed config files.

## Workspace Disk Usage
```
563M    workspace/images/almalinux/
425M    workspace/images/debian/
469M    workspace/images/fedora/
619M    workspace/images/rocky/
600M    workspace/images/ubuntu/
```
Total: ~2.7 GB

## Next Step
Phase 2 ready: import_base.sh — waiting for implementation milestone 4
