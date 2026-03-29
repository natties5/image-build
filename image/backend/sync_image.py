#!/usr/bin/env python3
"""
Sync Image System - Enhanced with Dynamic Upstream Discovery

This module provides image synchronization with:
- Dynamic upstream version discovery from official sources
- Policy-driven version filtering (min_version, max_version, selection_policy)
- Artifact format preference (qcow2 over img)
- Comprehensive evidence logging
- Plan-driven execution
"""

import argparse
import hashlib
import html.parser
import json
import re
import signal
import sys
import time
import urllib.error
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from urllib.parse import urljoin, urlparse


class DownloadInterruptedError(Exception):
    """Raised when download is interrupted by user or signal"""
    pass


# Global flag for signal handling
_interrupted = False


def _signal_handler(signum, frame):
    global _interrupted
    _interrupted = True
    print("\n[INTERRUPTED] Cleaning up...", file=sys.stderr)


@contextmanager
def download_cleanup_context(tmp_file: Path):
    """Context manager that cleans up partial file on failure or interrupt"""
    global _interrupted
    try:
        yield
    except (DownloadInterruptedError, KeyboardInterrupt):
        print(f"\n[CLEANUP] Removing partial file: {tmp_file}")
        if tmp_file.exists():
            tmp_file.unlink()
        raise
    except Exception:
        print(f"\n[CLEANUP] Removing partial file due to error: {tmp_file}")
        if tmp_file.exists():
            tmp_file.unlink()
        raise


REPO_ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = REPO_ROOT / "image" / "config" / "sync-config.json"
OS_CONFIG_DIR = REPO_ROOT / "image" / "config" / "os"
CHUNK_SIZE = 4 * 1024 * 1024


class LinkParser(html.parser.HTMLParser):
    """Parse HTML links from directory listings"""
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "a":
            return
        href = dict(attrs).get("href")
        if href:
            self.links.append(href)


def load_config() -> dict:
    """Load global config and merge with all per-OS configs from config/os/"""
    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        cfg = json.load(f)
    
    # Load per-OS configs
    cfg["os_configs"] = {}
    if OS_CONFIG_DIR.exists():
        for os_file in OS_CONFIG_DIR.glob("*.json"):
            with os_file.open("r", encoding="utf-8") as f:
                os_cfg = json.load(f)
                os_name = os_cfg.get("os")
                if os_name:
                    cfg["os_configs"][os_name] = os_cfg
    
    return cfg


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_allowed_host(url: str, cfg: dict) -> None:
    host = urlparse(url).netloc
    if host not in cfg["allowed_hosts"]:
        raise RuntimeError(f"host not allowed: {host}")


def http_get_text(url: str, cfg: dict, timeout: Optional[int] = None) -> str:
    """Fetch text content from URL with error handling"""
    ensure_allowed_host(url, cfg)
    req = urllib.request.Request(url, headers={"User-Agent": cfg["user_agent"]})
    actual_timeout = timeout or cfg.get("request_timeout_seconds", 30)
    try:
        with urllib.request.urlopen(req, timeout=actual_timeout) as r:
            return r.read().decode("utf-8", errors="ignore")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} when fetching {url}: {e.reason}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"URL error when fetching {url}: {e.reason}")
    except TimeoutError:
        raise RuntimeError(f"Timeout when fetching {url} (timeout={actual_timeout}s)")


def canonical_os(config: dict, os_name: str) -> str:
    """Normalize OS name to canonical form"""
    value = os_name.strip().lower()
    if value not in config["os_configs"]:
        raise ValueError(f"unsupported os: {os_name}")
    return value


def _compare_versions(version1: str, version2: str) -> int:
    """Compare two versions. Returns -1 if v1 < v2, 0 if equal, 1 if v1 > v2"""
    try:
        # Try float comparison first (Ubuntu-style: 20.04, 22.04)
        if "." in str(version1) or "." in str(version2):
            v1 = float(version1)
            v2 = float(version2)
        else:
            # Integer comparison (Debian/Rocky/AlmaLinux-style: 12, 13, 8, 9)
            v1 = int(version1)
            v2 = int(version2)
        if v1 < v2:
            return -1
        elif v1 > v2:
            return 1
        return 0
    except ValueError:
        # Fall back to string comparison
        if str(version1) < str(version2):
            return -1
        elif str(version1) > str(version2):
            return 1
        return 0


def _check_version_bounds(version: str, min_version: str, max_version: Optional[str], os_name: str) -> None:
    """Check if version is within bounds (min_version <= version <= max_version if max_version exists)"""
    if min_version and _compare_versions(version, min_version) < 0:
        raise ValueError(f"version {version} is below minimum supported version {min_version} for {os_name}")
    
    if max_version is not None and _compare_versions(version, max_version) > 0:
        raise ValueError(f"version {version} is above maximum supported version {max_version} for {os_name}")


# ============================================================================
# UPSTREAM VERSION DISCOVERY
# ============================================================================

