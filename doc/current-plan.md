# Sync Image Plan (Phase 0–6) - Enhanced with Dynamic Discovery

## Overview

This document describes the image synchronization system with a new **central CLI menu** (`image`) that provides a unified interface for managing OS images across subsystems.

### Domain-Based Architecture (Strict)

The repository has been refactored into a strict domain-based structure. The repository root is kept clean, and all image-related code, config, and runtime data lives under `/image`:

```
image-build/
├── center/              # Central menu and routing only
│
├── image/               # Image domain owns everything image-related
│   ├── menu.py         # Image domain menu
│   ├── backend/        # Image backend (sync_image.py)
│   ├── services/       # Business logic services
│   ├── adapters/       # External adapters
│   ├── config/         # Image config (moved from root)
│   │   ├── sync-config.json
│   │   └── os/
│   ├── runtime/        # Image runtime data (moved from root)
│   │   ├── state/
│   │   ├── cache/
│   │   ├── logs/
│   │   └── reports/
│   └── tests/          # Image tests
│
├── openstack/          # Placeholder for future OpenStack work
├── guest_config/       # Placeholder for future guest config work
│
├── docs/               # Documentation
├── doc/                # Documentation (synced)
├── image_cli.py        # Main entry point
└── .gitignore
```

**Key Changes:**
- Root is kept clean - no image-owned runtime folders at repo root
- All image config moved from `config/` to `image/config/`
- All image runtime data moved from root to `image/runtime/`
- Backend moved from `tools/sync/` to `image/backend/`
- `tools/sync/sync_image.py` is now a compatibility shim

### Central Image Menu

The central menu is now located at `center/menu.py` and provides:

- **image sync** - Check targets, resolve sources, create/update plans (dry-run)
- **image pull** - Download images from existing plans only
- **image status** - Show current status table of all OS/versions
- **image setting** - Configure per-OS behavior interactively
- **image clean** - Remove plans, cache, and downloaded images

The menu acts as a neutral front-end that connects to the current sync subsystem while remaining extensible for future features.

### Menu Flow

```
config → sync → pull → status → clean
```

1. **sync** checks all targets, resolves upstream sources, and creates plans (no download)
2. **pull** downloads images only from existing plans (plan-driven execution)
3. **status** shows the current state of all OS/versions
4. **setting** configures per-OS policies interactively
5. **clean** removes plans, cache, and downloaded images for selected targets

### Key Design Principles

- **Domain-based**: Clean separation into `center/`, `image/`, `openstack/`, `guest_config/` domains
- **Central menu**: Entry point at `image_cli.py` → `center/menu.py` routes to domains
- **Service layer**: Image domain uses service layer (`image/services/`) for business logic
- **Adapter pattern**: `image/adapters/sync_backend.py` bridges to existing backend
- **Plan-driven**: `pull` only works from existing plans created by `sync`
- **Interactive UX**: Users select targets interactively; system reads config as source of truth
- **Safe defaults**: No destructive operations without confirmation; Enter keeps current values
- **Backward compatible**: Existing sync backend (`tools/sync/sync_image.py`) is preserved
- **Dynamic Discovery**: `sync` automatically detects new versions from upstream sources

## Dynamic Upstream Discovery

The system now supports **dynamic upstream version discovery** from official sources:

### Discovery Pipeline
```
official source
-> version discovery (HTML directory listing)
-> normalization
-> policy filter (min_version, max_version, enabled)
-> candidate selection
-> evidence logging
-> plan update
```

### Supported Discovery Methods

All major OS families now support automatic version discovery:

- **Ubuntu**: Discovers from cloud-images.ubuntu.com
- **Debian**: Discovers from cloud.debian.org/images/cloud/
- **Rocky Linux**: Discovers from download.rockylinux.org/pub/rocky/
- **AlmaLinux**: Discovers from repo.almalinux.org/almalinux/
- **Fedora**: Discovers from dl.fedoraproject.org/pub/fedora/linux/releases/

### Policy-Driven Filtering

