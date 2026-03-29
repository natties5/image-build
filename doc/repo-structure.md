# Image Build System - Domain-Based Architecture (Strict)

## Repository Structure (Strict Domain Separation)

This document describes the strict domain-based repository structure where all image-related code, config, and runtime data lives under `/image`.

### Overview

The repository has been refactored into a strict domain-based layout:

- **Root is kept clean** - no image-owned runtime folders at repo root
- **`center/`** - Central menu and routing only (lightweight)
- **`image/`** - OWNS all image-related code, config, backend, and runtime data
- **`openstack/`** - Placeholder for future OpenStack pipeline work
- **`guest_config/`** - Placeholder for future guest config work

### Directory Structure

```
image-build/
├── center/                    # Central menu domain (router only)
│   ├── menu.py               # Main central menu
│   ├── router.py             # Domain routing logic
│   └── state.py              # Central state management
│
├── image/                     # Image domain - OWNS everything image-related
│   ├── menu.py               # Image domain menu
│   │
│   ├── backend/              # Image backend (moved from tools/sync/)
│   │   └── sync_image.py     # Main backend implementation
│   │
│   ├── services/             # Business logic services
│   │   ├── sync_service.py   # Sync operations
│   │   ├── pull_service.py   # Download operations
│   │   ├── status_service.py # Status reporting
│   │   ├── setting_service.py# Configuration
│   │   └── clean_service.py  # Cleanup operations
│   │
│   ├── adapters/             # External adapters
│   │   └── sync_backend.py   # Bridge to backend
│   │
│   ├── config/               # Image config (MOVED from root config/)
│   │   ├── sync-config.json  # Global sync configuration
│   │   └── os/               # Per-OS configurations
│   │       ├── ubuntu.json
│   │       ├── debian.json
│   │       ├── rocky.json
│   │       ├── almalinux.json
│   │       └── fedora.json
│   │
│   ├── runtime/              # Image runtime data (MOVED from root)
│   │   ├── state/            # Plan state storage
│   │   │   └── sync/
│   │   │       └── plans/    # Plan files
│   │   ├── cache/            # Downloaded images cache
│   │   │   └── official/
│   │   ├── logs/             # Sync logs
│   │   │   └── sync/
│   │   └── reports/          # Generated reports
│   │       └── sync/
│   │
│   └── tests/                # Image domain tests
│
├── openstack/                 # OpenStack domain (placeholder)
│   ├── menu.py               # Placeholder menu
│   └── README.md             # Documentation
│
├── guest_config/              # Guest Config domain (placeholder)
│   ├── menu.py               # Placeholder menu
│   └── README.md             # Documentation
│
├── tools/                     # Compatibility shims
│   └── sync/
│       └── sync_image.py     # COMPATIBILITY SHIM (re-exports from image/backend/)
│
├── config/                    # Migration notice (see README.txt inside)
│
├── docs/                      # Documentation (primary)
├── doc/                       # Documentation (synced)
├── image_cli.py               # Main entry point
└── image.sh                   # Shell wrapper
```

### What Moved

**MOVED to `/image` domain:**

| Old Location | New Location | Status |
|--------------|--------------|--------|
| `config/sync-config.json` | `image/config/sync-config.json` | ✅ Moved |
| `config/os/*.json` | `image/config/os/*.json` | ✅ Moved |
| `tools/sync/sync_image.py` | `image/backend/sync_image.py` | ✅ Moved |
| `state/` | `image/runtime/state/` | ✅ Moved |
| `cache/` | `image/runtime/cache/` | ✅ Moved |
| `logs/` | `image/runtime/logs/` | ✅ Moved |
| `reports/` | `image/runtime/reports/` | ✅ Moved |

**Root is now clean** - no image-owned runtime folders remain at repo root.

### Compatibility Shims

To maintain backward compatibility, the following shims are provided:

