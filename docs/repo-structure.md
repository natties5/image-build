# Image Build System - Domain-Based Architecture

## Repository Structure (Refactored)

This document describes the new domain-based repository structure.

### Overview

The repository has been refactored to use a clean domain-based layout to prepare for future subsystems. The structure separates concerns into distinct domains:

- **`center/`** - Central menu and routing only
- **`image/`** - All image-related logic and menus
- **`openstack/`** - Placeholder for future OpenStack pipeline work
- **`guest_config/`** - Placeholder for future guest config work

### Directory Structure

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
│   └── tests/                # Domain tests (future)
│
├── openstack/                 # OpenStack domain (placeholder)
│   ├── menu.py               # Placeholder menu
│   └── README.md             # Documentation
│
├── guest_config/              # Guest Config domain (placeholder)
│   ├── menu.py               # Placeholder menu
│   └── README.md             # Documentation
│
├── tools/                     # Legacy tools (preserved)
│   ├── image/                # Old image CLI (preserved)
│   │   └── image_cli.py
│   └── sync/                 # Sync backend (preserved)
│       └── sync_image.py
│
├── config/                    # Configuration
│   ├── sync-config.json      # Global config
│   └── os/                   # Per-OS configs
│
├── docs/                      # Documentation (primary)
├── doc/                       # Documentation (synced)
├── image_cli.py               # Main entry point
└── image.sh                   # Shell wrapper
```

### Key Changes from Previous Layout

#### Before (Previous Layout)

```
image-build/
├── image                      # Shell script entry point
├── tools/
│   ├── image/
│   │   └── image_cli.py      # Central menu
│   └── sync/
│       └── sync_image.py     # Backend
└── config/
```

#### After (New Layout)

```
image-build/
├── image.py                   # Python entry point
├── center/
│   ├── menu.py               # Central menu
│   ├── router.py             # Domain router
│   └── state.py              # State management
├── image/
│   ├── menu.py               # Image domain menu
│   ├── services/             # Service layer
│   └── adapters/             # Backend bridge
├── openstack/                # Placeholder
├── guest_config/             # Placeholder
└── tools/
    ├── image/                # Preserved
    └── sync/                 # Preserved
```

### Routing Flow

The application now follows this routing flow:

```
image.py
    ↓
center/menu.py (Central Menu)
    ↓ (User selects domain)
    ├─→ image/menu.py
    ├─→ openstack/menu.py (placeholder)
    └─→ guest_config/menu.py (placeholder)
```

### Central Menu (`center/`)

The central menu domain provides:

- **Menu Display**: Shows main menu with domain options
- **Routing**: Routes to selected domain via `router.py`
- **State Management**: Tracks active domain via `state.py`

Menu options:
1. **Image** - Manage OS images (sync, pull, status, setting, clean)
2. **OpenStack** - OpenStack pipeline (placeholder)
3. **Guest Config** - Guest configuration (placeholder)
0. **Exit** - Exit the application

### Image Domain (`image/`)

The image domain contains all image-related functionality:

#### Services Layer (`image/services/`)

Each service handles specific business logic:

- **Sync Service** (`sync_service.py`): Creates and updates plans
- **Pull Service** (`pull_service.py`): Downloads images from plans
- **Status Service** (`status_service.py`): Reports on current state
- **Setting Service** (`setting_service.py`): Manages per-OS configuration
- **Clean Service** (`clean_service.py`): Removes plans and cache

#### Adapter Layer (`image/adapters/`)

- **Sync Backend Adapter** (`sync_backend.py`): Bridges to existing `tools/sync/sync_image.py`

### Preserved Legacy Backend

**IMPORTANT**: The existing sync backend at `tools/sync/sync_image.py` is intentionally preserved.

- The backend remains fully functional
- The adapter (`image/adapters/sync_backend.py`) wraps its functionality
- No breaking changes to existing code
- Direct CLI access still works:
  ```bash
  py tools/sync/sync_image.py ubuntu 22.04 amd64
  ```

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

### Backward Compatibility

The refactor maintains backward compatibility:

1. **Existing backend preserved**: `tools/sync/sync_image.py` unchanged
2. **Old CLI preserved**: `tools/image/image_cli.py` still exists
3. **Old entry point**: `image.sh` (renamed from `image`) can still be used
4. **Config paths**: All config paths remain the same
5. **Plan storage**: Plans still stored in `state/sync/plans/`

### Migration Notes

For users of the old system:

- The new `image_cli.py` entry point provides a cleaner menu hierarchy
- All existing functionality is preserved
- Plans created with old system are compatible
- Config files remain in the same location

### Development Guidelines

When adding new features:

1. **Domain Separation**: Add domain-specific logic to appropriate domain
2. **Service Layer**: Implement business logic in services
3. **Adapters**: Use adapters for external dependencies
4. **Central Menu**: Update router when adding new domains
5. **Documentation**: Update both `docs/` and `doc/`

### Testing

After the refactor, verify:

1. Central menu displays correctly
2. Routing to Image domain works
3. Image commands (sync, pull, status, setting, clean) work
4. Routing to placeholder domains works
5. Backend bridge correctly calls existing sync backend
6. No broken imports
7. Old CLI still works

### Summary

This refactor creates a clean foundation for future development by:

- Separating concerns into distinct domains
- Preserving existing functionality
- Establishing clear routing patterns
- Preparing for OpenStack and Guest Config subsystems
- Maintaining backward compatibility

The domain-based structure makes the codebase more maintainable and easier to extend.
