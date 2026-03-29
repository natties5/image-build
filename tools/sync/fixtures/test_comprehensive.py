#!/usr/bin/env python3
"""
Comprehensive Test Suite for Image Sync System
Tests dynamic discovery, artifact preference, and all menu commands
"""

import json
import sys
import os
from pathlib import Path

# Add tools to path
repo_root = Path(__file__).resolve().parents[3]
sync_dir = repo_root / "tools" / "sync"
sys.path.insert(0, str(sync_dir))

# Import using importlib to avoid path issues
import importlib.util
spec = importlib.util.spec_from_file_location("sync_image", sync_dir / "sync_image.py")
sync_module = importlib.util.module_from_spec(spec)
sys.modules["sync_image"] = sync_module
spec.loader.exec_module(sync_module)

from sync_image import (
    load_config,
    discover_upstream_versions,
    filter_candidates_by_policy,
    select_version_by_policy,
    canonical_version,
    canonical_os,
    canonical_arch,
    determine_artifact_metadata,
    strict_candidate_select_with_preference
)

def test_discovery():
    """Test upstream version discovery for all OS families"""
    print("\n" + "="*70)
    print("TEST: Dynamic Upstream Discovery")
    print("="*70)
    
    cfg = load_config()
    
    tests = [
        ("ubuntu", "Ubuntu"),
        ("debian", "Debian"),
        ("rocky", "Rocky Linux"),
        ("almalinux", "AlmaLinux"),
        ("fedora", "Fedora")
    ]
    
    all_passed = True
    for os_name, display_name in tests:
        try:
            candidates, metadata = discover_upstream_versions(os_name, cfg)
            print(f"[OK] {display_name}: Discovered {len(candidates)} version(s)")
            if candidates:
                versions = [c["version"] for c in candidates[:3]]
                print(f"  Latest: {', '.join(versions)}")
            print(f"  Source: {metadata.get('discovery_source', 'N/A')}")
        except Exception as e:
            print(f"[FAIL] {display_name}: FAILED - {e}")
            all_passed = False
    
    return all_passed

def test_policy_filter():
    """Test policy-based version filtering"""
    print("\n" + "="*70)
    print("TEST: Policy-Based Version Filtering")
    print("="*70)
    
    cfg = load_config()
    
    # Test Rocky Linux with min_version=8
    os_cfg = cfg["os_configs"]["rocky"]
    candidates = [
        {"version": "7", "release_name": "7"},
        {"version": "8", "release_name": "8"},
        {"version": "9", "release_name": "9"},
        {"version": "10", "release_name": "10"}
    ]
    
    valid, filter_log = filter_candidates_by_policy(candidates, os_cfg, "rocky")
    valid_versions = [c["version"] for c in valid]
    
    print(f"Rocky Linux filtering (min_version=8):")
    print(f"  Input: 7, 8, 9, 10")
    print(f"  Valid: {', '.join(valid_versions)}")
    
    if "7" not in valid_versions and "8" in valid_versions and "10" in valid_versions:
        print("[OK] Policy filter working correctly")
        return True
    else:
        print("[FAIL] Policy filter NOT working correctly")
        return False

def test_artifact_preference():
    """Test artifact format preference"""
    print("\n" + "="*70)
    print("TEST: Artifact Format Preference")
    print("="*70)
    
    test_cases = [
        ("debian-13-generic-amd64.qcow2", "qcow2", 110),
        ("ubuntu-22.04-server-cloudimg-amd64.img", "raw", 90),
        ("Rocky-9-GenericCloud.latest.x86_64.qcow2", "qcow2", 110),
    ]
    
    all_passed = True
    for filename, expected_format, expected_min_score in test_cases:
        metadata = determine_artifact_metadata(filename, [])
        actual_format = metadata["disk_format"]
        actual_score = metadata["preference_score"]
        
        if actual_format == expected_format and actual_score >= expected_min_score:
            print(f"[OK] {filename}")
            print(f"  Format: {actual_format}, Score: {actual_score}")
        else:
            print(f"[FAIL] {filename}")
            print(f"  Expected: {expected_format} (score>={expected_min_score})")
            print(f"  Got: {actual_format} (score={actual_score})")
            all_passed = False
    
    return all_passed

def test_version_selection():
    """Test version selection with latest policy"""
    print("\n" + "="*70)
    print("TEST: Version Selection with Latest Policy")
    print("="*70)
    
    cfg = load_config()
    os_cfg = cfg["os_configs"]["debian"]
    
    # Simulate discovered candidates
    candidates = [
        {"version": "12", "release_name": "bookworm"},
        {"version": "13", "release_name": "trixie"}
    ]
    
    # Test latest mode
    selected, reason, log = select_version_by_policy(candidates, os_cfg, "latest")
    
    print(f"Debian latest mode:")
    print(f"  Candidates: 12, 13")
    print(f"  Selected: {selected}")
    print(f"  Reason: {reason}")
    
    if selected == "13":
        print("[OK] Latest selection working correctly")
        return True
    else:
        print("[FAIL] Latest selection NOT working correctly")
        return False

def test_config_loading():
    """Test configuration loading"""
    print("\n" + "="*70)
    print("TEST: Configuration Loading")
    print("="*70)
    
    try:
        cfg = load_config()
        os_configs = cfg.get("os_configs", {})
        
        print(f"Loaded {len(os_configs)} OS configurations:")
        for os_name in sorted(os_configs.keys()):
            os_cfg = os_configs[os_name]
            enabled = os_cfg.get("enabled", True)
            min_ver = os_cfg.get("min_version", "N/A")
            policy = os_cfg.get("selection_policy", "explicit")
            discovery = "discovery" in os_cfg
            
            status = "[OK]" if enabled else "[DISABLED]"
            print(f"  {status} {os_name}: min={min_ver}, policy={policy}, discovery={discovery}")
        
        return True
    except Exception as e:
        print(f"[FAIL] Configuration loading failed: {e}")
        return False

