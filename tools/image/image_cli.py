#!/usr/bin/env python3
"""
Central Image CLI Menu System

A neutral, shared CLI layer for managing OS images across subsystems.
Serves as the front-end for sync, pull, status, setting, and clean operations.
"""

import argparse
import json
import sys
from pathlib import Path

# Repository root
REPO_ROOT = Path(__file__).resolve().parents[2]

# Import sync backend functions using importlib to avoid module path issues
import importlib.util
spec = importlib.util.spec_from_file_location("sync_image", REPO_ROOT / "tools" / "sync" / "sync_image.py")
sync_module = importlib.util.module_from_spec(spec)
sys.modules["sync_image"] = sync_module
spec.loader.exec_module(sync_module)

# Extract functions from sync module
load_config = sync_module.load_config
canonical_os = sync_module.canonical_os
canonical_version = sync_module.canonical_version
canonical_arch = sync_module.canonical_arch
build_plan = sync_module.build_plan
execute_from_plan = sync_module.execute_from_plan


def get_os_list(config: dict) -> list[str]:
    """Get list of supported OS names."""
    return sorted(config.get("os_configs", {}).keys())


def get_os_versions(config: dict, os_name: str) -> list[str]:
    """Get list of supported versions for an OS."""
    os_cfg = config.get("os_configs", {}).get(os_name, {})
    return sorted(os_cfg.get("sources", {}).keys())


def get_available_plans(config: dict) -> dict:
    """Get all available plans grouped by OS and version."""
    plans = {}
    state_root = REPO_ROOT / config.get("state_root", "state/sync/plans")
    
    if not state_root.exists():
        return plans
    
    for plan_dir in state_root.iterdir():
        if plan_dir.is_dir():
            plan_file = plan_dir / "plan.json"
            if plan_file.exists():
                try:
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


def interactive_select_os(config: dict, title: str = "Select target:") -> str | None:
    """Interactive OS selection menu."""
    os_list = get_os_list(config)
    
    print(f"\n{title}")
    print("1) all")
    for i, os_name in enumerate(os_list, 2):
        print(f"{i}) {os_name}")
    print("0) Cancel")
    
    try:
        choice = input("\nChoice: ").strip()
        if choice == "0":
            return None
        if choice == "1":
            return "all"
        idx = int(choice) - 2
        if 0 <= idx < len(os_list):
            return os_list[idx]
        print("Invalid choice")
        return None
    except (ValueError, EOFError):
        print("Invalid input")
        return None


def interactive_select_version(config: dict, os_name: str, allow_all: bool = True) -> str | None:
    """Interactive version selection menu."""
    versions = get_os_versions(config, os_name)
    
    print(f"\n{os_name}")
    start = 1
    if allow_all:
        print("1) all")
        start = 2
    for i, version in enumerate(versions, start):
        print(f"{i}) {version}")
    print("0) Cancel")
    
    try:
        choice = input("\nChoice: ").strip()
        if choice == "0":
            return None
        if allow_all and choice == "1":
            return "all"
        idx = int(choice) - start
        if 0 <= idx < len(versions):
            return versions[idx]
        print("Invalid choice")
        return None
    except (ValueError, EOFError):
        print("Invalid input")
        return None


def interactive_select_version_from_plans(plans: dict, os_name: str) -> str | None:
    """Interactive version selection from existing plans only."""
    if os_name not in plans:
        return None
    
    versions = sorted(plans[os_name].keys())
    
    print(f"\n{os_name}")
    print("1) all")
    for i, version in enumerate(versions, 2):
        print(f"{i}) {version}")
    print("0) Cancel")
    
    try:
        choice = input("\nChoice: ").strip()
        if choice == "0":
            return None
        if choice == "1":
            return "all"
        idx = int(choice) - 2
        if 0 <= idx < len(versions):
            return versions[idx]
        print("Invalid choice")
        return None
    except (ValueError, EOFError):
        print("Invalid input")
        return None