def _discover_ubuntu_versions(cfg: dict) -> tuple[list, dict]:
    """
    Discover Ubuntu versions from official cloud-images site.
    Returns: (candidates, discovery_metadata)
    """
    discovery_url = "https://cloud-images.ubuntu.com/"
    discovery_log = []
    candidates = []
    
    try:
        html = http_get_text(discovery_url, cfg, timeout=30)
        parser = LinkParser()
        parser.feed(html)
        
        # Ubuntu uses release codenames as directories
        # Look for LTS releases: focal (20.04), jammy (22.04), noble (24.04)
        release_patterns = {
            "focal": "20.04",
            "jammy": "22.04",
            "noble": "24.04",
            "oracular": "24.10",
        }
        
        for link in parser.links:
            link = link.rstrip("/")
            if link in release_patterns:
                version = release_patterns[link]
                candidates.append({
                    "version": version,
                    "release_name": link,
                    "discovery_source": discovery_url,
                    "discovery_method": "html_directory_listing"
                })
                discovery_log.append({
                    "version": version,
                    "release_name": link,
                    "source_url": discovery_url,
                    "status": "discovered"
                })
        
    except Exception as e:
        discovery_log.append({
            "source_url": discovery_url,
            "status": "discovery_failed",
            "error": str(e)
        })
    
    # Sort by version descending
    candidates.sort(key=lambda x: float(x["version"]) if "." in x["version"] else int(x["version"]), reverse=True)
    
    metadata = {
        "discovery_source": discovery_url,
        "discovery_method": "html_directory_listing",
        "discovery_log": discovery_log,
        "raw_candidates_found": len(candidates)
    }
    
    return candidates, metadata


def _discover_debian_versions(cfg: dict) -> tuple[list, dict]:
    """
    Discover Debian versions from official cloud.debian.org.
    Returns: (candidates, discovery_metadata)
    """
    discovery_url = "https://cloud.debian.org/images/cloud/"
    discovery_log = []
    candidates = []
    
    try:
        html = http_get_text(discovery_url, cfg, timeout=30)
        parser = LinkParser()
        parser.feed(html)
        
        # Debian uses release names as directories
        release_patterns = {
            "bookworm": "12",
            "trixie": "13",
            "sid": "unstable"
        }
        
        for link in parser.links:
            link = link.rstrip("/")
            if link in release_patterns:
                version = release_patterns[link]
                candidates.append({
                    "version": version,
                    "release_name": link,
                    "discovery_source": discovery_url,
                    "discovery_method": "html_directory_listing"
                })
                discovery_log.append({
                    "version": version,
                    "release_name": link,
                    "source_url": discovery_url,
                    "status": "discovered"
                })
        
    except Exception as e:
        discovery_log.append({
            "source_url": discovery_url,
            "status": "discovery_failed",
            "error": str(e)
        })
    
    # Sort by version descending (handle "unstable" specially)
    def version_key(x):
        v = x["version"]
        if v == "unstable":
            return 999
        return int(v) if v.isdigit() else float(v)
    
    candidates.sort(key=version_key, reverse=True)
    
    metadata = {
        "discovery_source": discovery_url,
        "discovery_method": "html_directory_listing",
        "discovery_log": discovery_log,
        "raw_candidates_found": len(candidates)
    }
    
    return candidates, metadata


def _discover_rocky_versions(cfg: dict) -> tuple[list, dict]:
    """
    Discover Rocky Linux versions from official download site.
    Returns: (candidates, discovery_metadata)
    """
    discovery_url = "https://download.rockylinux.org/pub/rocky/"
    discovery_log = []
    candidates = []
    
    try:
        html = http_get_text(discovery_url, cfg, timeout=30)
        parser = LinkParser()
        parser.feed(html)
        
        # Look for version directories (8, 9, 10, etc.)
        version_pattern = re.compile(r'^([0-9]+)/?$')
        
        for link in parser.links:
            match = version_pattern.match(link)
            if match:
                version = match.group(1)
                candidates.append({
                    "version": version,
                    "release_name": version,
                    "discovery_source": discovery_url,
                    "discovery_method": "html_directory_listing"
                })
                discovery_log.append({
                    "version": version,
                    "source_url": discovery_url,
                    "status": "discovered"
                })
        
    except Exception as e:
        discovery_log.append({
            "source_url": discovery_url,
            "status": "discovery_failed",
            "error": str(e)
        })
    
    # Sort by version descending
    candidates.sort(key=lambda x: int(x["version"]), reverse=True)
    
    metadata = {
        "discovery_source": discovery_url,
        "discovery_method": "html_directory_listing",
        "discovery_log": discovery_log,
        "raw_candidates_found": len(candidates)
    }
    
    return candidates, metadata


def _discover_almalinux_versions(cfg: dict) -> tuple[list, dict]:
    """
    Discover AlmaLinux versions from official repo site.
    Returns: (candidates, discovery_metadata)
    """
    discovery_url = "https://repo.almalinux.org/almalinux/"
    discovery_log = []
    candidates = []
    
    try:
        html = http_get_text(discovery_url, cfg, timeout=30)
        parser = LinkParser()
        parser.feed(html)
        
        # Look for version directories (8, 9, 10, etc.)
        version_pattern = re.compile(r'^([0-9]+)/?$')
        
        for link in parser.links:
            match = version_pattern.match(link)
            if match:
                version = match.group(1)
                candidates.append({
                    "version": version,
                    "release_name": version,
                    "discovery_source": discovery_url,
                    "discovery_method": "html_directory_listing"
                })
                discovery_log.append({
                    "version": version,
                    "source_url": discovery_url,
                    "status": "discovered"
                })
        
    except Exception as e:
        discovery_log.append({
            "source_url": discovery_url,
            "status": "discovery_failed",
            "error": str(e)
        })
    
    # Sort by version descending
    candidates.sort(key=lambda x: int(x["version"]), reverse=True)
    
    metadata = {
        "discovery_source": discovery_url,
        "discovery_method": "html_directory_listing",
        "discovery_log": discovery_log,
        "raw_candidates_found": len(candidates)
    }
    
    return candidates, metadata


