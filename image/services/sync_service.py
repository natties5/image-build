#!/usr/bin/env python3
"""
Sync Service - Handles image synchronization operations

This service provides the business logic for the sync command,
which creates and updates plans without downloading images.
"""

from typing import Dict, List, Optional
from image.adapters.sync_backend import get_sync_adapter


class SyncService:
    """Service for handling image synchronization operations."""
    
    def __init__(self):
        self.adapter = get_sync_adapter()
    
    def get_os_list(self) -> List[str]:
        """Get list of supported OS names."""
        return self.adapter.get_os_list()
    
    def get_os_versions(self, os_name: str) -> List[str]:
        """Get list of supported versions for an OS."""
        return self.adapter.get_os_versions(os_name)
    
    def sync_os(self, os_name: str, default_arch: str = "amd64") -> List[Dict]:
        """
        Sync all versions for a specific OS.
        
        Args:
            os_name: OS name (must be canonical)
            default_arch: Default architecture to use
            
        Returns:
            List of sync results for each version
        """
        results = []
        versions = self.get_os_versions(os_name)
        config = self.adapter.load_config()
        os_cfg = config.get("os_configs", {}).get(os_name, {})
        
        for version in versions:
            try:
                # Check if version should be synced based on policy
                canonical_ver, version_metadata = self.adapter.canonical_version(os_name, version)
                
                # Convert arch to canonical form for the backend
                canonical_arch_val = self.adapter.canonical_arch(os_name, default_arch)
                
                # Build plan (dry-run)
                plan = self.adapter.build_plan(os_name, canonical_ver, canonical_arch_val, version_metadata)
                
                cache_status = plan.get("status", {}).get("phase_5_cache", "MISS")
                results.append({
                    "os": os_name,
                    "version": version,
                    "status": "ready" if cache_status == "HIT" else "new",
                    "cache": cache_status,
                    "plan_id": plan.get("plan_id")
                })
                
            except Exception as e:
                results.append({
                    "os": os_name,
                    "version": version,
                    "status": "failed",
                    "error": str(e)
                })
        
        return results
    
    def sync_all(self, default_arch: str = "amd64") -> Dict[str, List[Dict]]:
        """
        Sync all OS and all their versions.
        
        Args:
            default_arch: Default architecture to use
            
        Returns:
            Dictionary mapping OS names to their sync results
        """
        all_results = {}
        os_list = self.get_os_list()
        
        for os_name in os_list:
            all_results[os_name] = self.sync_os(os_name, default_arch)
        
        return all_results
    
    def get_summary(self, results: List[Dict]) -> Dict[str, int]:
        """
        Get summary statistics from sync results.
        
        Args:
            results: List of sync result dictionaries
            
        Returns:
            Dictionary with counts for each status
        """
        return {
            "cached": sum(1 for r in results if r.get("status") == "ready"),
            "new": sum(1 for r in results if r.get("status") == "new"),
            "failed": sum(1 for r in results if r.get("status") == "failed")
        }
