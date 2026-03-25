# image-build

Portable, menu-driven OpenStack image build pipeline for Linux cloud images.

## Overview
This project discovers upstream cloud images, prepares guests, and publishes final OpenStack images.

Primary phase chain:
1. `sync_download` - discover/download base image
2. `import_base` - import base image to Glance
3. `create_vm` - create boot volume + VM
4. `configure_guest` - configure guest via SSH
5. `clean_guest` - clean/generalize + poweroff
6. `publish_final` - upload final image + cleanup

## Quick Start
```bash
cp settings/openstack.env.template settings/openstack.env
cp settings/guest-access.env.template settings/guest-access.env

# source your OpenRC profile
source /path/to/openrc.sh

# interactive mode (recommended)
bash scripts/control.sh

# direct sync commands
bash scripts/control.sh sync dry-run --os ubuntu
bash scripts/control.sh sync download --os fedora --version 41
```

## Supported OS (sync path)
- ubuntu
- debian
- fedora
- rocky
- almalinux
- alpine
- arch

## Important Current Notes
- Interactive Build menu in `scripts/control.sh` runs phase scripts.
- Direct `scripts/control.sh build ...` dispatcher path is still marked NOT IMPLEMENTED.
- Configure repo flow is `official -> vault -> official-fallback -> failed`.
- `clean_guest.sh` restores official repo backup before shutdown/capture.

## Repository Structure
```text
scripts/control.sh          # single user-facing entrypoint

phases/
  sync_download.sh
  import_base.sh
  create_vm.sh
  configure_guest.sh
  clean_guest.sh
  publish_final.sh

lib/
  core_paths.sh
  common_utils.sh
  openstack_api.sh
  state_store.sh
  config_store.sh

config/
  os/<os>/sync.env
  guest/<os>/{default.env,<version>.env}

settings/
  *.template -> local *.env (gitignored)

runtime/
  state/<phase>/*.json + flags
  logs/<phase>/*.log

workspace/images/<os>/<version>/
```

## Documentation
Read in this order:
1. `rebuild-project-doc/00_INDEX.md`
2. `rebuild-project-doc/01_START_PROJECT_BLUEPRINT.md`
3. `rebuild-project-doc/02_DOWNLOAD_IMAGE_SYSTEM.md`
4. `rebuild-project-doc/03_GUEST_OS_CONFIG_SYSTEM.md`
5. `AIlogtest/00_INDEX.md`
