# Operator Guide

## Main Controller

Run:

```bash
bash scripts/control.sh
```

Top-level sections:

1. SSH
2. Git
3. Script
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

## Script Menu

- `manual`
- `auto`
- `status`
- `logs`
- `back`

Script actions automatically require remote repo readiness; if missing, controller offers bootstrap.

### Manual Mode

Flow:

1. Select OS
2. Select version
3. Select phase/action
4. Action runs
5. Return to same menu

Actions:

- `preflight`
- `download`
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

### Auto Mode

Run:

```bash
bash scripts/control.sh script auto --os ubuntu --version 24.04
```

Scaffold flags:

- `--resume-from <phase>`
- `--stop-before <phase>`
- `--fail-fast yes|no`
- `--cleanup-mode <value>`

## Local-Only Jump-Host Files

Store local-only files under `deploy/local/` (gitignored):

- `deploy/local/control.env`
- `deploy/local/ssh_config`
- `deploy/local/ssh/*` (private keys)
- optional overrides under `deploy/local/*.env`

Do not put real secrets in tracked files.
