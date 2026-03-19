# Jump-Host Local Configuration

Tracked templates live in `deploy/`.
Local secrets and host-specific values must live in `deploy/local/` (gitignored).

## Setup

1. Copy `deploy/control.env.example` to `deploy/local/control.env`.
2. Copy `deploy/ssh_config.example` to `deploy/local/ssh/config`.
3. Place your private key at `deploy/local/ssh/id_jump` (`chmod 600` on Linux).
4. Run `scripts/control.sh status` to verify jump-host connectivity.