def _discover_fedora_versions(cfg: dict) -> tuple[list, dict]:
    """
    Discover Fedora versions from official release tree (automation-friendly path).
    Uses dl.fedoraproject.org which is more automation-friendly than download.fedoraproject.org.
    Returns: (candidates, discovery_metadata)
    """
    # Use the mirror/direct download path which is more automation-friendly
    discovery_url = "https://dl.fedoraproject.org/pub/fedora/linux/releases/"
    discovery_log = []
    candidates = []
    
    try:
        html = http_get_text(discovery_url, cfg, timeout=30)
        parser = LinkParser()
        parser.feed(html)
        
        # Look for version directories (39, 40, 41, etc.)
        version_pattern = re.compile(r'^([0-9]+)/?$')
        
        for link in parser.links:
            match = version_pattern.match(link)
            if match:
                version = match.group(1)
                # Fedora versions typically start from 20+ in modern era
                if int(version) >= 20:
                    candidates.append({
                        "version": version,
                        "release_name": version,
                        "discovery_source": discovery_url,
                        "discovery_method": "html_directory_listing"
                    })
                    discovery_log.append({
                        "version": version,
                        "source_url": discovery_url,
                        "status": "discovered"
                    })
        
    except Exception as e:
        discovery_log.append({
            "source_url": discovery_url,
            "status": "discovery_failed",
            "error": str(e)
        })
    
    # Sort by version descending
    candidates.sort(key=lambda x: int(x["version"]), reverse=True)
    
    metadata = {
        "discovery_source": discovery_url,
        "discovery_method": "html_directory_listing",
        "discovery_log": discovery_log,
        "raw_candidates_found": len(candidates)
    }
    
    return candidates, metadata


def discover_upstream_versions(os_name: str, cfg: dict) -> tuple[list, dict]:
    """
    Discover available versions from official upstream sources.
    Returns: (candidates, discovery_metadata)
    """
    discovery_functions = {
        "ubuntu": _discover_ubuntu_versions,
        "debian": _discover_debian_versions,
        "rocky": _discover_rocky_versions,
        "almalinux": _discover_almalinux_versions,
        "fedora": _discover_fedora_versions,
    }
    
    if os_name not in discovery_functions:
        return [], {"error": f"No upstream discovery available for {os_name}"}
    
    return discovery_functions[os_name](cfg)


def filter_candidates_by_policy(
    candidates: list,
    os_cfg: dict,
    os_name: str
) -> tuple[list, list]:
    """
    Filter discovered candidates by policy (min_version, max_version, enabled).
    Returns: (valid_candidates, filter_log)
    """
    min_version = os_cfg.get("min_version")
    max_version = os_cfg.get("max_version")
    enabled = os_cfg.get("enabled", True)
    
    valid_candidates = []
    filter_log = []
    
    if not enabled:
        filter_log.append({
            "status": "os_disabled",
            "reason": "OS is disabled in configuration"
        })
        return [], filter_log
    
    for candidate in candidates:
        version = candidate["version"]
        
        # Skip unstable/testing versions in production
        if version in ("unstable", "testing", "rawhide"):
            filter_log.append({
                "version": version,
                "status": "filtered",
                "reason": "unstable/testing releases excluded by policy"
            })
            continue
        
        try:
            # min_version is required per spec, but handle None gracefully
            effective_min = min_version if min_version is not None else "0"
            _check_version_bounds(version, effective_min, max_version, os_name)
            valid_candidates.append(candidate)
            filter_log.append({
                "version": version,
                "status": "valid",
                "reason": f"within bounds {effective_min}-{max_version or 'unlimited'}"
            })
        except ValueError as e:
            filter_log.append({
                "version": version,
                "status": "filtered",
                "reason": str(e)
            })
    
    return valid_candidates, filter_log


def select_version_by_policy(
    candidates: list,
    os_cfg: dict,
    requested_version: str
) -> tuple[Optional[str], str, list]:
    """
    Select version based on policy and request.
    Returns: (selected_version, selection_reason, selection_log)
    """
    selection_policy = os_cfg.get("selection_policy", "explicit")
    selection_log = []
    
    # Handle auto/latest mode
    if requested_version in ("auto", "latest"):
        if selection_policy not in ("latest", "auto"):
            return None, f"Auto/latest mode not supported (policy: {selection_policy})", selection_log
        
        if not candidates:
            return None, "No valid candidates found", selection_log
        
        # Sort candidates by version and pick the latest
        def version_key(x):
            v = x["version"]
            try:
                return float(v) if "." in v else int(v)
            except ValueError:
                return 0
        
        sorted_candidates = sorted(candidates, key=version_key, reverse=True)
        selected = sorted_candidates[0]
        
        min_version = os_cfg.get("min_version", "unknown")
        max_version = os_cfg.get("max_version")
        
        reason = f"latest valid version >= {min_version}"
        if max_version:
            reason += f" and <= {max_version}"
        
        selection_log.append({
            "requested": requested_version,
            "selected": selected["version"],
            "method": "latest_policy",
            "candidates_considered": len(candidates)
        })
        
        return selected["version"], reason, selection_log
    
    # Explicit mode - check if requested version exists in candidates
    for candidate in candidates:
        if candidate["version"] == requested_version:
            selection_log.append({
                "requested": requested_version,
                "selected": requested_version,
                "method": "explicit_match"
            })
            return requested_version, f"explicit version {requested_version}", selection_log
    
    # Check config sources as fallback
    sources = os_cfg.get("sources", {})
    if requested_version in sources:
        selection_log.append({
            "requested": requested_version,
            "selected": requested_version,
            "method": "explicit_config",
            "note": "version from static config (not discovered upstream)"
        })
        return requested_version, f"explicit version {requested_version} (from config)", selection_log
    
    return None, f"Version {requested_version} not found in discovered candidates or config", selection_log


