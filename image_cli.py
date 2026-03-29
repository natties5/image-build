#!/usr/bin/env python3
"""
Image Build System - Main Entry Point

This script launches the central menu for the Image Build System.
It serves as the main entry point that routes to different domains:
- Image domain (image/)
- OpenStack domain (openstack/)
- Guest Config domain (guest_config/)

Usage:
  python image.py

Or on Unix-like systems (with proper permissions):
  ./image.py
"""

import sys
from pathlib import Path

# Repository root
REPO_ROOT = Path(__file__).resolve().parent

# Import and run central menu
center_menu = REPO_ROOT / "center" / "menu.py"
if center_menu.exists():
    import subprocess
    result = subprocess.run([sys.executable, str(center_menu)], cwd=str(REPO_ROOT))
    sys.exit(result.returncode)
else:
    print(f"Error: Central menu not found at {center_menu}")
    sys.exit(1)
