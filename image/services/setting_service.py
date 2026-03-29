#!/usr/bin/env python3
"""
Setting Service - Handles configuration operations

This service provides the business logic for the setting command,
which configures per-OS behavior.
"""

import json
from pathlib import Path
from typing import Dict, List, Optional
from image.adapters.sync_backend import get_sync_adapter

REPO_ROOT = Path(__file__).resolve().parents[2]


class SettingService:
    """Service for handling configuration operations."""
    
    def __init__(self):
        self.adapter = get_sync_adapter()
    
    def get_os_list(self) -> List[str]:
        """Get list of supported OS names."""
        return self.adapter.get_os_list()
    
    def get_os_config(self, os_name: str) -> Dict:
        """
        Get configuration for a specific OS.
        
        Args:
            os_name: OS name
            
        Returns:
            Dictionary containing OS configuration
        """
        config = self.adapter.load_config()
        os_cfg = config.get("os_configs", {}).get(os_name, {})
        
        return {
            "os": os_name,
            "enabled": os_cfg.get("enabled", True),
            "min_version": os_cfg.get("min_version", ""),
            "max_version": os_cfg.get("max_version") or "",
            "selection_policy": os_cfg.get("selection_policy", "explicit"),
            "default_arch": os_cfg.get("default_arch", "x86")
        }
    
    def get_all_os_configs(self) -> List[Dict]:
        """
        Get configuration for all OS.
        
        Returns:
            List of OS configuration dictionaries
        """
        return [self.get_os_config(os_name) for os_name in self.get_os_list()]
    
    def update_os_config(
        self,
        os_name: str,
        enabled: Optional[bool] = None,
        min_version: Optional[str] = None,
        max_version: Optional[str] = None,
        selection_policy: Optional[str] = None,
        default_arch: Optional[str] = None
    ) -> bool:
        """
        Update configuration for a specific OS.
        
        Args:
            os_name: OS name to update
            enabled: New enabled status
            min_version: New minimum version
            max_version: New maximum version (None or empty to clear)
            selection_policy: New selection policy
            default_arch: New default architecture
            
        Returns:
            True if update was successful
        """
        try:
            os_config_path = REPO_ROOT / "image" / "config" / "os" / f"{os_name}.json"
            
            with os_config_path.open("r", encoding="utf-8") as f:
                os_cfg = json.load(f)
            
            if enabled is not None:
                os_cfg["enabled"] = enabled
            if min_version is not None:
                os_cfg["min_version"] = min_version
            if max_version is not None:
                os_cfg["max_version"] = max_version if max_version else None
            if selection_policy is not None:
                os_cfg["selection_policy"] = selection_policy
            if default_arch is not None:
                os_cfg["default_arch"] = default_arch
            
            with os_config_path.open("w", encoding="utf-8") as f:
                json.dump(os_cfg, f, indent=2, ensure_ascii=False)
            
            # Clear adapter cache to reload config
            self.adapter._config = None
            
            return True
            
        except Exception as e:
            print(f"[Error] Failed to update config for {os_name}: {e}")
            return False
