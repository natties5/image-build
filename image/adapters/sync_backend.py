#!/usr/bin/env python3
"""
Sync Backend Adapter

This module provides a clean interface to the existing sync backend
located at tools/sync/sync_image.py. It acts as a bridge between
the new image domain structure and the legacy sync backend.

The existing backend is preserved as-is and this adapter simply
wraps its functionality for use by the new image domain services.
"""

import sys
import importlib.util
from pathlib import Path
from typing import Optional, Dict, Any, Tuple, List

# Repository root
REPO_ROOT = Path(__file__).resolve().parents[2]
SYNC_BACKEND_PATH = REPO_ROOT / "tools" / "sync" / "sync_image.py"

# Load the sync backend module dynamically
_spec = importlib.util.spec_from_file_location("sync_image", SYNC_BACKEND_PATH)
if _spec is None or _spec.loader is None:
    raise ImportError(f"Failed to load sync backend from {SYNC_BACKEND_PATH}")

_sync_module = importlib.util.module_from_spec(_spec)
sys.modules["sync_image"] = _sync_module
_spec.loader.exec_module(_sync_module)


class SyncBackendAdapter:
    """
    Adapter class that wraps the existing sync backend functionality.
    
    This provides a clean interface for the image domain services to
    interact with the legacy sync backend without directly importing
    from the tools/ directory.
    """
    
    def __init__(self):
        self._backend = _sync_module
        self._config: Optional[Dict] = None
    
    def load_config(self) -> Dict:
        """
        Load the sync configuration.
        
        Returns:
            Dictionary containing merged global and per-OS configs.
        """
        if self._config is None:
            self._config = self._backend.load_config()
        return self._config
    
    def canonical_os(self, os_name: str) -> str:
        """
        Normalize OS name to canonical form.
        
        Args:
            os_name: The OS name to normalize
            
        Returns:
            Canonical OS name
            
        Raises:
            ValueError: If OS is not supported
        """
        config = self.load_config()
        return self._backend.canonical_os(config, os_name)
    
    def canonical_version(self, os_name: str, version: str) -> Tuple[str, Dict]:
        """
        Resolve version to canonical form with dynamic discovery support.
        
        Args:
            os_name: Canonical OS name
            version: Version string or alias
            
        Returns:
            Tuple of (canonical_version, version_metadata)
            
        Raises:
            ValueError: If version is not supported
        """
        config = self.load_config()
        return self._backend.canonical_version(config, os_name, version)
    
    def canonical_arch(self, os_name: str, arch: str) -> str:
        """
        Normalize architecture to canonical form.
        
        Args:
            os_name: Canonical OS name
            arch: Architecture string
            
        Returns:
            Canonical architecture name
            
        Raises:
            ValueError: If architecture is not supported
        """
        config = self.load_config()
        return self._backend.canonical_arch(config, os_name, arch)
    
    def build_plan(
        self, 
        os_name: str, 
        version: str, 
        arch: str, 
        version_metadata: Optional[Dict] = None
    ) -> Dict:
        """
        Build a sync plan for the specified OS/version/arch.
        
        Args:
            os_name: Canonical OS name
            version: Canonical version
            arch: Canonical architecture
            version_metadata: Optional version selection metadata
            
        Returns:
            Dictionary containing the plan
        """
        config = self.load_config()
        return self._backend.build_plan(config, os_name, version, arch, version_metadata or {})
    
    def execute_from_plan(self, plan_id: str) -> Dict:
        """
        Execute download from an existing plan.
        
        Args:
            plan_id: The plan ID to execute
            
        Returns:
            Dictionary containing run results
            
        Raises:
            FileNotFoundError: If plan doesn't exist
            RuntimeError: If execution fails
        """
        config = self.load_config()
        return self._backend.execute_from_plan(config, plan_id)
    
    def get_os_list(self) -> List[str]:
        """
        Get list of supported OS names.
        
        Returns:
            Sorted list of OS names
        """
        config = self.load_config()
        return sorted(config.get("os_configs", {}).keys())
    
    def get_os_versions(self, os_name: str) -> List[str]:
        """
        Get list of supported versions for an OS.
        
        Args:
            os_name: OS name
            
        Returns:
            Sorted list of version strings
        """
        config = self.load_config()
        os_cfg = config.get("os_configs", {}).get(os_name, {})
        return sorted(os_cfg.get("sources", {}).keys())
    
    def get_available_plans(self) -> Dict:
        """
        Get all available plans grouped by OS and version.
        
        Returns:
            Nested dictionary of plans[os][version] = [plan_info, ...]
        """
        config = self.load_config()
        plans = {}
        state_root = REPO_ROOT / config.get("state_root", "state/sync/plans")
        
        if not state_root.exists():
            return plans
        
        for plan_dir in state_root.iterdir():
            if plan_dir.is_dir():
                plan_file = plan_dir / "plan.json"
                if plan_file.exists():
                    try:
                        import json
                        with plan_file.open("r", encoding="utf-8") as f:
                            plan = json.load(f)
                        input_data = plan.get("input", {})
                        os_name = input_data.get("os")
                        version = input_data.get("version")
                        plan_id = plan.get("plan_id")
                        
                        if os_name and version and plan_id:
                            if os_name not in plans:
                                plans[os_name] = {}
                            if version not in plans[os_name]:
                                plans[os_name][version] = []
                            plans[os_name][version].append({
                                "plan_id": plan_id,
                                "status": plan.get("status", {}),
                                "plan_file": str(plan_file.relative_to(REPO_ROOT))
                            })
                    except (json.JSONDecodeError, KeyError):
                        continue
        
        return plans


# Singleton instance for easy import
_sync_adapter: Optional[SyncBackendAdapter] = None


def get_sync_adapter() -> SyncBackendAdapter:
    """
    Get the singleton sync backend adapter instance.
    
    Returns:
        SyncBackendAdapter instance
    """
    global _sync_adapter
    if _sync_adapter is None:
        _sync_adapter = SyncBackendAdapter()
    return _sync_adapter
