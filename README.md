# Image Build Control Panel

This repository is a VS Code-friendly, jump-host-driven image build framework.

## Primary Entrypoint

Use `scripts/control.sh` for operator workflows:

- `bash scripts/control.sh` (interactive main menu: SSH / Git / Script / Exit)
- `bash scripts/control.sh ssh validate`
- `bash scripts/control.sh git bootstrap`
- `bash scripts/control.sh script manual`
- `bash scripts/control.sh script auto --os ubuntu --version 24.04`

Legacy wrappers under `scripts/01..11_*.sh` and `bin/imagectl.sh` remain supported.

## Jump Host Configuration (Local Only)

1. Copy `deploy/control.env.example` to `deploy/local/control.env`.
2. Copy `deploy/ssh_config.example` to `deploy/local/ssh_config`.
3. Add private key at `deploy/local/ssh/id_jump`.
4. Optional local overrides:
   - `deploy/local/openstack.env`
   - `deploy/local/openrc.path`
   - `deploy/local/guest-access.env`
   - `deploy/local/publish.env`
   - `deploy/local/clean.env`

`deploy/local/**` is gitignored by default.

## SSH / Git / Script Sections

- SSH:
  - `connect` opens a real SSH session to jump host.
  - `validate` checks non-interactive connectivity.
  - `info` prints resolved target and repo settings (no secrets).
- Git:
  - `bootstrap` prepares remote repo safely if missing/empty.
  - `sync-safe`, `sync-code-overwrite`, `sync-clean`.
  - `status`, `branch`, optional `push`.
- Script:
  - `manual`, `auto`, `status`, `logs`.
  - Script execution checks remote repo readiness and guides bootstrap.

## Sync Modes

- `safe`: fetch + checkout + pull (non-destructive)
- `code-overwrite`: align tracked code with remote branch
- `clean`: overwrite code + clean runtime/work artifacts

Destructive sync modes require confirmation or `--yes`.

## OS Support

- Implemented: Ubuntu
- Skeleton only: Debian, CentOS, AlmaLinux, Rocky

Non-Ubuntu flows return a clear not-implemented message.