def cmd_sync(config: dict, args) -> int:
    """Sync command - create/update plans for OS versions."""
    os_name = args.os
    
    # Interactive mode if no OS specified
    if not os_name:
        os_name = interactive_select_os(config, "Select target:")
        if os_name is None:
            print("Cancelled")
            return 0
    
    # Validate OS if specified
    if os_name != "all":
        try:
            os_name = canonical_os(config, os_name)
        except ValueError as e:
            print(f"[ERROR] {e}", file=sys.stderr)
            return 1
    
    # Determine which OS to sync
    targets = []
    if os_name == "all":
        targets = get_os_list(config)
    else:
        targets = [os_name]
    
    # Default architecture - use amd64 (gets converted to x86_64 internally)
    default_arch = "amd64"
    
    print(f"\n[Sync] Creating plans for {len(targets)} OS(s)...")
    results = []
    
    for target_os in targets:
        versions = get_os_versions(config, target_os)
        os_cfg = config.get("os_configs", {}).get(target_os, {})
        
        for version in versions:
            try:
                # Check if version should be synced based on policy
                canonical_ver, version_metadata = canonical_version(config, target_os, version)
                
                # Convert arch to canonical form for the backend
                canonical_arch_val = canonical_arch(config, target_os, default_arch)
                
                # Build plan (dry-run)
                plan = build_plan(config, target_os, canonical_ver, canonical_arch_val, version_metadata)
                
                cache_status = plan.get("status", {}).get("phase_5_cache", "MISS")
                results.append({
                    "os": target_os,
                    "version": version,
                    "status": "ready" if cache_status == "HIT" else "new",
                    "cache": cache_status,
                    "plan_id": plan.get("plan_id")
                })
                print(f"  {target_os} {version} -> {'cached' if cache_status == 'HIT' else 'new'}")
                
            except Exception as e:
                results.append({
                    "os": target_os,
                    "version": version,
                    "status": "failed",
                    "error": str(e)
                })
                print(f"  {target_os} {version} -> failed: {e}")
    
    print(f"\n[Sync Summary]")
    cached = sum(1 for r in results if r.get("status") == "ready")
    new_plans = sum(1 for r in results if r.get("status") == "new")
    failed = sum(1 for r in results if r.get("status") == "failed")
    print(f"  Cached: {cached}")
    print(f"  New: {new_plans}")
    print(f"  Failed: {failed}")
    
    return 0 if failed == 0 else 1


def cmd_pull(config: dict, args) -> int:
    """Pull command - download images from existing plans."""
    # Get available plans
    plans = get_available_plans(config)
    
    if not plans:
        print("[INFO] No plans available. Run 'image sync' first to create plans.")
        return 0
    
    os_name = args.os
    
    # Interactive mode if no OS specified
    if not os_name:
        os_list = sorted(plans.keys())
        print("\nSelect target:")
        print("1) all")
        for i, os_name_item in enumerate(os_list, 2):
            print(f"{i}) {os_name_item}")
        print("0) Cancel")
        
        try:
            choice = input("\nChoice: ").strip()
            if choice == "0":
                print("Cancelled")
                return 0
            if choice == "1":
                os_name = "all"
            else:
                idx = int(choice) - 2
                if 0 <= idx < len(os_list):
                    os_name = os_list[idx]
                else:
                    print("Invalid choice")
                    return 1
        except (ValueError, EOFError):
            print("Invalid input")
            return 1
    
    # Determine targets
    targets = []
    if os_name == "all":
        targets = list(plans.keys())
    else:
        if os_name not in plans:
            print(f"[ERROR] No plans found for {os_name}. Run 'image sync {os_name}' first.")
            return 1
        targets = [os_name]
    
    # Collect plan IDs to execute
    plan_ids = []
    for target_os in targets:
        if target_os in plans:
            # Interactive version selection if only one OS and interactive
            if len(targets) == 1 and not args.version:
                version_choice = interactive_select_version_from_plans(plans, target_os)
                if version_choice is None:
                    print("Cancelled")
                    return 0
                if version_choice == "all":
                    for version, plan_list in plans[target_os].items():
                        for plan_info in plan_list:
                            plan_ids.append(plan_info["plan_id"])
                else:
                    if version_choice in plans[target_os]:
                        for plan_info in plans[target_os][version_choice]:
                            plan_ids.append(plan_info["plan_id"])
            else:
                # Pull all versions for this OS
                for version, plan_list in plans[target_os].items():
                    for plan_info in plan_list:
                        plan_ids.append(plan_info["plan_id"])
    
    if not plan_ids:
        print("[INFO] No plans selected for pull.")
        return 0
    
    # Show confirmation summary
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
    
    # Execute pulls
    print(f"\n[Pull] Downloading {len(plan_ids)} image(s)...")
    success_count = 0
    failed_count = 0
    
    for plan_id in plan_ids:
        try:
            print(f"\n  Executing plan: {plan_id}")
            run = execute_from_plan(config, plan_id)
            status = run.get("status", "unknown")
            print(f"  Status: {status}")
            if status in ("downloaded", "cached"):
                success_count += 1
            else:
                failed_count += 1
        except Exception as e:
            print(f"  Failed: {e}")
            failed_count += 1
    
    print(f"\n[Pull Complete]")
    print(f"  Success: {success_count}")
    print(f"  Failed: {failed_count}")
    
    return 0 if failed_count == 0 else 1


