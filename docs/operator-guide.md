# Operator Guide

## Main Controller

Run:

```bash
bash scripts/control.sh
```

Top-level sections:

1. SSH
2. Git
3. Pipeline
4. Exit

## SSH Menu

- `connect`: open normal SSH session to jump host; logout returns to menu.
- `validate`: run non-interactive jump-host connectivity check.
- `info`: show resolved target/repo config (safe fields only).

Direct commands:

```bash
bash scripts/control.sh ssh connect
bash scripts/control.sh ssh validate
bash scripts/control.sh ssh info
```

## Git Menu

- `bootstrap-remote-repo`
- `sync-safe`
- `sync-code-overwrite`
- `sync-clean`
- `status`
- `branch-info`
- `push`

Bootstrap behavior:

- Missing remote path: create parent directory and clone repo.
- Existing empty directory: clone into existing path.
- Existing git repo: fetch/checkout/pull configured branch.
- Existing non-repo non-empty path: fail safely (no destructive cleanup).

Direct commands:

```bash
bash scripts/control.sh git bootstrap
bash scripts/control.sh git sync-safe
bash scripts/control.sh git sync-code-overwrite --yes
bash scripts/control.sh git sync-clean --yes
bash scripts/control.sh git status
bash scripts/control.sh git branch
```

## Pipeline Menu

- `Manual`
- `Auto by OS`
- `Auto by OS Version`
- `Status`
- `Logs`
- `Back`

Pipeline execution always uses dependency-aware order:

1. Select OS
2. Ensure remote repo exists
3. Run `download/discover`
4. Load discovered versions from manifest/summary
5. Continue with selected mode

Version choices are manifest-driven. If no manifest versions are found, run discover first.

Before mutating phases, controller validates required local runtime config and syncs required runtime env files to jump host.

### Manual Mode

Flow:

1. Select OS
2. Controller runs discover first
3. Select one discovered version
4. Select action
5. Action runs and returns to same menu

Actions:

- `preflight`
- `import`
- `create`
- `configure`
- `clean`
- `publish`
- `status`
- `logs`
- `change-version`
- `change-os`
- `back`

### Auto by OS

Flow:

1. Select OS
2. Controller runs discover first
3. Validate required local runtime config (including `ROOT_PASSWORD`)
4. Sync required runtime config to jump host repo (`deploy/local/`)
5. Validate synced runtime config exists remotely
6. Load all discovered versions
7. Run full pipeline (`preflight -> import -> create -> configure -> clean -> publish`) for each version
8. Show per-version summary

### Auto by OS Version

Flow:

1. Select OS
2. Controller runs discover first
3. Validate required local runtime config (including `ROOT_PASSWORD`)
4. Sync required runtime config to jump host repo (`deploy/local/`)
5. Validate synced runtime config exists remotely
6. Load discovered versions
7. Select one discovered version
8. Run full pipeline for that version
9. Show summary

Direct commands:

```bash
bash scripts/control.sh pipeline manual
bash scripts/control.sh pipeline auto-by-os --os ubuntu
bash scripts/control.sh pipeline auto-by-os-version --os ubuntu --version 24.04
```

Compatibility aliases:

```bash
bash scripts/control.sh script manual
bash scripts/control.sh script auto --os ubuntu --version 24.04
bash scripts/control.sh auto --os ubuntu --version 24.04
```

## EXPECTED_PROJECT_NAME for Preflight

Set `EXPECTED_PROJECT_NAME` in one of:

- `deploy/local/control.env`
- `deploy/local/openstack.env`
- shell environment before running the command

Controller-based preflight runs pass this value automatically.

## Remote Runtime Config Sync

Controller syncs only required runtime env files (if present):

- `deploy/local/guest-access.env`
- `deploy/local/openstack.env`
- `deploy/local/openrc.path`
- `deploy/local/publish.env`
- `deploy/local/clean.env`

Synced destination on jump host:

- `<JUMP_HOST_REPO_PATH>/deploy/local/`

Never synced:

- `deploy/local/ssh_config`
- `deploy/local/ssh/*` private keys

## Local-Only Jump-Host Files

Store local-only files under `deploy/local/` (gitignored):

- `deploy/local/control.env`
- `deploy/local/ssh_config`
- `deploy/local/ssh/*` (private keys)
- optional overrides under `deploy/local/*.env`

Do not put real secrets in tracked files.