Discovery respects all policy settings:
- `enabled`: Skip disabled OS families
- `min_version`: Required minimum version
- `max_version`: Optional maximum version
- `selection_policy`: "explicit" or "latest"
- `release_channel`: Filter by release type

### Discovery Evidence

Every discovery operation produces detailed evidence:
```json
{
  "upstream_discovery": {
    "discovery_source": "https://cloud.debian.org/images/cloud/",
    "discovery_method": "html_directory_listing",
    "discovery_log": [...],
    "raw_candidates_found": 2
  },
  "policy_filter": {
    "candidates_before_filter": 2,
    "candidates_after_filter": 2,
    "filter_log": [...]
  },
  "version_selection": {
    "selected_version": "13",
    "selection_reason": "latest valid version >= 12",
    "selection_log": [...]
  }
}
```

## Scope

This system focuses on phase 0–6 of image sync:

- Phase 0: input intake and normalization
- Phase 1: policy loading and source mapping
- Phase 2: source discovery from official listing
- Phase 3: version guard and checksum planning
- Phase 4: dry-run plan and state persistence
- Phase 5: cache decision
- Phase 6: controlled download from plan.json

Not included: build, guest access, OpenStack upload, and post-upload validation

---

## Goal

The goal of this baseline is to make sync image the most stable upstream phase, because if this phase fails, the entire system will fail downstream.

Objectives:
- Resolve input to canonical form
- Map OS/version to official source clearly
- Fetch official listings dynamically
- Select candidates with strict policy compliance
- Parse checksums accurately
- Create dry-run plan.json that can be executed
- Execute strictly from plan.json only
- Cache must be bound to source/version/arch/checksum
- Download shows progress MB/s and ETA
- Automatic cleanup of partial files on fail/cancel

---

## Core Rules

- No download before dry-run plan exists
- No execution by re-resolving sources independently
- No versions allowed that fail canonical + policy + min_version guard
- No cache reuse across source/version/arch/checksum without identity guard
- Hosts must be in allowlist

---

## Configuration Structure

Config is split into two levels:

### Global Config (`config/sync-config.json`)
Stores global/shared settings:
- version
- state_root, cache_root, log_root, report_root
- request_timeout_seconds
- allowed_hosts
- user_agent

### Per-OS Config (`config/os/*.json`)
Separate files for each OS:
- ubuntu.json - Ubuntu LTS releases
- debian.json - Debian releases
- rocky.json - Rocky Linux releases
- almalinux.json - AlmaLinux releases
- fedora.json - Fedora releases (disabled by default)

Each file contains:
- os: OS name
- enabled: Whether this OS is enabled
- min_version: minimum supported version (required)
- max_version: maximum supported version (optional, can be null)
- selection_policy: version selection policy ("explicit" or "latest")
- release_channel: release channel (e.g., "stable", "lts", "rolling")
- aliases: version aliases
- architectures: arch mappings
- sources: version-specific listing/checksum settings
- discovery: upstream discovery configuration

### Version Selection Policies

**explicit**: User must specify exact version (e.g., "debian 12", "ubuntu 22.04")

**latest**: Supports automatic version discovery
- Use `auto` or `latest` as version selector
- System discovers available versions from upstream
- Filters by min_version and max_version (if set)
- Selects the latest valid version
- Supported for: Debian (Fedora when enabled)

---

## Artifact Format Selection

The system now implements **artifact preference** logic:

### Preference Order (highest first)
1. **qcow2** (score: 100) - Preferred cloud image format
2. **raw/img** (score: 80) - Raw disk images
3. **vmdk/vdi** (score: 60) - VM-specific formats
4. **iso** (score: 50) - Installer media
5. **tar** (score: 30) - Archive formats

### Metadata Tracking

Each artifact tracks comprehensive metadata:
```json
{
  "artifact_metadata": {
    "source_filename": "debian-13-generic-amd64.qcow2",
    "artifact_extension": ".qcow2",
    "disk_format": "qcow2",
    "artifact_type": "disk_image",
    "preference_score": 110,
    "image_variant": "cloud"
  }
}
```

This ensures the best format is selected when multiple options exist.

---

## Loader Behavior

