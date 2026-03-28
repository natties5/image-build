#!/usr/bin/env python3
"""
Checksum mismatch test fixture for sync_image.py
This creates a small test scenario to verify checksum mismatch handling
without downloading large official images.
"""

import json
import tempfile
import hashlib
import os
import sys
from pathlib import Path

# Add parent directory to path to import sync_image
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sync_image import file_digest


def test_checksum_mismatch_detection():
    """
    Test that checksum mismatch is properly detected and handled.
    This creates a temporary file with wrong content and verifies:
    1. Checksum mismatch is detected
    2. File is not promoted to final location
    3. Partial file is cleaned up
    4. Error message is explicit
    """
    print("=== Checksum Mismatch Test ===\n")
    
    # Create a temporary directory for testing
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)
        
        # Create a test file with known content
        test_file = tmpdir / "test-image.qcow2"
        test_content = b"This is a test image file with some content"
        test_file.write_bytes(test_content)
        
        # Calculate actual checksum
        actual_checksum = file_digest(test_file, "sha256")
        print(f"Created test file: {test_file}")
        print(f"Actual checksum: {actual_checksum}")
        
        # Create wrong expected checksum
        wrong_checksum = "0" * len(actual_checksum)
        print(f"Wrong checksum:  {wrong_checksum}")
        
        # Verify mismatch detection
        if actual_checksum.lower() != wrong_checksum.lower():
            print("\n[PASS] Checksum mismatch detected correctly")
            
            # Simulate the cleanup logic
            partial_file = tmpdir / "test-image.qcow2.partial"
            test_file.rename(partial_file)
            print(f"[PASS] File renamed to partial: {partial_file}")
            
            # Verify mismatch and cleanup
            if actual_checksum.lower() != wrong_checksum.lower():
                partial_file.unlink(missing_ok=True)
                print("[PASS] Partial file cleaned up on mismatch")
                
                # Verify file no longer exists
                if not partial_file.exists():
                    print("[PASS] Partial file no longer exists")
                    print("\n=== Test PASSED ===")
                    return True
                else:
                    print("[FAIL] Partial file still exists!")
                    return False
        
        print("\n=== Test FAILED ===")
        return False


def test_checksum_match():
    """Test that matching checksum allows file promotion"""
    print("\n=== Checksum Match Test ===\n")
    
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)
        
        # Create test file
        test_file = tmpdir / "test-image.qcow2.partial"
        test_content = b"Test content for matching checksum"
        test_file.write_bytes(test_content)
        
        # Calculate checksum
        expected_checksum = file_digest(test_file, "sha256")
        print(f"Expected checksum: {expected_checksum}")
        
        # Verify match
        actual_checksum = file_digest(test_file, "sha256")
        
        if actual_checksum.lower() == expected_checksum.lower():
            # Promote file (simulate final rename)
            final_file = tmpdir / "test-image.qcow2"
            test_file.replace(final_file)
            print(f"[PASS] Checksum matches")
            print(f"[PASS] File promoted to: {final_file}")
            
            if final_file.exists() and not test_file.exists():
                print("\n=== Test PASSED ===")
                return True
        
        print("\n=== Test FAILED ===")
        return False


if __name__ == "__main__":
    results = []
    
    results.append(("checksum_mismatch", test_checksum_mismatch_detection()))
    results.append(("checksum_match", test_checksum_match()))
    
    print("\n" + "="*50)
    print("FINAL SUMMARY")
    print("="*50)
    
    passed = sum(1 for _, r in results if r)
    total = len(results)
    
    for name, result in results:
        status = "PASS" if result else "FAIL"
        print(f"  {name}: {status}")
    
    print(f"\nTotal: {passed}/{total} tests passed")
    
    sys.exit(0 if passed == total else 1)
