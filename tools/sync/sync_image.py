#!/usr/bin/env python3
"""
Compatibility shim for the sync image backend.

This file provides backward compatibility for code that imports from
tools/sync/sync_image.py. The actual implementation has moved to:
    image/backend/sync_image.py

This shim re-exports all functionality from the new location.
"""

import sys
from pathlib import Path

# Add repository root to path to enable imports
REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

# Import everything from the new location
from image.backend.sync_image import (
    DownloadInterruptedError,
    LinkParser,
    load_config,
    canonical_os,
    canonical_version,
    canonical_arch,
    discover_upstream_versions,
    filter_candidates_by_policy,
    select_version_by_policy,
    build_plan,
    execute_from_plan,
    main,
)

__all__ = [
    "DownloadInterruptedError",
    "LinkParser",
    "load_config",
    "canonical_os",
    "canonical_version",
    "canonical_arch",
    "discover_upstream_versions",
    "filter_candidates_by_policy",
    "select_version_by_policy",
    "build_plan",
    "execute_from_plan",
    "main",
]