1. Read global config from `config/sync-config.json`
2. Read all per-OS configs from `config/os/*.json`
3. Merge into single runtime config structure
4. Use for validation, discovery, execution

---

## Current Flow

```
input
-> normalize (canonical_os, canonical_version, canonical_arch)
-> validate (min_version/max_version guard, selection_policy)
-> [discovery] discover versions from upstream sources
-> [if auto/latest mode] select latest valid version
-> policy lookup
-> official listing fetch
-> strict candidate selection with artifact preference
-> checksum fetch
-> dry-run plan (with full discovery metadata)
-> cache decision
-> execute from plan.json only
-> verify checksum
```

---

## Run Examples

### Central Image Menu (Recommended)

The new `image` CLI provides an interactive menu system for all operations:

```bash
# Sync - create/update plans (dry-run)
py tools/image/image_cli.py sync              # Interactive menu
py tools/image/image_cli.py sync all          # Sync all OS
py tools/image/image_cli.py sync ubuntu       # Sync all Ubuntu versions

# Pull - download from existing plans
py tools/image/image_cli.py pull              # Interactive menu
py tools/image/image_cli.py pull all          # Pull all planned images
py tools/image/image_cli.py pull ubuntu       # Pull Ubuntu from plans

# Status - show current state
py tools/image/image_cli.py status

# Setting - configure per-OS behavior
py tools/image/image_cli.py setting

# Clean - remove plans and cache
py tools/image/image_cli.py clean             # Interactive menu
py tools/image/image_cli.py clean all         # Clean everything (requires YES confirmation)
py tools/image/image_cli.py clean ubuntu      # Clean specific OS
```

### Legacy Direct Sync (Still Available)

The original sync backend remains available for direct use:

```bash
# Ubuntu
py tools\sync\sync_image.py ubuntu 22.04 amd64
py tools\sync\sync_image.py ubuntu jammy amd64
py tools\sync\sync_image.py ubuntu 20.04 amd64
py tools\sync\sync_image.py ubuntu 24.04 amd64

# Debian (explicit)
py tools\sync\sync_image.py debian 12 amd64
py tools\sync\sync_image.py debian 13 amd64
py tools\sync\sync_image.py debian bookworm amd64
py tools\sync\sync_image.py debian trixie amd64

# Debian (auto/latest mode)
py tools\sync\sync_image.py debian auto amd64
py tools\sync\sync_image.py debian latest amd64

# Rocky Linux
py tools\sync\sync_image.py rocky 8 amd64
py tools\sync\sync_image.py rocky 9 amd64
py tools\sync\sync_image.py rocky 10 amd64

# AlmaLinux
py tools\sync\sync_image.py almalinux 8 amd64
py tools\sync\sync_image.py almalinux 9 amd64
py tools\sync\sync_image.py almalinux 10 amd64
```

Execute from plan:
```bash
py tools\sync\sync_image.py --execute --plan-id <plan_id>
```

Results:
- Creates `state/sync/plans/<plan_id>/plan.json`
- Creates `state/sync/plans/<plan_id>/manifest.json`
- Creates `state/sync/plans/<plan_id>/logs.jsonl`
- Creates `logs/sync/sync.log.jsonl`
- On successful execution: creates `run.json` and files in `cache/official/...`

### Version Selection Evidence

When using auto/latest mode or when upstream discovery is active, the plan includes comprehensive metadata:
```json
{
  "version_selection": {
    "requested_version": "latest",
    "selection_mode": "latest",
    "upstream_discovery": {
      "discovery_source": "https://cloud.debian.org/images/cloud/",
      "discovery_method": "html_directory_listing",
      "discovery_log": [
        {"version": "12", "release_name": "bookworm", "status": "discovered"},
        {"version": "13", "release_name": "trixie", "status": "discovered"}
      ],
      "raw_candidates_found": 2
    },
    "policy_filter": {
      "candidates_before_filter": 2,
      "candidates_after_filter": 2,
      "filter_log": [...]
    },
    "version_selection": {
      "selected_version": "13",
      "selection_reason": "latest valid version >= 12",
      "selection_log": [...]
    }
  }
}
```

