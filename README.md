# image-build

Portable, menu-driven OpenStack image build pipeline for Linux distributions.

---

## Overview

This pipeline discovers, downloads, and builds production-ready cloud images for OpenStack. It runs locally — no jump-host required.

**Phases:**
1. `sync_download` — Discover & download base image from official upstream
2. `import_base`   — Import local image into Glance
3. `create_vm`     — Create boot volume + VM from base image
4. `configure_guest` — SSH in and configure guest OS
5. `clean_guest`   — Final clean + poweroff
6. `publish_final` — Upload volume as final image, cleanup

---

## Quick Start

```bash
# 1. Copy and fill in settings (never commit these files)
cp settings/openstack.env.template settings/openstack.env
cp settings/guest-access.env.template settings/guest-access.env

# 2. Source your OpenStack credentials
source /path/to/openrc.sh

# 3. Launch interactive menu
bash scripts/control.sh

# — OR — run directly:
bash scripts/control.sh sync dry-run --os ubuntu
bash scripts/control.sh sync dry-run --os debian
bash scripts/control.sh sync download --os ubuntu --version 24.04
bash scripts/control.sh status dashboard
```

---

## OS Support

| OS         | Min Version | Sync | Import | Configure | Publish |
|------------|:-----------:|:----:|:------:|:---------:|:-------:|
| ubuntu     | 18.04       | ✓    | -      | -         | -       |
| debian     | 12          | ✓    | -      | -         | -       |
| fedora     | 41          | ✓    | -      | -         | -       |
| almalinux  | 8           | ✓    | -      | -         | -       |
| rocky      | 8           | ✓    | -      | -         | -       |

---

## Project Structure

```
scripts/control.sh          ← single user-facing entrypoint

lib/
├── core_paths.sh           ← canonical path variables (source of truth)
├── common_utils.sh         ← logging, retry, timeout, SSH helpers
├── openstack_api.sh        ← OpenStack CLI wrappers (skeleton)
├── config_store.sh         ← load/merge config files
└── state_store.sh          ← read/write flags and runtime JSON

phases/
├── sync_download.sh        ← REAL: discover/download base images
├── import_base.sh          ← skeleton
├── create_vm.sh            ← skeleton
├── configure_guest.sh      ← skeleton
├── clean_guest.sh          ← skeleton
└── publish_final.sh        ← skeleton

config/
├── defaults.env            ← project-wide tracked defaults
├── os/<os>/sync.env        ← per-OS discovery rules (tracked)
└── guest/<os>/             ← per-OS/version guest policy (tracked)

settings/
├── openstack.env.template  ← copy → openstack.env (gitignored)
└── guest-access.env.template ← copy → guest-access.env (gitignored)

workspace/images/<os>/<ver>/ ← downloaded images (gitignored)
runtime/state/<phase>/       ← flag files + JSON manifests (gitignored)
runtime/logs/<phase>/        ← timestamped log files (gitignored)
```

---

## Runtime Model

Every phase writes three output types:

| Type | Location | Purpose |
|------|----------|---------|
| JSON manifest | `runtime/state/<phase>/<os>-<ver>.json` | Full result data |
| Flag file | `runtime/state/<phase>/<os>-<ver>.<flag>` | Quick status check |
| Log file | `runtime/logs/<phase>/<os>-<ver>.log` | Timestamped trace |

Flag files: `.ready`, `.dryrun-ok`, `.failed`

---

## Design Principles

- **Local-first**: no jump-host, runs on any Linux/Bash environment
- **Single entrypoint**: `scripts/control.sh` only
- **Input = `.env`, Output = `.json`, State = flag files**
- **Dry-run first**: every long operation supports `--dry-run`
- **Fail clearly**: `.failed` flag + JSON with `failure_reason` on any error
- **Never hardcode URLs**: all image discovery is rule-driven via `config/os/*/sync.env`

---

## Documentation

Design docs are in `rebuild-project-doc/` (read-only reference):

| File | Topic |
|------|-------|
| 01_START_PROJECT_BLUEPRINT.md | Architecture overview, directory structure |
| 02_DOWNLOAD_IMAGE_SYSTEM.md   | sync_download design |
| 05_CONFIG_SCHEMA_REFERENCE.md | Config file schemas |
| 06_OPENSTACK_PIPELINE_DESIGN.md | Full pipeline design |
| 07_MENU_DESIGN.md             | Menu structure |
| 08_HELPER_LIBRARIES_DESIGN.md | lib/ function specs |
| 09_IMPLEMENTATION_ROADMAP.md  | Milestone ordering |
| 10_AI_IMPLEMENTATION_NOTES.md | AI coding guardrails |