def canonical_version(config: dict, os_name: str, version: str) -> tuple[str, dict]:
    """
    Resolve version to canonical form with dynamic discovery support.
    Returns: (canonical_version, version_metadata)
    """
    value = version.strip().lower()
    os_cfg = config["os_configs"][os_name]
    aliases = os_cfg.get("aliases", {})
    selection_policy = os_cfg.get("selection_policy", "explicit")
    
    # Initialize metadata
    metadata = {
        "requested_version": version,
        "selection_mode": "explicit",
        "upstream_discovery": {},
        "policy_filter": {},
        "version_selection": {},
        "resolved_from_alias": None
    }
    
    # Resolve alias first
    if value in aliases:
        resolved_alias = aliases[value]
        metadata["resolved_from_alias"] = value
        value = resolved_alias
    
    # Check if this OS supports upstream discovery
    discovery_enabled = os_name in ("ubuntu", "debian", "rocky", "almalinux", "fedora")
    
    if discovery_enabled:
        # Perform upstream discovery
        candidates, discovery_metadata = discover_upstream_versions(os_name, config)
        metadata["upstream_discovery"] = discovery_metadata
        
        # Filter by policy
        valid_candidates, filter_log = filter_candidates_by_policy(candidates, os_cfg, os_name)
        metadata["policy_filter"] = {
            "candidates_before_filter": len(candidates),
            "candidates_after_filter": len(valid_candidates),
            "filter_log": filter_log
        }
        
        # Select version based on policy
        selected_version, selection_reason, selection_log = select_version_by_policy(
            valid_candidates, os_cfg, value
        )
        
        metadata["version_selection"] = {
            "selected_version": selected_version,
            "selection_reason": selection_reason,
            "selection_log": selection_log
        }
        
        if selected_version:
            if value in ("auto", "latest"):
                metadata["selection_mode"] = value
            return selected_version, metadata
        else:
            # If discovery failed but we have config sources, fall back
            sources = os_cfg.get("sources", {})
            if value in sources:
                metadata["version_selection"]["fallback"] = "config_source"
                metadata["version_selection"]["warning"] = "Using config fallback, upstream discovery did not find this version"
                return value, metadata
            else:
                raise ValueError(f"Version {version} not found in upstream discovery or config for {os_name}")
    else:
        # No upstream discovery - use config only
        sources = os_cfg.get("sources", {})
        if value in sources:
            return value, metadata
        else:
            raise ValueError(f"unsupported version for {os_name}: {version}")


def canonical_arch(config: dict, os_name: str, arch: str) -> str:
    """Normalize architecture to canonical form"""
    value = arch.strip().lower()
    os_cfg = config["os_configs"][os_name]
    arch_map = os_cfg.get("architectures", {})
    if value not in arch_map:
        raise ValueError(f"unsupported arch for {os_name}: {arch}")
    return arch_map[value]


def parse_listing_links(html_text: str) -> list[str]:
    """Parse HTML to extract link hrefs"""
    parser = LinkParser()
    parser.feed(html_text)
    return parser.links


def determine_artifact_metadata(filename: str, patterns: list[str]) -> dict:
    """
    Determine artifact metadata from filename and patterns.
    Returns metadata including disk_format, artifact_type, preference_score.
    """
    metadata = {
        "source_filename": filename,
        "artifact_extension": Path(filename).suffix.lower(),
        "disk_format": "unknown",
        "artifact_type": "unknown",
        "preference_score": 0
    }
    
    # Determine disk format from extension
    ext = metadata["artifact_extension"]
    if ext == ".qcow2":
        metadata["disk_format"] = "qcow2"
        metadata["artifact_type"] = "disk_image"
        metadata["preference_score"] = 100  # Highest preference
    elif ext == ".img":
        metadata["disk_format"] = "raw"
        metadata["artifact_type"] = "disk_image"
        metadata["preference_score"] = 80
    elif ext == ".iso":
        metadata["disk_format"] = "iso"
        metadata["artifact_type"] = "installer"
        metadata["preference_score"] = 50
    elif ext == ".tar" or ext == ".tar.gz" or filename.endswith(".tar.xz"):
        metadata["disk_format"] = "tar"
        metadata["artifact_type"] = "archive"
        metadata["preference_score"] = 30
    elif ext == ".vmdk":
        metadata["disk_format"] = "vmdk"
        metadata["artifact_type"] = "disk_image"
        metadata["preference_score"] = 60
    elif ext == ".vdi":
        metadata["disk_format"] = "vdi"
        metadata["artifact_type"] = "disk_image"
        metadata["preference_score"] = 60
    
    # Check if filename indicates cloud-init or generic image (preferred)
    lower_filename = filename.lower()
    if "cloud" in lower_filename or "generic" in lower_filename:
        metadata["preference_score"] += 10
        metadata["image_variant"] = "cloud"
    
    return metadata