---

## Domain-Based Architecture

### New Structure Overview

The repository has been refactored into a clean domain-based structure to prepare for future subsystems:

```
image-build/
├── center/                    # Central menu domain
│   ├── menu.py               # Central menu entry point
│   ├── router.py             # Domain routing logic
│   └── state.py              # Central state management
│
├── image/                     # Image domain - OWNS all image-related code
│   ├── menu.py               # Image domain menu
│   ├── backend/              # Image backend (moved from tools/sync/)
│   │   └── sync_image.py     # Main backend implementation
│   ├── services/             # Business logic services
│   │   ├── sync_service.py
│   │   ├── pull_service.py
│   │   ├── status_service.py
│   │   ├── setting_service.py
│   │   └── clean_service.py
│   ├── adapters/             # External adapters
│   │   └── sync_backend.py   # Bridge to backend
│   ├── config/               # Image config (moved from root config/)
│   │   ├── sync-config.json  # Global sync config
│   │   └── os/               # Per-OS configs
│   │       ├── ubuntu.json
│   │       ├── debian.json
│   │       ├── rocky.json
│   │       ├── almalinux.json
│   │       └── fedora.json
│   ├── runtime/              # Image runtime data (moved from root)
│   │   ├── state/            # Plan state storage
│   │   ├── cache/            # Downloaded images cache
│   │   ├── logs/             # Sync logs
│   │   └── reports/          # Generated reports
│   └── tests/                # Image tests
│
├── openstack/                # OpenStack domain (placeholder)
│   ├── menu.py
│   └── README.md
│
├── guest_config/             # Guest Config domain (placeholder)
│   ├── menu.py
│   └── README.md
│
├── tools/                    # Compatibility shims
│   └── sync/
│       └── sync_image.py     # Compatibility shim (re-exports from image/backend/)
│
├── docs/                     # Documentation
├── doc/                      # Documentation (synced)
├── image_cli.py              # Main entry point
└── .gitignore
```

### What Moved

**Moved to `/image` domain:**
- Config: `config/` → `image/config/`
- Backend: `tools/sync/sync_image.py` → `image/backend/sync_image.py`
- State: `state/` → `image/runtime/state/`
- Cache: `cache/` → `image/runtime/cache/`
- Logs: `logs/` → `image/runtime/logs/`
- Reports: `reports/` → `image/runtime/reports/`

**Root is now clean** - no image-owned runtime folders remain at repo root.

### Routing Flow

```
image_cli.py
    ↓
center/menu.py (Central Menu)
    ↓ (User selects domain)
    ├─→ image/menu.py         # Image domain
    ├─→ openstack/menu.py     # Placeholder
    └─→ guest_config/menu.py  # Placeholder
```

Inside Image domain:
```
image/menu.py
    ↓ (User selects command)
    ├─→ sync_service → image/backend/sync_image.py
    ├─→ pull_service → image/backend/sync_image.py
    ├─→ status_service
    ├─→ setting_service → image/config/os/*.json
    └─→ clean_service → image/runtime/*/
```

### Backend Location

The sync backend now lives under the image domain:
- **Primary location**: `image/backend/sync_image.py`
- **Compatibility shim**: `tools/sync/sync_image.py` (re-exports from new location)

The backend uses paths relative to repo root:
- Config: `image/config/`
- Runtime: `image/runtime/`
- `image/adapters/sync_backend.py` provides a bridge/wrapper
- No breaking changes to existing functionality
- Direct CLI access still works:
  ```bash
  py tools/sync/sync_image.py ubuntu 22.04 amd64
  ```

### Central Menu Details

The central menu (`center/`):
- Provides the main entry point for all domains
- Routes to selected domain via `router.py`
- Manages state via `state.py`
- Is lightweight and only handles menu/routing

### Image Domain Details

The image domain (`image/`):
- Contains all image-related business logic
- Uses a service layer (`image/services/`) for operations
- Bridges to existing backend via adapter pattern
- Provides interactive menu at `image/menu.py`

