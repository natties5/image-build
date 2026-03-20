# Architecture Overview

The `image-build` repository is an automated pipeline for building and publishing OpenStack images for various Linux distributions.

## Pipeline Lifecycle

The pipeline follows a series of distinct phases:

1. **Discover**: Identify available official cloud images from distribution mirrors.
2. **Download**: Pull images to the jump-host cache.
3. **Build (Import)**: Upload base images to OpenStack Glance.
4. **Configure (Build VM)**: Create a temporary VM from the base image and apply configuration.
5. **Validate**: Perform tests to ensure the image meets quality standards.
6. **Publish**: Snapshot the configured VM and save the final image to Glance.
7. **Reuse (Cleanup)**: Remove temporary resources used during the build process.

## Component Layers

The repository is structured into the following layers:

### 1. Control Layer (`scripts/control.sh`)
The entry point for the operator. It runs on the local machine and handles:
- SSH connection to the jump host.
- Git synchronization of the repository.
- Orchestration of pipeline phases.
- Runtime configuration sync.

### 2. Phase Layer (`phases/`)
Individual shell scripts that implement specific pipeline steps. These scripts are executed on the jump host.
- They are designed to be idempotent where possible.
- They read from normalized inputs provided by helper libraries.

### 3. Library Layer (`lib/`)
Reusable bash helpers and logic:
- `control_*.sh`: Helpers for the local controller (main, ssh, sync, etc.).
- `os_helpers.sh`: Helpers for handling multiple operating systems and manifests.
- `runtime_helpers.sh`: Helpers for configuration loading and remote sync.

### 4. Configuration Layer (`config/`)
Tracked configuration for different aspects of the pipeline.
- See `doc/config-layout.md` for details.

### 5. Manifest and Output Layer
Machine-readable files and execution state.
- `manifests/`: Discovered versions and build metadata.
- `runtime/state/`: Live execution state of the pipeline.
- `logs/`: Detailed execution logs.

## Jump Host Driven Model

The system uses a **jump host** as the primary execution environment for OpenStack interactions. The local controller syncs code and configuration to the jump host via SSH and then triggers the remote phases. This model ensures that credentials and heavy network operations (like large image downloads) stay within a controlled environment.
