#!/usr/bin/env python3
"""
Test ambiguity detection in candidate selection
"""
import sys
sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parent.parent))

from sync_image import strict_candidate_select

def test_ambiguity():
    # Test case 1: Multiple candidates matching same pattern (should fail)
    links = [
        "jammy-server-cloudimg-amd64.img",
        "jammy-server-cloudimg-amd64-disk1.img",  # Another match
        "SHA256SUMS"
    ]
    patterns = ["jammy-server-cloudimg-amd64"]
    
    try:
        result = strict_candidate_select(links, patterns, "x86_64")
        print(f"FAIL: Should reject ambiguity but got: {result}")
        return False
    except RuntimeError as e:
        if "ambiguous" in str(e).lower():
            print(f"PASS: Correctly rejected ambiguity: {e}")
            return True
        else:
            print(f"FAIL: Wrong error: {e}")
            return False

def test_no_candidates():
    # Test case 2: No candidates (should fail)
    links = ["SHA256SUMS", "other-file.txt"]
    patterns = ["nonexistent-pattern"]
    
    try:
        result = strict_candidate_select(links, patterns, "x86_64")
        print(f"FAIL: Should reject no candidates but got: {result}")
        return False
    except RuntimeError as e:
        if "ambiguous" in str(e).lower():
            print(f"PASS: Correctly rejected no candidates: {e}")
            return True
        else:
            print(f"FAIL: Wrong error: {e}")
            return False

def test_single_candidate():
    # Test case 3: Single candidate (should pass)
    links = [
        "jammy-server-cloudimg-amd64.img",
        "SHA256SUMS"
    ]
    patterns = ["jammy-server-cloudimg-amd64"]
    
    try:
        result = strict_candidate_select(links, patterns, "x86_64")
        if result == "jammy-server-cloudimg-amd64.img":
            print(f"PASS: Correctly selected single candidate: {result}")
            return True
        else:
            print(f"FAIL: Wrong selection: {result}")
            return False
    except RuntimeError as e:
        print(f"FAIL: Should accept single candidate but got: {e}")
        return False

if __name__ == "__main__":
    print("=== Ambiguity Detection Tests ===\n")
    
    results = []
    
    print("Test 1: Multiple candidates (ambiguity)...")
    results.append(("ambiguity", test_ambiguity()))
    
    print("\nTest 2: No candidates...")
    results.append(("no-candidates", test_no_candidates()))
    
    print("\nTest 3: Single candidate...")
    results.append(("single-candidate", test_single_candidate()))
    
    print("\n=== Summary ===")
    passed = sum(1 for _, r in results if r)
    total = len(results)
    print(f"Passed: {passed}/{total}")
    
    for name, result in results:
        status = "✓" if result else "✗"
        print(f"{status} {name}")
    
    sys.exit(0 if passed == total else 1)