Menu commands:
- **sync** - Create/update plans (dry-run)
- **pull** - Download images from plans
- **status** - Show current status
- **setting** - Configure per-OS settings
- **clean** - Remove plans and cache
- **back** - Return to central menu

### Command Reference

#### image sync
- Checks all relevant targets for the selected OS
- Resolves upstream source/version/checksum
- Creates/updates plans without downloading
- Interactive OS selection (or specify OS as argument)
- Shows summary: new, unchanged, failed, stale, ready
- Displays discovery results from upstream sources

#### image pull
- Downloads real images from existing plans only
- Plan-driven: no plan = no pull selection
- Interactive OS and version selection
- Shows confirmation summary before execution
- Downloads with progress MB/s and ETA

#### image status
- Shows current status for each OS/version
- Table output with: OS, Version, Status, Cache, Plan ID
- Status values: not planned, planned, ready, stale, failed
- Shows enabled/disabled status for each OS
- Read-only in this round

#### image setting
- Configure per-OS behavior interactively
- **Show Status**: Display all OS config in one table
- **Setting OS**: Configure one OS at a time
  - Press Enter to keep current value
  - Shows current values as defaults
  - Config saved to `config/os/<os>.json`

#### image clean
- Remove plans + cache + downloaded images
- Three modes:
  - `clean all`: Remove everything (requires typing 'YES')
  - `clean <os>` → all versions: Remove all for that OS
  - `clean <os>` → select version: Remove specific OS/version
- Shows dry-run preview before destructive confirmation

### Menu Behavior Rules

1. **Interactive First**: If no arguments provided, show interactive menu
2. **Config-Driven**: System reads config as source of truth; users select targets
3. **Plan-Driven Pull**: Pull only works from existing plans created by sync
4. **Safe Defaults**: Enter keeps current value in settings; destructive actions require confirmation
5. **No Downloads in Sync**: Sync is always dry-run; only pull downloads
6. **Dynamic Discovery**: Sync automatically detects versions from upstream

---

## Current Status

### Phases Ready
- Phase 0: input normalization (supports aliases, rejects invalid inputs)
- Phase 1: policy loading (split config: global + per-OS, optional max_version, selection_policy)
- Phase 2: official listing discovery with **dynamic upstream detection**
- Phase 3: checksum planning + strict candidate guard + min_version/max_version guard
- Phase 4: dry-run state persistence with **full discovery metadata**
- Phase 5: cache HIT/MISS/INVALID/STALE + stale cache detection
- Phase 6: controlled download with progress MB/s + ETA + partial cleanup + retry policy

### Improvements Added
- Download progress shows MB/s and ETA
- Automatic cleanup of `.partial` files on fail or interrupt
- Signal handling for Ctrl+C interrupt
- User-friendly error messages with hints
- **Dynamic upstream version discovery** for all supported OS families
- **Artifact preference logic** (qcow2 > img > others)
- **Comprehensive artifact metadata tracking**
- **Discovery evidence logging** in plan/manifest
- Support for Ubuntu 20.04 (focal)
- Support for Debian 12 (bookworm), 13 (trixie)
- Support for Rocky Linux 8, 9, 10
- Support for AlmaLinux 8, 9, 10
- Stale cache detection (checksum, source_url, filename changes)
- Cache states: HIT, MISS, INVALID, STALE
- Retry policy for failed downloads (3 attempts with exponential backoff)
- Timeout handling improvements (URLError, HTTPError, TimeoutError)
- Checksum mismatch test fixture
- **Config split: global + per-OS files**
- **min_version guard for version validation (required)**
- **max_version guard (optional)**
- **selection_policy support (explicit/latest)**
- **Debian auto/latest version discovery**
- **Enhanced checksum parser** (supports Ubuntu/Debian and Rocky/AlmaLinux formats)
- **Version selection evidence in plan/manifest**

