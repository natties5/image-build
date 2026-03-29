#!/usr/bin/env python3
"""
Image Domain Menu

This module provides the interactive menu for image-related operations.
It uses the service layer to perform operations and provides a clean
user interface for managing OS images.

Commands:
  sync      - Create/update plans (dry-run)
  pull      - Download images from plans
  status    - Show current status
  setting   - Configure per-OS settings
  clean     - Remove plans and cache
  back      - Return to central menu
"""

import sys
from pathlib import Path

# Add repository root to path
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from image.services.sync_service import SyncService
from image.services.pull_service import PullService
from image.services.status_service import StatusService
from image.services.setting_service import SettingService
from image.services.clean_service import CleanService


def show_banner():
    """Display the image domain banner."""
    print("\n" + "=" * 50)
    print("  Image Domain - OS Image Management")
    print("=" * 50)


def show_main_menu():
    """Display the main menu options."""
    print("\nSelect a command:")
    print("  1) sync    - Create/update plans (dry-run)")
    print("  2) pull    - Download images from plans")
    print("  3) status  - Show current status")
    print("  4) setting - Configure per-OS settings")
    print("  5) clean   - Remove plans and cache")
    print("  0) back    - Return to central menu")


def get_user_choice() -> str:
    """Get user input and return the choice."""
    try:
        choice = input("\nChoice: ").strip()
        return choice
    except (EOFError, KeyboardInterrupt):
        return "0"


def cmd_sync(service: SyncService) -> int:
    """Handle sync command."""
    print("\n[Sync] Create/update plans (dry-run)")
    
    os_list = service.get_os_list()
    
    print("\nSelect target:")
    print("  1) all")
    for i, os_name in enumerate(os_list, 2):
        print(f"  {i}) {os_name}")
    print("  0) Cancel")
    
    choice = get_user_choice()
    
    if choice == "0":
        return 0
    
    targets = []
    if choice == "1":
        targets = os_list
    else:
        try:
            idx = int(choice) - 2
            if 0 <= idx < len(os_list):
                targets = [os_list[idx]]
            else:
                print("Invalid choice")
                return 1
        except ValueError:
            print("Invalid input")
            return 1
    
    print(f"\n[Sync] Creating plans for {len(targets)} OS(s)...")
    all_results = []
    
    for target_os in targets:
        results = service.sync_os(target_os)
        all_results.extend(results)
        
        for result in results:
            status = result.get("status", "unknown")
            if status == "failed":
                print(f"  {result['os']} {result['version']} -> failed: {result.get('error', 'unknown')}")
            else:
                print(f"  {result['os']} {result['version']} -> {status}")
    
    summary = service.get_summary(all_results)
    print(f"\n[Sync Summary]")
    print(f"  Cached: {summary['cached']}")
    print(f"  New: {summary['new']}")
    print(f"  Failed: {summary['failed']}")
    
    return 0 if summary['failed'] == 0 else 1