def strict_candidate_select_with_preference(
    links: list[str],
    patterns: list[str],
    arch: str
) -> tuple[str, dict]:
    """
    Select best candidate with artifact preference (qcow2 > img > others).
    Returns: (selected_filename, artifact_metadata)
    """
    candidates = []
    seen_filenames = set()
    
    for link in links:
        # Skip duplicates
        if link in seen_filenames:
            continue
        seen_filenames.add(link)
        name = link.strip()
        if not name:
            continue
        
        # Skip checksum and metadata files
        skip_extensions = ('.checksum', '.asc', '.sig', '.sha256', '.sha512', '.md5', '.txt')
        if any(name.lower().endswith(ext) for ext in skip_extensions):
            continue
        
        for pattern in patterns:
            # Check if pattern matches arch
            pattern_lower = pattern.lower()
            if arch == "x86_64":
                if not any(x in pattern_lower for x in ["amd64", "x86_64", "x64"]):
                    continue
            if arch == "aarch64":
                if not any(x in pattern_lower for x in ["arm64", "aarch64"]):
                    continue
            
            if pattern in name:
                metadata = determine_artifact_metadata(name, patterns)
                candidates.append({
                    "filename": name,
                    "pattern": pattern,
                    "metadata": metadata
                })
    
    if not candidates:
        raise RuntimeError(f"No candidates found matching patterns: {patterns}")
    
    # Sort by preference score (highest first)
    candidates.sort(key=lambda x: x["metadata"]["preference_score"], reverse=True)
    
    # If multiple candidates have the same top score, raise ambiguity error
    top_score = candidates[0]["metadata"]["preference_score"]
    top_candidates = [c for c in candidates if c["metadata"]["preference_score"] == top_score]
    
    if len(top_candidates) > 1:
        raise RuntimeError(f"Ambiguous candidates with same preference score ({top_score}): {[c['filename'] for c in top_candidates]}")
    
    selected = top_candidates[0]
    return selected["filename"], selected["metadata"]


def strict_candidate_select(links: list[str], patterns: list[str], arch: str) -> str:
    """Legacy function - delegates to new preference-aware version"""
    filename, _ = strict_candidate_select_with_preference(links, patterns, arch)
    return filename


def parse_checksum(checksum_text: str, filename: str) -> str:
    """Parse checksum from text for given filename"""
    for line in checksum_text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if filename not in line:
            continue
        
        # Handle "SHA256 (filename) = hash" format (Rocky/AlmaLinux)
        if line.startswith("SHA256 (") or line.startswith("SHA512 ("):
            parts = line.split()
            if len(parts) >= 4 and parts[1].startswith("("):
                return parts[-1]
        
        # Handle standard "hash filename" format (Ubuntu/Debian)
        parts = line.split()
        if len(parts) >= 2:
            # Check if first part looks like a hash
            potential_hash = parts[0]
            if len(potential_hash) in (32, 40, 64, 128):  # MD5, SHA1, SHA256, SHA512 lengths
                return potential_hash
    
    raise RuntimeError(f"Checksum not found for {filename}")


def file_digest(path: Path, algorithm: str) -> str:
    """Calculate file digest using specified algorithm"""
    h = hashlib.new(algorithm)
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: Path, payload: dict) -> None:
    """Write JSON payload to file with pretty formatting"""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)


def append_jsonl(path: Path, payload: dict) -> None:
    """Append JSON line to log file"""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def build_paths(
    cfg: dict,
    os_name: str,
    release_name: str,
    arch: str,
    artifact_type: str,
    cache_key: str,
    plan_id: str
) -> dict:
    """Build all necessary paths for plan execution"""
    plan_dir = REPO_ROOT / cfg["state_root"] / plan_id
    cache_dir = REPO_ROOT / cfg["cache_root"] / os_name / release_name / arch / artifact_type / cache_key[:16]
    
    return {
        "plan_dir": plan_dir,
        "plan_file": plan_dir / "plan.json",
        "run_file": plan_dir / "run.json",
        "manifest_file": plan_dir / "manifest.json",
        "logs_file": plan_dir / "logs.jsonl",
        "cache_dir": cache_dir,
        "report_dir": REPO_ROOT / cfg["report_root"],
        "global_log_file": REPO_ROOT / cfg["log_root"] / "sync.log.jsonl",
    }