### OS Coverage
- **Ubuntu 20.04 LTS (focal)** - min_version: 20.04, policy: explicit
- **Ubuntu 22.04 LTS (jammy)** - min_version: 20.04, policy: explicit
- **Ubuntu 24.04 LTS (noble)** - min_version: 20.04, policy: explicit
- **Debian 12 (bookworm)** - min_version: 12, policy: latest, supports auto/latest
- **Debian 13 (trixie)** - min_version: 12, policy: latest, supports auto/latest
- **Rocky Linux 8** - min_version: 8, dynamic discovery enabled
- **Rocky Linux 9** - min_version: 8, dynamic discovery enabled
- **Rocky Linux 10** - min_version: 8, dynamic discovery enabled
- **AlmaLinux 8** - min_version: 8, dynamic discovery enabled (stable only)
- **AlmaLinux 9** - min_version: 8, dynamic discovery enabled (stable only)
- **AlmaLinux 10** - min_version: 8, dynamic discovery enabled (stable only)
- **Fedora 39-43** - min_version: 39, policy: latest, **DISABLED** pending path verification

### Known Limitations

#### Fedora Status
- **Discovery**: Working correctly via dl.fedoraproject.org
- **Download paths**: Require verification before enabling
- **Status**: Disabled by default with clear documentation
- **Workaround**: Enable after validating image URLs and checksum locations

#### Version Discovery
- Ubuntu: Explicit mode only (intentional for LTS stability)
- Rocky/AlmaLinux: Explicit mode only (intentional for enterprise stability)
- Debian: Supports explicit + auto/latest modes
- Fedora: Supports latest mode (when enabled)

### Architecture Support
- amd64 (x86_64)
- arm64 (aarch64)

### Error Handling
- Unsupported OS: shows list of supported OS
- Unsupported version: clear error message
- Below min_version: early rejection with clear message
- Above max_version (if set): early rejection with clear message
- Missing plan-id: usage hint
- Bad plan-id: suggestion to run dry-run first
- Discovery failures: logged in discovery metadata

### Remaining Gaps
- Cross-check with extra upstream metadata beyond directory listings
- Full integration tests with complete downloads (Smoke Pass sufficient for most cases)
- Fedora enablement (requires path verification)
- Extend auto/latest mode to Ubuntu, Rocky, AlmaLinux (if desired)

---

## Automated Version Detection Details

### Implementation

The system now implements automated version detection for all OS families:

```python
# Discovery pipeline
candidates, metadata = discover_upstream_versions(os_name, cfg)
valid_candidates, filter_log = filter_candidates_by_policy(candidates, os_cfg, os_name)
selected_version, reason, selection_log = select_version_by_policy(
    valid_candidates, os_cfg, requested_version
)
```

### Discovery Sources

| OS | Discovery URL | Method | Status |
|----|---------------|--------|--------|
| Ubuntu | cloud-images.ubuntu.com | HTML directory listing | Active |
| Debian | cloud.debian.org/images/cloud/ | HTML directory listing | Active |
| Rocky | download.rockylinux.org/pub/rocky/ | HTML directory listing | Active |
| AlmaLinux | repo.almalinux.org/almalinux/ | HTML directory listing | Active |
| Fedora | dl.fedoraproject.org/pub/fedor... | HTML directory listing | Discovery active, downloads disabled |

### Policy Compliance

All discovered versions are filtered through policy:

1. **enabled check**: Skip if OS is disabled
2. **min_version check**: Reject versions below minimum
3. **max_version check**: Reject versions above maximum (if set)
4. **stable-only filter**: Reject unstable/testing releases

### Evidence Preservation

Every discovery operation preserves evidence:
- Raw candidates from upstream
- Policy filter decisions
- Final selection rationale
- All logged in plan.json for auditability

---

## Artifact Selection Details

### Preference Scoring

```python
preference_scores = {
    "qcow2": 100,      # Cloud-native format
    "raw": 80,         # Raw disk (Ubuntu uses .img)
    "vmdk": 60,        # VMware
    "vdi": 60,         # VirtualBox
    "iso": 50,         # Installer media
    "tar": 30,         # Archive
}

# Bonus for cloud-init images
if "cloud" in filename or "generic" in filename:
    score += 10
```

### Metadata Fields

```json
{
  "artifact_metadata": {
    "source_filename": "original-filename.qcow2",
    "artifact_extension": ".qcow2",
    "disk_format": "qcow2",
    "artifact_type": "disk_image",
    "preference_score": 110,
    "image_variant": "cloud"
  }
}
```