def cmd_pull(service: PullService) -> int:
    """Handle pull command."""
    print("\n[Pull] Download images from plans")
    
    os_list = service.get_os_list_with_plans()
    
    if not os_list:
        print("[INFO] No plans available. Run 'sync' first to create plans.")
        return 0
    
    print("\nSelect target:")
    print("  1) all")
    for i, os_name in enumerate(os_list, 2):
        print(f"  {i}) {os_name}")
    print("  0) Cancel")
    
    choice = get_user_choice()
    
    if choice == "0":
        return 0
    
    targets = []
    if choice == "1":
        targets = os_list
    else:
        try:
            idx = int(choice) - 2
            if 0 <= idx < len(os_list):
                targets = [os_list[idx]]
            else:
                print("Invalid choice")
                return 1
        except ValueError:
            print("Invalid input")
            return 1
    
    # Collect plan IDs
    plan_ids = []
    for target_os in targets:
        versions = service.get_versions_for_os(target_os)
        for version in versions:
            plan_ids.extend(service.get_plan_ids_for_os_version(target_os, version))
    
    if not plan_ids:
        print("[INFO] No plans selected for pull.")
        return 0
    
    print(f"\n[Pull Summary] {len(plan_ids)} plan(s) to execute:")
    for pid in plan_ids:
        print(f"  - {pid}")
    
    try:
        confirm = input("\nProceed with download? [y/N]: ").strip().lower()
        if confirm != 'y':
            print("Cancelled")
            return 0
    except EOFError:
        print("Cancelled")
        return 0
    
    print(f"\n[Pull] Downloading {len(plan_ids)} image(s)...")
    results = []
    
    for plan_id in plan_ids:
        try:
            print(f"\n  Executing plan: {plan_id}")
            run = service.pull_plan(plan_id)
            status = run.get("status", "unknown")
            print(f"  Status: {status}")
            results.append({"plan_id": plan_id, "status": status, "success": True})
        except Exception as e:
            print(f"  Failed: {e}")
            results.append({"plan_id": plan_id, "status": "failed", "success": False, "error": str(e)})
    
    summary = service.get_summary(results)
    print(f"\n[Pull Complete]")
    print(f"  Success: {summary['success']}")
    print(f"  Failed: {summary['failed']}")
    
    return 0 if summary['failed'] == 0 else 1


def cmd_status(service: StatusService) -> int:
    """Handle status command."""
    print("\n[Status] Current status of all OS/versions")
    
    all_status = service.get_all_status()
    
    print("\n" + "=" * 80)
    print(f"{'OS':<12} {'Version':<10} {'Status':<12} {'Cache':<8} {'Plan ID':<14} {'Enabled':<8}")
    print("=" * 80)
    
    for status in all_status:
        enabled_str = "yes" if status['enabled'] else "no"
        print(f"{status['os']:<12} {status['version']:<10} {status['plan_status']:<12} "
              f"{status['cache']:<8} {status['plan_id']:<14} {enabled_str:<8}")
    
    print("=" * 80)
    
    summary = service.get_summary()
    print(f"\nTotal OS: {summary['total_os']}")
    print(f"Total plans: {summary['total_plans']}")
    
    return 0


def cmd_setting(service: SettingService) -> int:
    """Handle setting command."""
    print("\n[Setting] Configure per-OS behavior")
    print("\n  1) Show Status")
    print("  2) Setting OS")
    print("  0) Cancel")
    
    choice = get_user_choice()
    
    if choice == "0":
        return 0
    
    if choice == "1":
        # Show Status
        configs = service.get_all_os_configs()
        
        print("\n" + "=" * 80)
        print(f"{'OS':<12} {'Enabled':<8} {'Min Ver':<10} {'Max Ver':<10} {'Policy':<10} {'Default Arch':<12}")
        print("=" * 80)
        
        for cfg in configs:
            print(f"{cfg['os']:<12} {('yes' if cfg['enabled'] else 'no'):<8} "
                  f"{cfg['min_version']:<10} {cfg['max_version']:<10} "
                  f"{cfg['selection_policy']:<10} {cfg['default_arch']:<12}")
        
        print("=" * 80)
        return 0
    
    if choice == "2":
        # Setting OS
        os_list = service.get_os_list()
        
        print("\nSelect OS:")
        for i, os_name in enumerate(os_list, 1):
            print(f"  {i}) {os_name}")
        print("  0) Cancel")
        
        os_choice = get_user_choice()
        if os_choice == "0":
            return 0
        
        try:
            idx = int(os_choice) - 1
            if 0 <= idx < len(os_list):
                selected_os = os_list[idx]
            else:
                print("Invalid choice")
                return 1
        except ValueError:
            print("Invalid input")
            return 1
        
        # Get current config
        cfg = service.get_os_config(selected_os)
        
        print(f"\n[Configure {selected_os}]")
        print("Press Enter to keep current value\n")
        
        # Min version
        new_min = input(f"Min version [{cfg['min_version']}]: ").strip()
        # Max version
        new_max = input(f"Max version [{cfg['max_version']}]: ").strip()
        # Selection policy
        new_policy = input(f"Selection policy (explicit/latest) [{cfg['selection_policy']}]: ").strip()
        # Default arch
        new_arch = input(f"Default arch (x86/arm64) [{cfg['default_arch']}]: ").strip()
        # Enabled
        new_enabled = input(f"Enabled (yes/no) [{('yes' if cfg['enabled'] else 'no')}]: ").strip().lower()
        
        # Update config
        success = service.update_os_config(
            selected_os,
            enabled=new_enabled == "yes" if new_enabled else None,
            min_version=new_min if new_min else None,
            max_version=new_max if new_max else None,
            selection_policy=new_policy if new_policy in ("explicit", "latest") else None,
            default_arch=new_arch if new_arch else None
        )
        
        if success:
            print(f"\n[OK] Configuration saved for {selected_os}")
        else:
            print(f"\n[Error] Failed to save configuration for {selected_os}")
        
        return 0 if success else 1
    
    print("Invalid choice")
    return 1


