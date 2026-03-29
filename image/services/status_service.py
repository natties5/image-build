#!/usr/bin/env python3
"""
Status Service - Handles status reporting operations

This service provides the business logic for the status command,
which shows the current state of all OS/versions.
"""

from typing import Dict, List
from image.adapters.sync_backend import get_sync_adapter


class StatusService:
    """Service for handling status reporting operations."""
    
    def __init__(self):
        self.adapter = get_sync_adapter()
    
    def get_os_list(self) -> List[str]:
        """Get list of supported OS names."""
        return self.adapter.get_os_list()
    
    def get_os_versions(self, os_name: str) -> List[str]:
        """Get list of supported versions for an OS."""
        return self.adapter.get_os_versions(os_name)
    
    def get_available_plans(self) -> Dict:
        """Get all available plans grouped by OS and version."""
        return self.adapter.get_available_plans()
    
    def get_os_status(self, os_name: str, version: str) -> Dict:
        """
        Get status for a specific OS/version.
        
        Args:
            os_name: OS name
            version: Version string
            
        Returns:
            Dictionary with status information
        """
        plans = self.get_available_plans()
        config = self.adapter.load_config()
        os_cfg = config.get("os_configs", {}).get(os_name, {})
        enabled = os_cfg.get("enabled", True)
        
        status = {
            "os": os_name,
            "version": version,
            "enabled": enabled,
            "plan_status": "not planned",
            "cache": "-",
            "plan_id": "-"
        }
        
        if os_name in plans and version in plans[os_name]:
            plan_list = plans[os_name][version]
            if plan_list:
                plan_info = plan_list[0]  # Take first plan
                plan_status = plan_info.get("status", {})
                cache = plan_status.get("phase_5_cache", "MISS")
                plan_id = plan_info.get("plan_id", "-")[:12]
                
                if cache == "HIT":
                    plan_status_str = "ready"
                elif cache == "STALE":
                    plan_status_str = "stale"
                elif cache == "MISS":
                    plan_status_str = "planned"
                else:
                    plan_status_str = "unknown"
                
                status["plan_status"] = plan_status_str
                status["cache"] = cache
                status["plan_id"] = plan_id
        
        return status
    
    def get_all_status(self) -> List[Dict]:
        """
        Get status for all OS/versions.
        
        Returns:
            List of status dictionaries for all OS/versions
        """
        all_status = []
        os_list = self.get_os_list()
        
        for os_name in os_list:
            versions = self.get_os_versions(os_name)
            for version in versions:
                all_status.append(self.get_os_status(os_name, version))
        
        return all_status
    
    def get_summary(self) -> Dict[str, int]:
        """
        Get summary statistics.
        
        Returns:
            Dictionary with total counts
        """
        plans = self.get_available_plans()
        total_plans = sum(len(v) for plans_os in plans.values() for v in plans_os.values())
        
        return {
            "total_os": len(self.get_os_list()),
            "total_plans": total_plans
        }
