# Configuration Layout

This document describes the configuration structure of the `image-build` repository.

## Layers

The repository separates configuration into the following layers:

### 1. Control Config (`config/control/`)
Tracked templates and defaults for the local operator or jump-host control settings.
- `clean.env`: Configuration for the cleanup phase.
- `publish.env`: Configuration for the image publication phase.
- `source.env`: Configuration for source discovery.

### 2. Runtime Sync Config (`config/runtime/`)
Tracked templates for the OpenStack environment. Local overrides should be placed in `deploy/local/`.
- `openstack.env`: OpenStack resource templates and IDs.
- `openrc.path`: Path to the OpenStack credentials file.

### 3. OS Config (`config/os/`)
Per-OS discovery and download behavior.
- `ubuntu.env`, `debian.env`, `fedora.env`, etc.
- Contains `MIN_VERSION`, `MAX_VERSION`, `ALLOW_EOL`, and official source URLs.

### 4. Guest Policy Config (`config/guest/`)
VM policy settings, independent of the controller or runtime logic.
- `access.env`: Basic bootstrap access (root user, ssh port).
- `policy.env`: Detailed guest configuration policy (locales, timezone, upgrades, etc.).
- `config.env`: Additional guest-specific configuration.

## Local Overrides (`deploy/local/`)
This directory contains local-only, gitignored files that override the tracked defaults. These files are never committed.
- `control.env`: Controller-specific settings (e.g., jump-host connection details).
- `openstack.env`: Local OpenStack resource overrides.
- `openrc.path`: Local path to your `openrc` file.
- `guest-access.env`: Local guest credentials (e.g., `ROOT_PASSWORD`).
- `ssh_config`: SSH configuration for the jump host.
- `ssh/`: SSH keys.

## Effective Config Loading Flow
1. **Local Operator** starts `scripts/control.sh`.
2. **Load Control Config**: Sources `deploy/local/control.env` and tracked defaults.
3. **Connect/Sync to Jump Host**: Uses SSH settings to sync the repository.
4. **Sync Runtime Config**: Generates overlay files from `deploy/local/*.env` and syncs them to the jump host's `deploy/local/` directory.
5. **Phase Execution**: Remote phases source the synced files in `deploy/local/` followed by the tracked defaults in `config/`.

## Summary Table

| Type | Directory | Sync to Jump Host? | Tracked in Git? |
| :--- | :--- | :--- | :--- |
| **Control** | `config/control/` | No | Yes |
| **Runtime** | `config/runtime/` | No | Yes |
| **OS** | `config/os/` | Yes | Yes |
| **Guest** | `config/guest/` | Yes | Yes |
| **Local Overrides** | `deploy/local/` | Selected files | No |
| **Outputs/State** | `manifests/`, `runtime/`, `logs/` | Yes | Selected files |
