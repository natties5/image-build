# Jump Host Configuration

The `image-build` system relies on a jump host for executing OpenStack commands and downloading images.

## Requirements

1. **Operating System**: Typically Ubuntu or CentOS.
2. **Access**: SSH access with key-based authentication.
3. **OpenStack CLI**: `openstack` client must be installed and configured.
4. **Git**: Used for repository synchronization.
5. **Disk Space**: Sufficient space for the image cache (e.g., in `/root/image-build/cache`).

## Initial Setup

1. **Bootstrap SSH Access**:
   - Ensure the jump host's SSH public key is added to the relevant OpenStack project's security rules if needed.
   - Configure `deploy/local/ssh_config` on your local machine to point to the jump host.
   - Place your SSH private keys in `deploy/local/ssh/`.

2. **Bootstrap the Remote Repository**:
   - Run `scripts/control.sh git bootstrap` to clone the repository onto the jump host.
   - This will use the settings from `deploy/local/control.env`.

3. **Configure OpenStack Credentials**:
   - Upload your `openrc` file to the jump host.
   - Update `deploy/local/openrc.path` on your local machine to point to the remote path of your `openrc` file.

## Connection Details (`deploy/local/control.env`)

This local-only file defines how to connect to the jump host:

```bash
# JUMP_HOST: The SSH target string (e.g., user@hostname)
JUMP_HOST="root@10.254.20.100"

# JUMP_HOST_REPO_PATH: Where the repo is located on the jump host
JUMP_HOST_REPO_PATH="/root/image-build"

# SSH_CONFIG_PATH: Path to the SSH config file to use
SSH_CONFIG_PATH="deploy/local/ssh_config"
```

## Security Considerations

- **SSH Keys**: Never commit your private keys. Keep them in `deploy/local/ssh/`.
- **OpenStack Credentials**: Never commit your `openrc` file. Reference its path on the jump host in `deploy/local/openrc.path`.
- **Local Overrides**: The `deploy/local/` directory is gitignored to protect your environment-specific settings and secrets.
