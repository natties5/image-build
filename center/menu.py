#!/usr/bin/env python3
"""
Central Menu - Main Entry Point for Image Build System

This module provides the central menu that routes to different domains:
- Image domain (image/)
- OpenStack domain (openstack/)
- Guest Config domain (guest_config/)
"""

import sys
from pathlib import Path

# Add repository root to path
REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from center.router import Router
from center.state import CenterState


def show_banner():
    """Display the central menu banner."""
    print("\n" + "=" * 50)
    print("  Image Build System - Central Menu")
    print("=" * 50)


def show_menu():
    """Display the main menu options."""
    print("\nSelect a subsystem:")
    print("  1) Image - Manage OS images (sync, pull, status, etc.)")
    print("  2) OpenStack - OpenStack pipeline (placeholder)")
    print("  3) Guest Config - Guest configuration (placeholder)")
    print("  0) Exit")


def get_user_choice() -> str:
    """Get user input and return the choice."""
    try:
        choice = input("\nChoice: ").strip()
        return choice
    except (EOFError, KeyboardInterrupt):
        return "0"


def main() -> int:
    """Main entry point for the central menu."""
    state = CenterState()
    router = Router()
    
    while True:
        show_banner()
        show_menu()
        choice = get_user_choice()
        
        if choice == "0":
            print("\nGoodbye!")
            return 0
        elif choice == "1":
            result = router.route_to_image()
            if result != 0:
                print(f"\n[Warning] Image domain returned exit code: {result}")
        elif choice == "2":
            result = router.route_to_openstack()
            if result != 0:
                print(f"\n[Warning] OpenStack domain returned exit code: {result}")
        elif choice == "3":
            result = router.route_to_guest_config()
            if result != 0:
                print(f"\n[Warning] Guest Config domain returned exit code: {result}")
        else:
            print("\n[Error] Invalid choice. Please select 0-3.")
        
        print()  # Empty line for readability


if __name__ == "__main__":
    raise SystemExit(main())
