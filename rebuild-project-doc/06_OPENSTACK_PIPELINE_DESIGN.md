# 06 - OpenStack Pipeline Design (Implemented State)

Last updated: 2026-03-25

## 1) End-to-End Flow
1. sync/download base image locally
2. import base image to Glance
3. create boot volume + VM
4. configure guest over SSH
5. clean guest and power off
6. publish final image from volume

## 2) Phase Scripts (Actual)
- `phases/sync_download.sh`
- `phases/import_base.sh`
- `phases/create_vm.sh`
- `phases/configure_guest.sh`
- `phases/clean_guest.sh`
- `phases/publish_final.sh`

## 3) Control Entrypoints
- Interactive menu in `scripts/control.sh` is primary UX.
- `sync` command dispatcher supports dry-run/download subcommands.
- `build` command dispatcher path currently reports NOT IMPLEMENTED, while menu build path executes phase scripts.

## 4) Key Runtime Guarantees
- State/flag/log model per phase under `runtime/`
- Re-entrant behavior for common already-exists cases in import/create/publish
- Explicit wait loops for OpenStack resource states and guest reboot/SSH

## 5) Repo Strategy in Configure/Clean
Configure:
- baseline official check
- vault fallback attempt when official degrades
- official-fallback as last resort

Clean:
- restore official repo from backup before capture/shutdown

## 6) Current Gaps / Risks
- Direct `build` CLI dispatcher inconsistency with menu behavior
- Legacy phase scripts (`*_one.sh`/older files) still exist; active path is `*_base.sh`, `create_vm.sh`, `configure_guest.sh`, `clean_guest.sh`, `publish_final.sh`
- Some docs/logs still carry old terminology from prior architecture

## 7) Operational Rule
When behavior is unclear, treat phase script code + current config as source of truth over historical narrative docs.
