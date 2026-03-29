#!/usr/bin/env python3
"""
Router - Routes to different domains from the central menu
"""

import sys
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


class Router:
    """Routes to different subsystems/domains."""
    
    def route_to_image(self) -> int:
        """Route to the Image domain."""
        image_menu = REPO_ROOT / "image" / "menu.py"
        if not image_menu.exists():
            print("[Error] Image menu not found at image/menu.py")
            return 1
        
        try:
            result = subprocess.run(
                [sys.executable, str(image_menu)],
                cwd=str(REPO_ROOT)
            )
            return result.returncode
        except Exception as e:
            print(f"[Error] Failed to run image menu: {e}")
            return 1
    
    def route_to_openstack(self) -> int:
        """Route to the OpenStack domain."""
        openstack_menu = REPO_ROOT / "openstack" / "menu.py"
        if not openstack_menu.exists():
            print("[Error] OpenStack menu not found at openstack/menu.py")
            return 1
        
        try:
            result = subprocess.run(
                [sys.executable, str(openstack_menu)],
                cwd=str(REPO_ROOT)
            )
            return result.returncode
        except Exception as e:
            print(f"[Error] Failed to run OpenStack menu: {e}")
            return 1
    
    def route_to_guest_config(self) -> int:
        """Route to the Guest Config domain."""
        guest_menu = REPO_ROOT / "guest_config" / "menu.py"
        if not guest_menu.exists():
            print("[Error] Guest Config menu not found at guest_config/menu.py")
            return 1
        
        try:
            result = subprocess.run(
                [sys.executable, str(guest_menu)],
                cwd=str(REPO_ROOT)
            )
            return result.returncode
        except Exception as e:
            print(f"[Error] Failed to run Guest Config menu: {e}")
            return 1