def cmd_status(config: dict, args) -> int:
    """Status command - show current status of all OS/versions."""
    plans = get_available_plans(config)
    os_list = get_os_list(config)
    
    print("\n" + "=" * 70)
    print(f"{'OS':<12} {'Version':<10} {'Status':<12} {'Cache':<8} {'Plan ID':<14}")
    print("=" * 70)
    
    for os_name in os_list:
        os_cfg = config.get("os_configs", {}).get(os_name, {})
        versions = get_os_versions(config, os_name)
        enabled = os_cfg.get("enabled", True)
        
        for version in versions:
            # Check plan status
            status = "not planned"
            cache = "-"
            plan_id = "-"
            
            if os_name in plans and version in plans[os_name]:
                plan_list = plans[os_name][version]
                if plan_list:
                    plan_info = plan_list[0]  # Take first plan
                    plan_status = plan_info.get("status", {})
                    cache = plan_status.get("phase_5_cache", "MISS")
                    plan_id = plan_info.get("plan_id", "-")[:12]
                    
                    if cache == "HIT":
                        status = "ready"
                    elif cache == "STALE":
                        status = "stale"
                    elif cache == "MISS":
                        status = "planned"
                    else:
                        status = "unknown"
            
            enabled_str = "" if enabled else " (disabled)"
            print(f"{os_name:<12} {version:<10} {status:<12} {cache:<8} {plan_id:<14}{enabled_str}")
    
    print("=" * 70)
    print(f"\nTotal OS: {len(os_list)}")
    print(f"Total plans: {sum(len(v) for plans_os in plans.values() for v in plans_os.values())}")
    
    return 0


