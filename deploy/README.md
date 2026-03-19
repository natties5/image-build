# Jump-Host Local Configuration

Tracked templates live in `deploy/`.
Local secrets and host-specific values must live in `deploy/local/` (gitignored).

## Setup

1. Copy `deploy/control.env.example` to `deploy/local/control.env`.
2. Copy `deploy/ssh_config.example` to `deploy/local/ssh_config`.
3. Place your private key at `deploy/local/ssh/id_jump` (`chmod 600` on Linux).
4. Run `scripts/control.sh status` to verify jump-host connectivity.

Optional:

- Set `JUMP_HOST_REPO_URL` in `deploy/local/control.env`.
- If empty, controller defaults to local `origin` URL.
- Set `EXPECTED_PROJECT_NAME` in `deploy/local/control.env` (or `deploy/local/openstack.env`) so preflight can validate project context automatically.
