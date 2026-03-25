# 08 - Helper Libraries Design (Current)

Last updated: 2026-03-25

## 1) `lib/common_utils.sh`
Responsibilities:
- logging (`util_log_*`)
- retries/polling/timeouts
- dependency/path helpers
- SSH/SCP wrappers
- sync UI helpers (`_sync_*`)
- auto-discovery helpers (upstream version discovery/update)

Notable current support:
- OS list includes alpine and arch
- Fedora discovery checks release path with archive fallback

## 2) `lib/openstack_api.sh`
Responsibilities:
- OpenStack CLI wrappers for image/volume/server operations
- wait functions for state transitions
- lookup helpers for resources and IDs

## 3) `lib/state_store.sh`
Responsibilities:
- state ready/failed markers
- runtime json field reads/writes

## 4) Design Rule
Keep business logic in phase scripts; helper libs should stay reusable and phase-agnostic.
