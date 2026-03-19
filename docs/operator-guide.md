# Operator Guide

## Manual Mode

Run:

```bash
bash scripts/control.sh manual
```

Flow:

1. Select OS.
2. Select version.
3. Choose action from menu.
4. Action runs on jump host.
5. Control returns to menu.

Menu actions:

- `sync-safe`
- `sync-code-overwrite`
- `sync-clean`
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
- `exit`

## Auto Mode

Run a full Ubuntu pipeline for one version:

```bash
bash scripts/control.sh auto --os ubuntu --version 24.04
```

Scaffolded options:

- `--resume-from <phase>`
- `--stop-before <phase>`
- `--fail-fast yes|no`
- `--cleanup-mode <value>`

## Jump-Host Config Validation

Validate connectivity:

```bash
bash scripts/control.sh status
```

If this succeeds, jump-host settings are loaded and SSH execution is available.
