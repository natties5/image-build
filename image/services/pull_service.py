#!/usr/bin/env python3
"""
Pull Service - Handles image download operations

This service provides the business logic for the pull command,
which downloads images from existing plans.
"""

from typing import Dict, List, Optional
from image.adapters.sync_backend import get_sync_adapter


class PullService:
    """Service for handling image download operations."""
    
    def __init__(self):
        self.adapter = get_sync_adapter()
    
    def get_available_plans(self) -> Dict:
        """Get all available plans grouped by OS and version."""
        return self.adapter.get_available_plans()
    
    def get_os_list_with_plans(self) -> List[str]:
        """Get list of OS names that have plans."""
        plans = self.get_available_plans()
        return sorted(plans.keys())
    
    def get_versions_for_os(self, os_name: str) -> List[str]:
        """Get list of versions that have plans for a specific OS."""
        plans = self.get_available_plans()
        if os_name not in plans:
            return []
        return sorted(plans[os_name].keys())
    
    def get_plan_ids_for_os_version(self, os_name: str, version: str) -> List[str]:
        """Get all plan IDs for a specific OS and version."""
        plans = self.get_available_plans()
        if os_name not in plans or version not in plans[os_name]:
            return []
        return [p["plan_id"] for p in plans[os_name][version]]
    
    def pull_plan(self, plan_id: str) -> Dict:
        """
        Pull (download) a single plan.
        
        Args:
            plan_id: The plan ID to pull
            
        Returns:
            Dictionary containing run results
            
        Raises:
            Exception: If pull fails
        """
        return self.adapter.execute_from_plan(plan_id)
    
    def pull_os_all_versions(self, os_name: str) -> List[Dict]:
        """
        Pull all versions for a specific OS.
        
        Args:
            os_name: OS name
            
        Returns:
            List of pull results for each plan
        """
        results = []
        versions = self.get_versions_for_os(os_name)
        
        for version in versions:
            plan_ids = self.get_plan_ids_for_os_version(os_name, version)
            for plan_id in plan_ids:
                try:
                    run = self.pull_plan(plan_id)
                    results.append({
                        "os": os_name,
                        "version": version,
                        "plan_id": plan_id,
                        "status": run.get("status", "unknown"),
                        "success": True
                    })
                except Exception as e:
                    results.append({
                        "os": os_name,
                        "version": version,
                        "plan_id": plan_id,
                        "status": "failed",
                        "success": False,
                        "error": str(e)
                    })
        
        return results
    
    def pull_all(self) -> List[Dict]:
        """
        Pull all available plans for all OS.
        
        Returns:
            List of pull results for all plans
        """
        results = []
        os_list = self.get_os_list_with_plans()
        
        for os_name in os_list:
            os_results = self.pull_os_all_versions(os_name)
            results.extend(os_results)
        
        return results
    
    def get_summary(self, results: List[Dict]) -> Dict[str, int]:
        """
        Get summary statistics from pull results.
        
        Args:
            results: List of pull result dictionaries
            
        Returns:
            Dictionary with success/failure counts
        """
        success_count = sum(1 for r in results if r.get("success", False))
        failed_count = len(results) - success_count
        
        return {
            "success": success_count,
            "failed": failed_count,
            "total": len(results)
        }