def build_plan(cfg: dict, os_name: str, version: str, arch: str, version_metadata: dict) -> dict:
    """Build a sync plan for the specified OS/version/arch"""
    
    # Get source configuration
    os_cfg = cfg["os_configs"][os_name]
    sources = os_cfg.get("sources", {})
    
    # Check if we have a source for this version
    if version not in sources:
        raise ValueError(f"No source configuration for {os_name} version {version}")
    
    src = sources[version]
    listing_url = src["listing_url"]
    
    # Fetch listing
    listing_html = http_get_text(listing_url, cfg)
    links = parse_listing_links(listing_html)
    
    # Select candidate with preference
    selected_filename, artifact_metadata = strict_candidate_select_with_preference(
        links, src["filename_patterns"], arch
    )
    
    # Fetch and parse checksum
    checksum_url = urljoin(listing_url, src["checksum_file"])
    checksum_text = http_get_text(checksum_url, cfg)
    checksum_value = parse_checksum(checksum_text, selected_filename)
    
    # Build plan identity
    release_name = src.get("release_name", version)
    requested = {"os": os_name, "version": version, "arch": arch}
    plan_seed = json.dumps(requested, sort_keys=True).encode("utf-8")
    plan_id = hashlib.sha256(plan_seed).hexdigest()[:12]
    
    # Build cache key
    cache_key = hashlib.sha256(
        f"{os_name}|{version}|{arch}|{listing_url}|{selected_filename}|{checksum_value}".encode("utf-8")
    ).hexdigest()
    
    # Build paths
    paths = build_paths(cfg, os_name, release_name, arch, artifact_metadata["disk_format"], cache_key, plan_id)
    
    # Ensure directories exist
    paths["plan_dir"].mkdir(parents=True, exist_ok=True)
    paths["cache_dir"].mkdir(parents=True, exist_ok=True)
    paths["report_dir"].mkdir(parents=True, exist_ok=True)
    
    # Check cache status
    cache_file = paths["cache_dir"] / selected_filename
    cache_meta = paths["cache_dir"] / f"{selected_filename}.meta.json"
    cache_status = "MISS"
    
    if cache_file.exists() and cache_meta.exists():
        try:
            with cache_meta.open("r", encoding="utf-8") as f:
                meta = json.load(f)
            is_stale, stale_reason = check_cache_stale(meta, {
                "resolved": {
                    "expected_checksum": checksum_value,
                    "download_url": urljoin(listing_url, selected_filename),
                    "selected_filename": selected_filename
                }
            })
            if is_stale:
                cache_status = "STALE"
            else:
                cache_status = "HIT"
        except (json.JSONDecodeError, KeyError):
            cache_status = "INVALID"
    elif cache_file.exists() and not cache_meta.exists():
        cache_status = "INVALID"
    
    # Build the plan
    plan = {
        "plan_id": plan_id,
        "created_at": utc_now(),
        "phase_scope": "sync-only-phase-0-6",
        "input": requested,
        "resolved": {
            "os": os_name,
            "version": version,
            "release_name": release_name,
            "arch": arch,
            "artifact_type": artifact_metadata["disk_format"],
            "disk_format": artifact_metadata["disk_format"],
            "source_filename": selected_filename,
            "listing_url": listing_url,
            "checksum_url": checksum_url,
            "checksum_algorithm": src["checksum_algorithm"],
            "checksum_file": src["checksum_file"],
            "selected_filename": selected_filename,
            "download_url": urljoin(listing_url, selected_filename),
            "expected_checksum": checksum_value,
            "artifact_metadata": artifact_metadata
        },
        "paths": {
            "plan_dir": str(paths["plan_dir"].relative_to(REPO_ROOT)),
            "plan_file": str(paths["plan_file"].relative_to(REPO_ROOT)),
            "run_file": str(paths["run_file"].relative_to(REPO_ROOT)),
            "manifest_file": str(paths["manifest_file"].relative_to(REPO_ROOT)),
            "logs_file": str(paths["logs_file"].relative_to(REPO_ROOT)),
            "cache_dir": str(paths["cache_dir"].relative_to(REPO_ROOT)),
            "cache_file": str(cache_file.relative_to(REPO_ROOT)),
            "cache_meta": str(cache_meta.relative_to(REPO_ROOT)),
            "report_dir": str(paths["report_dir"].relative_to(REPO_ROOT)),
            "global_log_file": str(paths["global_log_file"].relative_to(REPO_ROOT))
        },
        "guards": {
            "dry_run_required_before_download": True,
            "strict_version_required": True,
            "checksum_required_for_download_phase": True,
            "re_resolve_on_execute_allowed": False,
            "host_allowlist_enforced": True
        },
        "status": {
            "phase_0_input_normalized": True,
            "phase_1_policy_loaded": True,
            "phase_2_source_discovery": "created",
            "phase_3_version_guard": "created",
            "phase_4_dry_run_plan": "created",
            "phase_5_cache": cache_status,
            "phase_6_download": "pending"
        }
    }
    
    # Add version selection metadata if available
    if version_metadata:
        plan["version_selection"] = version_metadata
    
    # Build manifest
    manifest = {
        "plan_id": plan_id,
        "summary": {
            "os": os_name,
            "version": version,
            "release_name": release_name,
            "arch": arch,
            "selected_filename": selected_filename,
            "download_url": plan["resolved"]["download_url"],
            "expected_checksum": checksum_value,
            "disk_format": artifact_metadata["disk_format"],
            "artifact_type": artifact_metadata["artifact_type"]
        }
    }
    
    if version_metadata:
        manifest["summary"]["selection_mode"] = version_metadata.get("selection_mode", "explicit")
        if version_metadata.get("version_selection", {}).get("selection_reason"):
            manifest["summary"]["selection_reason"] = version_metadata["version_selection"]["selection_reason"]
        if version_metadata.get("upstream_discovery", {}).get("discovery_log"):
            manifest["summary"]["discovered_candidates"] = len(
                version_metadata["upstream_discovery"]["discovery_log"]
            )
    
    # Write plan files
    write_json(paths["plan_file"], plan)
    write_json(paths["manifest_file"], manifest)
    append_jsonl(paths["logs_file"], {"ts": utc_now(), "event": "dry_run_created", "plan_id": plan_id})
    append_jsonl(paths["global_log_file"], {"ts": utc_now(), "event": "dry_run_created", "plan_id": plan_id})
    
    return plan


