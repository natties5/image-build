#!/usr/bin/env python3
"""
Clean Service - Handles cleanup operations

This service provides the business logic for the clean command,
which removes plans, cache, and downloaded images.
"""

import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from image.adapters.sync_backend import get_sync_adapter

REPO_ROOT = Path(__file__).resolve().parents[2]


class CleanService:
    """Service for handling cleanup operations."""
    
    def __init__(self):
        self.adapter = get_sync_adapter()
    
    def get_os_list(self) -> List[str]:
        """Get list of supported OS names."""
        return self.adapter.get_os_list()
    
    def get_available_plans(self) -> Dict:
        """Get all available plans grouped by OS and version."""
        return self.adapter.get_available_plans()
    
    def get_paths_for_os(self, os_name: str) -> List[Tuple[str, Path]]:
        """
        Get all paths that would be cleaned for a specific OS.
        
        Args:
            os_name: OS name
            
        Returns:
            List of (type, path) tuples
        """
        items = []
        plans = self.get_available_plans()
        config = self.adapter.load_config()
        cache_root = REPO_ROOT / config.get("cache_root", "cache/official")
        state_root = REPO_ROOT / config.get("state_root", "state/sync/plans")
        
        if os_name in plans:
            for version in plans[os_name]:
                for plan_info in plans[os_name][version]:
                    plan_path = REPO_ROOT / plan_info["plan_file"]
                    if plan_path.exists():
                        items.append(("plan", plan_path.parent))
                    # Check for cached files
                    cache_path = cache_root / os_name
                    if cache_path.exists():
                        items.append(("cache", cache_path))
        
        return items
    
    def get_all_paths(self) -> List[Tuple[str, Path]]:
        """
        Get all paths that would be cleaned (everything).
        
        Returns:
            List of (type, path) tuples
        """
        items = []
        config = self.adapter.load_config()
        state_root = REPO_ROOT / config.get("state_root", "state/sync/plans")
        cache_root = REPO_ROOT / config.get("cache_root", "cache/official")
        
        if state_root.exists():
            for plan_dir in state_root.iterdir():
                if plan_dir.is_dir():
                    items.append(("plan", plan_dir))
        
        if cache_root.exists():
            items.append(("cache", cache_root))
        
        return items
    
    def clean_items(self, items: List[Tuple[str, Path]]) -> int:
        """
        Clean (remove) the specified items.
        
        Args:
            items: List of (type, path) tuples to clean
            
        Returns:
            Number of items successfully removed
        """
        removed_count = 0
        
        for item_type, item_path in items:
            if item_path.exists():
                try:
                    if item_path.is_dir():
                        shutil.rmtree(item_path)
                    else:
                        item_path.unlink()
                    removed_count += 1
                except Exception as e:
                    print(f"[Error] Failed to remove {item_path}: {e}")
        
        return removed_count
    
    def clean_all(self) -> int:
        """
        Clean everything (all plans and cache).
        
        Returns:
            Number of items removed
        """
        items = self.get_all_paths()
        return self.clean_items(items)
    
    def clean_os(self, os_name: str) -> int:
        """
        Clean all items for a specific OS.
        
        Args:
            os_name: OS name to clean
            
        Returns:
            Number of items removed
        """
        items = self.get_paths_for_os(os_name)
        return self.clean_items(items)
    
    def clean_os_version(self, os_name: str, version: str) -> int:
        """
        Clean a specific OS/version.
        
        Args:
            os_name: OS name
            version: Version to clean
            
        Returns:
            Number of items removed
        """
        items = []
        plans = self.get_available_plans()
        config = self.adapter.load_config()
        cache_root = REPO_ROOT / config.get("cache_root", "cache/official")
        
        if os_name in plans and version in plans[os_name]:
            for plan_info in plans[os_name][version]:
                plan_path = REPO_ROOT / plan_info["plan_file"]
                if plan_path.exists():
                    items.append(("plan", plan_path.parent))
        
        return self.clean_items(items)