def cmd_setting(config: dict, args) -> int:
    """Setting command - configure per-OS behavior."""
    print("\n[Image Setting]")
    print("1) Show Status")
    print("2) Setting OS")
    print("0) Cancel")
    
    try:
        choice = input("\nChoice: ").strip()
        if choice == "0":
            return 0
        
        if choice == "1":
            # Show Status
            print("\n" + "=" * 80)
            print(f"{'OS':<12} {'Enabled':<8} {'Min Ver':<10} {'Max Ver':<10} {'Policy':<10} {'Default Arch':<12}")
            print("=" * 80)
            
            os_list = get_os_list(config)
            for os_name in os_list:
                os_cfg = config.get("os_configs", {}).get(os_name, {})
                enabled = "yes" if os_cfg.get("enabled", True) else "no"
                min_ver = os_cfg.get("min_version", "-")
                max_ver = os_cfg.get("max_version") or "-"
                policy = os_cfg.get("selection_policy", "explicit")
                default_arch = os_cfg.get("default_arch", "x86")
                
                print(f"{os_name:<12} {enabled:<8} {min_ver:<10} {max_ver:<10} {policy:<10} {default_arch:<12}")
            
            print("=" * 80)
            return 0
        
        elif choice == "2":
            # Setting OS
            os_list = get_os_list(config)
            print("\nSelect OS:")
            for i, os_name in enumerate(os_list, 1):
                print(f"{i}) {os_name}")
            print("0) Cancel")
            
            os_choice = input("\nChoice: ").strip()
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
            
            # Load current config
            os_config_path = REPO_ROOT / "config" / "os" / f"{selected_os}.json"
            with os_config_path.open("r", encoding="utf-8") as f:
                os_cfg = json.load(f)
            
            print(f"\n[Configure {selected_os}]")
            print("Press Enter to keep current value\n")
            
            # Min version
            current_min = os_cfg.get("min_version", "")
            new_min = input(f"Min version [{current_min}]: ").strip()
            if new_min:
                os_cfg["min_version"] = new_min
            
            # Max version
            current_max = os_cfg.get("max_version") or ""
            new_max = input(f"Max version [{current_max}]: ").strip()
            if new_max:
                os_cfg["max_version"] = new_max
            elif new_max == "-":
                os_cfg["max_version"] = None
            
            # Selection policy
            current_policy = os_cfg.get("selection_policy", "explicit")
            new_policy = input(f"Selection policy (explicit/latest) [{current_policy}]: ").strip()
            if new_policy in ("explicit", "latest"):
                os_cfg["selection_policy"] = new_policy
            
            # Default arch
            current_arch = os_cfg.get("default_arch", "x86")
            new_arch = input(f"Default arch (x86/arm64) [{current_arch}]: ").strip()
            if new_arch:
                os_cfg["default_arch"] = new_arch
            
            # Enabled
            current_enabled = "yes" if os_cfg.get("enabled", True) else "no"
            new_enabled = input(f"Enabled (yes/no) [{current_enabled}]: ").strip().lower()
            if new_enabled in ("yes", "no"):
                os_cfg["enabled"] = new_enabled == "yes"
            
            # Save config
            with os_config_path.open("w", encoding="utf-8") as f:
                json.dump(os_cfg, f, indent=2, ensure_ascii=False)
            
            print(f"\n[OK] Configuration saved for {selected_os}")
            return 0
        
        else:
            print("Invalid choice")
            return 1
    
    except EOFError:
        print("Cancelled")
        return 0