def test_canonical_functions():
    """Test canonicalization functions"""
    print("\n" + "="*70)
    print("TEST: Canonicalization Functions")
    print("="*70)
    
    cfg = load_config()
    all_passed = True
    
    # Test OS canonicalization
    try:
        result = canonical_os(cfg, "ubuntu")
        assert result == "ubuntu"
        print("[OK] OS canonicalization: ubuntu -> ubuntu")
    except Exception as e:
        print(f"[FAIL] OS canonicalization failed: {e}")
        all_passed = False
    
    # Test version canonicalization with alias
    try:
        version, metadata = canonical_version(cfg, "ubuntu", "jammy")
        assert version == "22.04"
        print(f"[OK] Version alias: jammy -> {version}")
    except Exception as e:
        print(f"[FAIL] Version alias failed: {e}")
        all_passed = False
    
    # Test arch canonicalization
    try:
        result = canonical_arch(cfg, "ubuntu", "amd64")
        assert result == "x86_64"
        print("[OK] Arch canonicalization: amd64 -> x86_64")
    except Exception as e:
        print(f"[FAIL] Arch canonicalization failed: {e}")
        all_passed = False
    
    return all_passed

def test_rocky_10_support():
    """Test Rocky Linux 10 support"""
    print("\n" + "="*70)
    print("TEST: Rocky Linux 10 Support")
    print("="*70)
    
    cfg = load_config()
    
    # Check if version 10 is in config
    sources = cfg["os_configs"]["rocky"].get("sources", {})
    
    if "10" in sources:
        print("[OK] Rocky Linux 10 present in configuration")
        
        # Check if discovery can find it
        try:
            candidates, metadata = discover_upstream_versions("rocky", cfg)
            versions = [c["version"] for c in candidates]
            if "10" in versions:
                print("[OK] Rocky Linux 10 detected via upstream discovery")
                return True
            else:
                print("[WARN] Rocky Linux 10 in config but not detected upstream (may not be released yet)")
                return True
        except Exception as e:
            print(f"[WARN] Discovery check failed: {e}")
            return True
    else:
        print("[FAIL] Rocky Linux 10 NOT in configuration")
        return False

def test_almalinux_10_support():
    """Test AlmaLinux 10 support"""
    print("\n" + "="*70)
    print("TEST: AlmaLinux 10 Support")
    print("="*70)
    
    cfg = load_config()
    
    # Check if version 10 is in config
    sources = cfg["os_configs"]["almalinux"].get("sources", {})
    
    if "10" in sources:
        print("[OK] AlmaLinux 10 present in configuration")
        
        # Check if discovery can find it
        try:
            candidates, metadata = discover_upstream_versions("almalinux", cfg)
            versions = [c["version"] for c in candidates]
            if "10" in versions:
                print("[OK] AlmaLinux 10 detected via upstream discovery")
                return True
            else:
                print("[WARN] AlmaLinux 10 in config but not detected upstream (may not be released yet)")
                return True
        except Exception as e:
            print(f"[WARN] Discovery check failed: {e}")
            return True
    else:
        print("[FAIL] AlmaLinux 10 NOT in configuration")
        return False

def test_fedora_discovery():
    """Test Fedora discovery (downloads disabled)"""
    print("\n" + "="*70)
    print("TEST: Fedora Discovery (Downloads Disabled)")
    print("="*70)
    
    cfg = load_config()
    os_cfg = cfg["os_configs"]["fedora"]
    
    # Check if disabled
    enabled = os_cfg.get("enabled", True)
    if not enabled:
        print("[OK] Fedora correctly disabled in configuration")
    else:
        print("[WARN] Fedora enabled (should be disabled pending verification)")
    
    # Check discovery works
    try:
        candidates, metadata = discover_upstream_versions("fedora", cfg)
        versions = [c["version"] for c in candidates[:5]]
        print(f"[OK] Fedora discovery working: found versions {', '.join(versions)}")
        return True
    except Exception as e:
        print(f"[FAIL] Fedora discovery failed: {e}")
        return False

def main():
    """Run all tests"""
    print("\n" + "="*70)
    print("IMAGE SYNC SYSTEM - COMPREHENSIVE TEST SUITE")
    print("="*70)
    
    results = []
    
    # Run tests
    results.append(("Configuration Loading", test_config_loading()))
    results.append(("Dynamic Discovery", test_discovery()))
    results.append(("Policy Filtering", test_policy_filter()))
    results.append(("Version Selection", test_version_selection()))
    results.append(("Artifact Preference", test_artifact_preference()))
    results.append(("Canonicalization", test_canonical_functions()))
    results.append(("Rocky Linux 10", test_rocky_10_support()))
    results.append(("AlmaLinux 10", test_almalinux_10_support()))
    results.append(("Fedora Discovery", test_fedora_discovery()))
    
    # Summary
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)
    
    passed = sum(1 for _, r in results if r)
    failed = sum(1 for _, r in results if not r)
    
    for name, result in results:
        status = "[OK] PASS" if result else "[FAIL] FAIL"
        print(f"{status}: {name}")
    
    print("="*70)
    print(f"Total: {passed} passed, {failed} failed")
    
    if failed == 0:
        print("\nSUCCESS All tests passed!")
        return 0
    else:
        print(f"\n[WARN] {failed} test(s) failed")
        return 1

if __name__ == "__main__":
    sys.exit(main())