This ensures:
- qcow2 is preferred when both qcow2 and img exist
- Official artifacts preserved (no guessing from extension alone)
- Real metadata tracked separately from filename

---

## Repository Structure Refactor

### Overview

The repository has been refactored into a clean domain-based architecture to prepare for future subsystems (OpenStack, Guest Config).

### New Domain Structure

```
image-build/
├── center/                    # Central menu domain
│   ├── menu.py               # Main central menu
│   ├── router.py             # Domain routing logic
│   └── state.py              # Central state management
│
├── image/                     # Image domain
│   ├── menu.py               # Image domain menu
│   ├── services/             # Business logic services
│   │   ├── sync_service.py   # Sync operations
│   │   ├── pull_service.py   # Download operations
│   │   ├── status_service.py # Status reporting
│   │   ├── setting_service.py# Configuration
│   │   └── clean_service.py  # Cleanup operations
│   ├── adapters/             # External adapters
│   │   └── sync_backend.py   # Bridge to existing backend
│   ├── config/               # Domain config
│   │   └── defaults.json     # Default settings
│   └── tests/                # Domain tests
│
├── openstack/                # OpenStack domain (placeholder)
│   ├── menu.py               # Placeholder menu
│   └── README.md             # Documentation
│
├── guest_config/             # Guest Config domain (placeholder)
│   ├── menu.py               # Placeholder menu
│   └── README.md             # Documentation
│
├── tools/                    # Legacy (preserved)
│   ├── image/
│   │   └── image_cli.py      # Old CLI (preserved)
│   └── sync/
│       └── sync_image.py     # Backend (preserved - unchanged)
│
├── docs/                      # Documentation (primary)
├── doc/                       # Documentation (synced)
└── image_cli.py               # New main entry point
```

### Entry Point

The main entry point is now `image_cli.py`:

```bash
python image_cli.py
```

This launches the central menu at `center/menu.py`, which routes to:
- **Image** domain: `image/menu.py`
- **OpenStack** domain: `openstack/menu.py` (placeholder)
- **Guest Config** domain: `guest_config/menu.py` (placeholder)

### Backend Preservation

**CRITICAL**: The existing sync backend at `tools/sync/sync_image.py` is intentionally preserved and unchanged.

- Backend remains fully functional
- `image/adapters/sync_backend.py` provides a bridge/wrapper
- All existing functionality preserved
- Direct CLI access still works

### Files Created

#### Center Domain (`center/`)
- `center/menu.py` - Central menu entry point
- `center/router.py` - Domain routing logic
- `center/state.py` - Central state management

#### Image Domain (`image/`)
- `image/menu.py` - Image domain menu
- `image/services/sync_service.py` - Sync operations
- `image/services/pull_service.py` - Download operations
- `image/services/status_service.py` - Status reporting
- `image/services/setting_service.py` - Configuration
- `image/services/clean_service.py` - Cleanup operations
- `image/adapters/sync_backend.py` - Bridge to existing backend
- `image/config/defaults.json` - Default settings

#### OpenStack Domain (`openstack/`)
- `openstack/menu.py` - Placeholder menu
- `openstack/README.md` - Documentation

#### Guest Config Domain (`guest_config/`)
- `guest_config/menu.py` - Placeholder menu
- `guest_config/README.md` - Documentation

#### Entry Point
- `image_cli.py` - New main entry point

#### Documentation
- `docs/repo-structure.md` - New structure documentation

### Backward Compatibility

The refactor maintains full backward compatibility:

1. **Backend preserved**: `tools/sync/sync_image.py` unchanged
2. **Old CLI preserved**: `tools/image/image_cli.py` still exists
3. **Config paths**: All config paths remain the same
4. **Plan storage**: Plans still in `state/sync/plans/`
5. **Direct access**: Can still run backend directly

### Migration

For existing users:
- New `image_cli.py` entry point provides cleaner menu hierarchy
- All existing plans and configs remain compatible
- Old CLI continues to work
- No migration of data required