def stream_download_with_progress(
    url: str,
    destination: Path,
    algorithm: str,
    cfg: dict,
    max_retries: int = 3
) -> tuple[str, int]:
    """Download file with progress reporting and retry logic"""
    ensure_allowed_host(url, cfg)
    
    last_exception = None
    for attempt in range(max_retries):
        if attempt > 0:
            print(f"\n[INFO] Retrying download (attempt {attempt + 1}/{max_retries})...")
        
        try:
            return _do_stream_download(url, destination, algorithm, cfg)
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
            last_exception = e
            print(f"\n[WARN] Download attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)  # Exponential backoff
            else:
                break
    
    raise RuntimeError(f"Download failed after {max_retries} attempts: {last_exception}")


def _do_stream_download(url: str, destination: Path, algorithm: str, cfg: dict) -> tuple[str, int]:
    """Internal download implementation with progress"""
    req = urllib.request.Request(url, headers={"User-Agent": cfg["user_agent"]})
    hasher = hashlib.new(algorithm)
    start_time = datetime.now(timezone.utc)

    with urllib.request.urlopen(req, timeout=cfg.get("request_timeout_seconds", 30)) as response:
        total = response.headers.get("Content-Length")
        total_bytes = int(total) if total else 0
        downloaded = 0
        last_percent = -1
        last_update_time = start_time
        last_downloaded = 0

        with destination.open("wb") as f:
            while True:
                chunk = response.read(CHUNK_SIZE)
                if not chunk:
                    break
                f.write(chunk)
                hasher.update(chunk)
                downloaded += len(chunk)

                now = datetime.now(timezone.utc)
                elapsed_since_update = (now - last_update_time).total_seconds()

                if total_bytes > 0:
                    percent = int(downloaded * 100 / total_bytes)
                    if percent != last_percent or elapsed_since_update >= 1.0:
                        mb = downloaded / (1024 * 1024)
                        total_mb = total_bytes / (1024 * 1024)

                        speed_mbps = 0
                        if elapsed_since_update > 0:
                            bytes_delta = downloaded - last_downloaded
                            speed_mbps = (bytes_delta / (1024 * 1024)) / elapsed_since_update

                        eta_str = ""
                        remaining = total_bytes - downloaded
                        if speed_mbps > 0 and remaining > 0:
                            eta_sec = remaining / (speed_mbps * 1024 * 1024)
                            eta_min = int(eta_sec // 60)
                            eta_sec_remain = int(eta_sec % 60)
                            eta_str = f" | ETA: {eta_min}m {eta_sec_remain}s"

                        print(
                            f"Downloading... {percent:3d}% "
                            f"({mb:.1f}/{total_mb:.1f} MB) "
                            f"@ {speed_mbps:.1f} MB/s{eta_str}",
                            end="\r",
                            flush=True,
                        )
                        last_percent = percent
                        last_update_time = now
                        last_downloaded = downloaded
                else:
                    if elapsed_since_update >= 1.0:
                        speed_mbps = 0
                        if elapsed_since_update > 0:
                            bytes_delta = downloaded - last_downloaded
                            speed_mbps = (bytes_delta / (1024 * 1024)) / elapsed_since_update
                        print(
                            f"Downloading... {downloaded:,} bytes @ {speed_mbps:.1f} MB/s",
                            end="\r",
                            flush=True,
                        )
                        last_update_time = now
                        last_downloaded = downloaded

    duration = (datetime.now(timezone.utc) - start_time).total_seconds()
    avg_speed = (downloaded / (1024 * 1024)) / duration if duration > 0 else 0
    print(" " * 100, end="\r")
    print(f"Download complete: {downloaded:,} bytes ({avg_speed:.1f} MB/s avg)")
    return hasher.hexdigest(), downloaded


def check_cache_stale(meta: dict, plan: dict) -> tuple[bool, str]:
    """Check if cached metadata is stale compared to plan"""
    expected_checksum = plan["resolved"]["expected_checksum"]
    expected_url = plan["resolved"]["download_url"]
    expected_filename = plan["resolved"]["selected_filename"]
    
    if meta.get("checksum") != expected_checksum:
        return True, "checksum_changed"
    
    if meta.get("source_url") != expected_url:
        return True, "source_url_changed"
    
    if meta.get("filename") != expected_filename:
        return True, "filename_changed"
    
    return False, ""


def execute_from_plan(cfg: dict, plan_id: str) -> dict:
    """Execute download from an existing plan"""
    global _interrupted
    
    plan_file = REPO_ROOT / cfg["state_root"] / plan_id / "plan.json"
    if not plan_file.exists():
        raise FileNotFoundError(f"plan not found: {plan_file}")

    with plan_file.open("r", encoding="utf-8") as f:
        plan = json.load(f)

    cache_file = REPO_ROOT / plan["paths"]["cache_file"]
    cache_meta = REPO_ROOT / plan["paths"]["cache_meta"]
    logs_file = REPO_ROOT / plan["paths"]["logs_file"]
    global_log = REPO_ROOT / plan["paths"]["global_log_file"]
    run_file = REPO_ROOT / plan["paths"]["run_file"]

    if plan["guards"]["dry_run_required_before_download"] is not True:
        raise RuntimeError("plan guard mismatch: dry_run_required_before_download")

    cache_status = "MISS"
    
    if cache_file.exists() and cache_meta.exists():
        with cache_meta.open("r", encoding="utf-8") as f:
            meta = json.load(f)
        
        is_stale, stale_reason = check_cache_stale(meta, plan)
        
        if is_stale:
            cache_status = "STALE"
            print(f"[INFO] Cache is STALE ({stale_reason}), re-downloading...")
            if cache_file.exists():
                cache_file.unlink()
            if cache_meta.exists():
                cache_meta.unlink()
            append_jsonl(logs_file, {"ts": utc_now(), "event": "cache_stale", "plan_id": plan_id, "reason": stale_reason})
            append_jsonl(global_log, {"ts": utc_now(), "event": "cache_stale", "plan_id": plan_id, "reason": stale_reason})
        elif meta.get("checksum") == plan["resolved"]["expected_checksum"]:
            cache_status = "HIT"
            run = {
                "plan_id": plan_id,
                "executed_at": utc_now(),
                "status": "cached",
                "file": str(cache_file.relative_to(REPO_ROOT)),
                "checksum": meta["checksum"],
                "bytes": cache_file.stat().st_size
            }
            write_json(run_file, run)
            append_jsonl(logs_file, {"ts": utc_now(), "event": "cache_hit", "plan_id": plan_id})
            append_jsonl(global_log, {"ts": utc_now(), "event": "cache_hit", "plan_id": plan_id})
            return run

    cache_file.parent.mkdir(parents=True, exist_ok=True)
    tmp_file = cache_file.with_suffix(cache_file.suffix + ".partial")

    if tmp_file.exists():
        print(f"[INFO] Cleaning up stale partial file: {tmp_file}")
        tmp_file.unlink()

    old_sigint = signal.signal(signal.SIGINT, _signal_handler)

    try:
        with download_cleanup_context(tmp_file):
            actual_checksum, total_bytes = stream_download_with_progress(
                url=plan["resolved"]["download_url"],
                destination=tmp_file,
                algorithm=plan["resolved"]["checksum_algorithm"],
                cfg=cfg,
            )

            if _interrupted:
                raise DownloadInterruptedError("Download interrupted by user")

        expected_checksum = plan["resolved"]["expected_checksum"]
        if actual_checksum.lower() != expected_checksum.lower():
            tmp_file.unlink(missing_ok=True)
            raise RuntimeError(f"checksum mismatch: expected {expected_checksum[:16]}..., got {actual_checksum[:16]}...")

        tmp_file.replace(cache_file)
        meta = {
            "plan_id": plan_id,
            "stored_at": utc_now(),
            "checksum_algorithm": plan["resolved"]["checksum_algorithm"],
            "checksum": actual_checksum,
            "source_url": plan["resolved"]["download_url"],
            "filename": plan["resolved"]["selected_filename"],
            "bytes": total_bytes
        }
        write_json(cache_meta, meta)

        run = {
            "plan_id": plan_id,
            "executed_at": utc_now(),
            "status": "downloaded",
            "file": str(cache_file.relative_to(REPO_ROOT)),
            "checksum": actual_checksum,
            "bytes": total_bytes
        }
        write_json(run_file, run)
        append_jsonl(logs_file, {"ts": utc_now(), "event": "downloaded", "plan_id": plan_id, "file": str(cache_file), "bytes": total_bytes})
        append_jsonl(global_log, {"ts": utc_now(), "event": "downloaded", "plan_id": plan_id, "bytes": total_bytes})
        return run
    finally:
        signal.signal(signal.SIGINT, old_sigint)


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync image planner and downloader")
    parser.add_argument("os", nargs="?")
    parser.add_argument("version", nargs="?")
    parser.add_argument("arch", nargs="?", default="amd64")
    parser.add_argument("--execute", action="store_true", help="Download using an existing plan")
    parser.add_argument("--plan-id", help="Existing plan id for execute mode")
    args = parser.parse_args()

    cfg = load_config()

    if args.execute:
        if not args.plan_id:
            print("[ERROR] --execute requires --plan-id", file=sys.stderr)
            print("Usage: sync_image.py --execute --plan-id <plan-id>", file=sys.stderr)
            return 1
        try:
            run = execute_from_plan(cfg, args.plan_id)
            print("[EXECUTE OK]")
            print(json.dumps(run, indent=2, ensure_ascii=False))
            return 0
        except FileNotFoundError as e:
            print(f"[ERROR] {e}", file=sys.stderr)
            print("Hint: Run dry-run first to create a plan", file=sys.stderr)
            return 1
        except RuntimeError as e:
            print(f"[ERROR] {e}", file=sys.stderr)
            return 1

    if not args.os or not args.version:
        parser.print_help()
        return 1

    try:
        os_name = canonical_os(cfg, args.os)
        version, version_metadata = canonical_version(cfg, os_name, args.version)
        arch = canonical_arch(cfg, os_name, args.arch)
    except ValueError as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        print(f"Supported OS: {', '.join(cfg.get('os_configs', {}).keys())}", file=sys.stderr)
        return 1

    plan = build_plan(cfg, os_name, version, arch, version_metadata)
    print("[DRY-RUN OK]")
    print(json.dumps(plan, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