1. **`tools/sync/sync_image.py`** - Re-exports everything from `image/backend/sync_image.py`
2. **`config/README.txt`** - Explains that config moved to `image/config/`

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
    ├─→ sync_service
    │       ↓
    │   image/backend/sync_image.py
    │       ↓
    │   image/runtime/state/plans/  (create plan)
    │   image/runtime/cache/        (download if needed)
    │
    ├─→ pull_service
    │       ↓
    │   image/backend/sync_image.py
    │       ↓
    │   image/runtime/state/plans/  (read plan)
    │   image/runtime/cache/        (store downloaded image)
    │
    ├─→ status_service
    │       ↓
    │   image/runtime/state/        (read plan status)
    │   image/runtime/cache/        (check cache status)
    │
    ├─→ setting_service
    │       ↓
    │   image/config/os/*.json      (read/write config)
    │
    └─→ clean_service
            ↓
        image/runtime/state/        (remove plans)
        image/runtime/cache/        (remove cached images)
        image/runtime/logs/         (remove logs)
```

### Path Configuration

The sync configuration (`image/config/sync-config.json`) now uses these roots:

```json
{
  "state_root": "image/runtime/state",
  "cache_root": "image/runtime/cache",
  "log_root": "image/runtime/logs",
  "report_root": "image/runtime/reports"
}
```

All paths are relative to the repository root.

### Central Menu (`center/`)

The central menu domain is lightweight and only handles:

- **Menu Display**: Shows main menu with domain options
- **Routing**: Routes to selected domain via `router.py`
- **State Management**: Tracks active domain via `state.py`

Menu options:
1. **Image** - Manage OS images (sync, pull, status, setting, clean)
2. **OpenStack** - OpenStack pipeline (placeholder)
3. **Guest Config** - Guest configuration (placeholder)
0. **Exit** - Exit the application

### Image Domain (`image/`)

The image domain OWNS all image-related functionality:

#### Backend (`image/backend/`)

- **`sync_image.py`**: Main backend implementation (moved from `tools/sync/`)
- Handles: plan creation, downloads, version discovery, cache management

#### Services Layer (`image/services/`)

Each service handles specific business logic:

- **Sync Service** (`sync_service.py`): Creates and updates plans
- **Pull Service** (`pull_service.py`): Downloads images from plans
- **Status Service** (`status_service.py`): Reports on current state
- **Setting Service** (`setting_service.py`): Manages per-OS configuration
- **Clean Service** (`clean_service.py`): Removes plans and cache

All services use paths under `image/`:
- Config: `image/config/`
- Runtime: `image/runtime/`

#### Adapter Layer (`image/adapters/`)

- **Sync Backend Adapter** (`sync_backend.py`): Bridges services to backend
- Points to: `image/backend/sync_image.py`

#### Config (`image/config/`)

All image configuration lives here:
- `sync-config.json`: Global sync settings
- `os/*.json`: Per-OS configurations

#### Runtime (`image/runtime/`)

All image runtime data lives here:
- `state/`: Plan state storage
- `cache/`: Downloaded images
- `logs/`: Sync logs
- `reports/`: Generated reports

### Placeholder Domains

#### OpenStack Domain (`openstack/`)

Current status: Placeholder

Reserved for future OpenStack pipeline work:
- Image upload to OpenStack
- Glance image management
- OpenStack integration

#### Guest Config Domain (`guest_config/`)

Current status: Placeholder

Reserved for future guest configuration work:
- Cloud-init configuration
- Guest customization
- VM configuration templates

### Entry Point

The main entry point is `image_cli.py` at the repository root:

```bash
# Launch the central menu
python image_cli.py
```

A shell wrapper is also provided at `image.sh`:

```bash
# Launch via shell wrapper
./image.sh
```

These scripts:
1. Locate the repository root
2. Import and launch `center/menu.py`
3. Exit with the return code from the central menu

### Using the Backend Directly

You can still use the backend directly:

```bash
# Via compatibility shim (old path)
py tools/sync/sync_image.py ubuntu 22.04 amd64

# Via new location (preferred)
py image/backend/sync_image.py ubuntu 22.04 amd64
```

Both work identically.

### Backward Compatibility

The refactor maintains backward compatibility:

1. **Compatibility shim**: `tools/sync/sync_image.py` re-exports from new location
2. **Old CLI preserved**: `tools/image/image_cli.py` still exists
3. **Old entry point**: `image.sh` wrapper still works
4. **Existing plans**: Still accessible from new location
5. **Config migration**: Documented in `config/README.txt`

### Migration Notes

For users of the old system:

- All image config now lives under `image/config/`
- All image runtime data now lives under `image/runtime/`
- The backend now lives at `image/backend/sync_image.py`
- Old paths at root level are deprecated
- Compatibility shims provided for gradual migration

### Development Guidelines

When adding new features:

1. **Domain Ownership**: Add image-specific code to `image/`, not root
2. **Config**: Store image config in `image/config/`
3. **Runtime**: Store image data in `image/runtime/`
4. **Backend**: Use `image/backend/` for image backend code
5. **Services**: Implement business logic in `image/services/`
6. **Central Menu**: Update router when adding new domains
7. **Documentation**: Update both `docs/` and `doc/`

### Testing

After the refactor, verify:

1. Root is clean (no `config/`, `state/`, `cache/`, `logs/`, `reports/` at root)
2. All image data lives under `image/`
3. Central menu displays correctly
4. Routing to Image domain works
5. Image commands (sync, pull, status, setting, clean) work
6. Routing to placeholder domains works
7. Backend bridge works with new paths
8. Compatibility shim works
9. No broken imports
10. Old CLI still works

### Summary

This strict refactor:

- **Cleans the root** - no image-owned folders at repo root
- **Consolidates ownership** - image domain owns everything image-related
- **Maintains compatibility** - shims allow gradual migration
- **Prepares for future** - clean foundation for OpenStack and Guest Config
- **Improves maintainability** - clear ownership and structure

The domain-based structure makes the codebase more maintainable and easier to extend.
