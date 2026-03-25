# Image Build Documentation Index (Current State)

Last updated: 2026-03-25
Scope: local workspace implementation (`scripts/`, `phases/`, `config/`, `lib/`)

## Read First
1. [01_START_PROJECT_BLUEPRINT.md](./01_START_PROJECT_BLUEPRINT.md)
2. [02_DOWNLOAD_IMAGE_SYSTEM.md](./02_DOWNLOAD_IMAGE_SYSTEM.md)
3. [03_GUEST_OS_CONFIG_SYSTEM.md](./03_GUEST_OS_CONFIG_SYSTEM.md)
4. [06_OPENSTACK_PIPELINE_DESIGN.md](./06_OPENSTACK_PIPELINE_DESIGN.md)

## Current Reality Summary
- Local-first workflow. No jump-host dependency for normal operation.
- Sync supports: `ubuntu`, `debian`, `fedora`, `rocky`, `almalinux`, `alpine`, `arch`.
- `configure_guest.sh` repo flow is: `official -> vault -> official-fallback -> failed`.
- `clean_guest.sh` restores official repo backup before capture/shutdown.
- Build phases are implemented as scripts (`import_base`, `create_vm`, `configure_guest`, `clean_guest`, `publish_final`).
- `scripts/control.sh` interactive Build menu runs phases; direct CLI `build` subcommand is still marked NOT IMPLEMENTED.

## File Map
- [01_START_PROJECT_BLUEPRINT.md](./01_START_PROJECT_BLUEPRINT.md): architecture and module map
- [02_DOWNLOAD_IMAGE_SYSTEM.md](./02_DOWNLOAD_IMAGE_SYSTEM.md): sync/discovery/download logic
- [03_GUEST_OS_CONFIG_SYSTEM.md](./03_GUEST_OS_CONFIG_SYSTEM.md): guest configure + clean model
- [04_ENV_AND_RUNTIME_MODEL.md](./04_ENV_AND_RUNTIME_MODEL.md): env inputs and runtime outputs
- [05_CONFIG_SCHEMA_REFERENCE.md](./05_CONFIG_SCHEMA_REFERENCE.md): config key reference (current keys)
- [06_OPENSTACK_PIPELINE_DESIGN.md](./06_OPENSTACK_PIPELINE_DESIGN.md): end-to-end phase design/status
- [07_MENU_DESIGN.md](./07_MENU_DESIGN.md): current menu and command behavior
- [08_HELPER_LIBRARIES_DESIGN.md](./08_HELPER_LIBRARIES_DESIGN.md): helper library responsibilities
- [09_IMPLEMENTATION_ROADMAP.md](./09_IMPLEMENTATION_ROADMAP.md): forward roadmap from current state
- [10_AI_IMPLEMENTATION_NOTES.md](./10_AI_IMPLEMENTATION_NOTES.md): maintenance rules for future AI sessions

## Terminology Policy
- Use `LEGACY_MIRROR` only when describing historical logs/older files.
- For current active configure flow, use `vault fallback` and `official-fallback` terminology.
- Treat old `OLS` wording as historical only.