def cmd_clean(config: dict, args) -> int:
    """Clean command - remove plans, cache, and downloaded images."""
    os_name = args.os
    
    # Interactive mode if no OS specified
    if not os_name:
        os_name = interactive_select_os(config, "Select target:")
        if os_name is None:
            print("Cancelled")
            return 0
    
    # Determine targets
    if os_name == "all":
        # Show what will be removed
        print("\n[WARNING] This will remove ALL plans, cache, and downloaded images!")
        print("Items to be removed:")
        
        state_root = REPO_ROOT / config.get("state_root", "state/sync/plans")
        cache_root = REPO_ROOT / config.get("cache_root", "cache/official")
        
        if state_root.exists():
            plan_count = sum(1 for d in state_root.iterdir() if d.is_dir())
            print(f"  - {plan_count} plan(s) from {state_root}")
        
        if cache_root.exists():
            print(f"  - All cached images from {cache_root}")
        
        try:
            confirm = input("\nType 'YES' to confirm: ").strip()
            if confirm != "YES":
                print("Cancelled")
                return 0
        except EOFError:
            print("Cancelled")
            return 0
        
        # Perform cleanup
        import shutil
        
        removed_plans = 0
        if state_root.exists():
            for plan_dir in state_root.iterdir():
                if plan_dir.is_dir():
                    shutil.rmtree(plan_dir)
                    removed_plans += 1
        
        removed_cache = False
        if cache_root.exists():
            shutil.rmtree(cache_root)
            removed_cache = True
        
        print(f"\n[Clean Complete]")
        print(f"  Removed {removed_plans} plan(s)")
        print(f"  Cache cleared: {removed_cache}")
        return 0
    
    else:
        # Single OS cleanup
        try:
            os_name = canonical_os(config, os_name)
        except ValueError as e:
            print(f"[ERROR] {e}", file=sys.stderr)
            return 1
        
        print(f"\n[Clean] {os_name}")
        print("1) all versions")
        print("2) select version")
        print("0) Cancel")
        
        try:
            choice = input("\nChoice: ").strip()
            if choice == "0":
                print("Cancelled")
                return 0
            
            if choice == "1":
                # Clean all versions for this OS
                version_choice = "all"
            elif choice == "2":
                # Select specific version
                versions = get_os_versions(config, os_name)
                print(f"\nSelect version:")
                for i, version in enumerate(versions, 1):
                    print(f"{i}) {version}")
                print("0) Cancel")
                
                v_choice = input("\nChoice: ").strip()
                if v_choice == "0":
                    print("Cancelled")
                    return 0
                
                try:
                    idx = int(v_choice) - 1
                    if 0 <= idx < len(versions):
                        version_choice = versions[idx]
                    else:
                        print("Invalid choice")
                        return 1
                except ValueError:
                    print("Invalid input")
                    return 1
            else:
                print("Invalid choice")
                return 1
        
        except EOFError:
            print("Cancelled")
            return 0
        
        # Show what will be removed
        plans = get_available_plans(config)
        cache_root = REPO_ROOT / config.get("cache_root", "cache/official")
        
        items_to_remove = []
        
        if os_name in plans:
            if version_choice == "all":
                for version in plans[os_name]:
                    for plan_info in plans[os_name][version]:
                        plan_path = REPO_ROOT / plan_info["plan_file"]
                        if plan_path.exists():
                            items_to_remove.append(("plan", str(plan_path.parent.relative_to(REPO_ROOT))))
                        # Check for cached files
                        cache_path = cache_root / os_name / plans[os_name][version][0].get("release_name", version)
                        if cache_path.exists():
                            items_to_remove.append(("cache", str(cache_path.relative_to(REPO_ROOT))))
            else:
                if version_choice in plans[os_name]:
                    for plan_info in plans[os_name][version_choice]:
                        plan_path = REPO_ROOT / plan_info["plan_file"]
                        if plan_path.exists():
                            items_to_remove.append(("plan", str(plan_path.parent.relative_to(REPO_ROOT))))
        
        if not items_to_remove:
            print(f"\n[INFO] No items found to clean for {os_name}")
            return 0
        
        print(f"\nItems to be removed:")
        for item_type, item_path in items_to_remove:
            print(f"  [{item_type}] {item_path}")
        
        try:
            confirm = input("\nProceed? [y/N]: ").strip().lower()
            if confirm != 'y':
                print("Cancelled")
                return 0
        except EOFError:
            print("Cancelled")
            return 0
        
        # Perform cleanup
        import shutil
        
        removed_count = 0
        for item_type, item_path in items_to_remove:
            full_path = REPO_ROOT / item_path
            if full_path.exists():
                shutil.rmtree(full_path)
                removed_count += 1
        
        print(f"\n[Clean Complete]")
        print(f"  Removed {removed_count} item(s)")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Central Image CLI - Manage OS images across subsystems",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Commands:
  sync      Check targets, resolve sources, create/update plans (dry-run)
  pull      Download images from existing plans
  status    Show current status of all OS/versions
  setting   Configure per-OS behavior
  clean     Remove plans, cache, and downloaded images

Examples:
  image sync              # Interactive sync menu
  image sync ubuntu       # Sync all versions of Ubuntu
  image pull              # Interactive pull menu
  image status            # Show status table
  image setting           # Configure settings
  image clean             # Interactive clean menu
        """
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Sync command
    sync_parser = subparsers.add_parser("sync", help="Create/update plans (dry-run)")
    sync_parser.add_argument("os", nargs="?", help="OS to sync (or 'all')")
    
    # Pull command
    pull_parser = subparsers.add_parser("pull", help="Download images from plans")
    pull_parser.add_argument("os", nargs="?", help="OS to pull (or 'all')")
    pull_parser.add_argument("--version", help="Specific version to pull")
    
    # Status command
    subparsers.add_parser("status", help="Show current status")
    
    # Setting command
    subparsers.add_parser("setting", help="Configure per-OS settings")
    
    # Clean command
    clean_parser = subparsers.add_parser("clean", help="Remove plans and cache")
    clean_parser.add_argument("os", nargs="?", help="OS to clean (or 'all')")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 0
    
    try:
        config = load_config()
    except Exception as e:
        print(f"[ERROR] Failed to load config: {e}", file=sys.stderr)
        return 1
    
    # Route to appropriate command
    commands = {
        "sync": cmd_sync,
        "pull": cmd_pull,
        "status": cmd_status,
        "setting": cmd_setting,
        "clean": cmd_clean,
    }
    
    if args.command in commands:
        return commands[args.command](config, args)
    else:
        parser.print_help()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