def cmd_clean(service: CleanService) -> int:
    """Handle clean command."""
    print("\n[Clean] Remove plans, cache, and downloaded images")
    
    os_list = service.get_os_list()
    
    print("\nSelect target:")
    print("  1) all")
    for i, os_name in enumerate(os_list, 2):
        print(f"  {i}) {os_name}")
    print("  0) Cancel")
    
    choice = get_user_choice()
    
    if choice == "0":
        return 0
    
    if choice == "1":
        # Clean all
        items = service.get_all_paths()
        
        if not items:
            print("[INFO] Nothing to clean.")
            return 0
        
        print("\n[WARNING] This will remove ALL plans, cache, and downloaded images!")
        print("Items to be removed:")
        for item_type, item_path in items:
            print(f"  [{item_type}] {item_path}")
        
        try:
            confirm = input("\nType 'YES' to confirm: ").strip()
            if confirm != "YES":
                print("Cancelled")
                return 0
        except EOFError:
            print("Cancelled")
            return 0
        
        removed = service.clean_all()
        print(f"\n[Clean Complete]")
        print(f"  Removed {removed} item(s)")
        return 0
    
    # Clean specific OS
    try:
        idx = int(choice) - 2
        if 0 <= idx < len(os_list):
            selected_os = os_list[idx]
        else:
            print("Invalid choice")
            return 1
    except ValueError:
        print("Invalid input")
        return 1
    
    items = service.get_paths_for_os(selected_os)
    
    if not items:
        print(f"[INFO] No items found to clean for {selected_os}")
        return 0
    
    print(f"\nItems to be removed for {selected_os}:")
    for item_type, item_path in items:
        print(f"  [{item_type}] {item_path}")
    
    try:
        confirm = input("\nProceed? [y/N]: ").strip().lower()
        if confirm != 'y':
            print("Cancelled")
            return 0
    except EOFError:
        print("Cancelled")
        return 0
    
    removed = service.clean_os(selected_os)
    print(f"\n[Clean Complete]")
    print(f"  Removed {removed} item(s)")
    return 0


def main() -> int:
    """Main entry point for the image domain menu."""
    sync_service = SyncService()
    pull_service = PullService()
    status_service = StatusService()
    setting_service = SettingService()
    clean_service = CleanService()
    
    while True:
        show_banner()
        show_main_menu()
        choice = get_user_choice()
        
        if choice == "0":
            return 0
        elif choice == "1":
            result = cmd_sync(sync_service)
        elif choice == "2":
            result = cmd_pull(pull_service)
        elif choice == "3":
            result = cmd_status(status_service)
        elif choice == "4":
            result = cmd_setting(setting_service)
        elif choice == "5":
            result = cmd_clean(clean_service)
        else:
            print("\n[Error] Invalid choice. Please select 0-5.")
            result = 1
        
        if result != 0:
            print(f"\n[Warning] Command returned exit code: {result}")
        
        print()  # Empty line for readability
        input("Press Enter to continue...")


if __name__ == "__main__":
    raise SystemExit(main())
