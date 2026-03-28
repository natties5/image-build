#!/usr/bin/env python3
import argparse
import hashlib
import html.parser
import json
import signal
import sys
import time
import urllib.error
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
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
CONFIG_PATH = REPO_ROOT / "config" / "sync-config.json"
CHUNK_SIZE = 4 * 1024 * 1024


class LinkParser(html.parser.HTMLParser):
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
    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_allowed_host(url: str, cfg: dict) -> None:
    host = urlparse(url).netloc
    if host not in cfg["allowed_hosts"]:
        raise RuntimeError(f"host not allowed: {host}")


def http_get_text(url: str, cfg: dict) -> str:
    ensure_allowed_host(url, cfg)
    req = urllib.request.Request(url, headers={"User-Agent": cfg["user_agent"]})
    with urllib.request.urlopen(req, timeout=cfg.get("request_timeout_seconds", 30)) as r:
        return r.read().decode("utf-8", errors="ignore")


def canonical_os(config: dict, os_name: str) -> str:
    value = os_name.strip().lower()
    if value not in config["default_os"]:
        raise ValueError(f"unsupported os: {os_name}")
    return value


def canonical_version(config: dict, os_name: str, version: str) -> str:
    value = version.strip().lower()
    os_cfg = config["default_os"][os_name]
    aliases = os_cfg.get("aliases", {})
    if value in aliases:
        return aliases[value]
    if value in os_cfg.get("sources", {}):
        return value
    raise ValueError(f"unsupported version for {os_name}: {version}")


def canonical_arch(config: dict, os_name: str, arch: str) -> str:
    value = arch.strip().lower()
    os_cfg = config["default_os"][os_name]
    arch_map = os_cfg.get("architectures", {})
    if value not in arch_map:
        raise ValueError(f"unsupported arch for {os_name}: {arch}")
    return arch_map[value]


def parse_listing_links(html_text: str) -> list[str]:
    parser = LinkParser()
    parser.feed(html_text)
    return parser.links


def strict_candidate_select(links: list[str], patterns: list[str], arch: str) -> str:
    candidates = []
    for link in links:
        name = link.strip()
        if not name:
            continue
        for pattern in patterns:
            if arch == "x86_64" and "amd64" not in pattern:
                continue
            if arch == "aarch64" and "arm64" not in pattern:
                continue
            if pattern in name:
                candidates.append(name)

    candidates = sorted(set(candidates))
    if len(candidates) != 1:
        raise RuntimeError(f"ambiguous candidates: {candidates}")
    return candidates[0]


def parse_checksum(checksum_text: str, filename: str) -> str:
    for line in checksum_text.splitlines():
        if filename not in line:
            continue
        parts = line.split()
        if not parts:
            continue
        return parts[0]
    raise RuntimeError(f"checksum not found for {filename}")


def file_digest(path: Path, algorithm: str) -> str:
    h = hashlib.new(algorithm)
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)


def append_jsonl(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def build_paths(cfg: dict, os_name: str, release_name: str, arch: str, artifact_type: str, cache_key: str, plan_id: str) -> dict:
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


def build_plan(cfg: dict, os_name: str, version: str, arch: str) -> dict:
    src = cfg["default_os"][os_name]["sources"][version]
    listing_url = src["listing_url"]
    listing_html = http_get_text(listing_url, cfg)
    links = parse_listing_links(listing_html)
    selected_filename = strict_candidate_select(links, src["filename_patterns"], arch)

    checksum_url = urljoin(listing_url, src["checksum_file"])
    checksum_text = http_get_text(checksum_url, cfg)
    checksum_value = parse_checksum(checksum_text, selected_filename)

    release_name = src["release_name"]
    artifact_type = src["artifact_type"]

    requested = {"os": os_name, "version": version, "arch": arch}
    plan_seed = json.dumps(requested, sort_keys=True).encode("utf-8")
    plan_id = hashlib.sha256(plan_seed).hexdigest()[:12]
    cache_key = hashlib.sha256(
        f"{os_name}|{version}|{arch}|{listing_url}|{selected_filename}|{checksum_value}".encode("utf-8")
    ).hexdigest()
    paths = build_paths(cfg, os_name, release_name, arch, artifact_type, cache_key, plan_id)

    paths["plan_dir"].mkdir(parents=True, exist_ok=True)
    paths["cache_dir"].mkdir(parents=True, exist_ok=True)
    paths["report_dir"].mkdir(parents=True, exist_ok=True)

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
            "artifact_type": artifact_type,
            "listing_url": listing_url,
            "checksum_url": checksum_url,
            "checksum_algorithm": src["checksum_algorithm"],
            "checksum_file": src["checksum_file"],
            "selected_filename": selected_filename,
            "download_url": urljoin(listing_url, selected_filename),
            "expected_checksum": checksum_value
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

    manifest = {
        "plan_id": plan_id,
        "summary": {
            "os": os_name,
            "version": version,
            "release_name": release_name,
            "arch": arch,
            "selected_filename": selected_filename,
            "download_url": plan["resolved"]["download_url"],
            "expected_checksum": checksum_value
        }
    }

    write_json(paths["plan_file"], plan)
    write_json(paths["manifest_file"], manifest)
    append_jsonl(paths["logs_file"], {"ts": utc_now(), "event": "dry_run_created", "plan_id": plan_id})
    append_jsonl(paths["global_log_file"], {"ts": utc_now(), "event": "dry_run_created", "plan_id": plan_id})
    return plan


def stream_download_with_progress(url: str, destination: Path, algorithm: str, cfg: dict, max_retries: int = 3) -> tuple[str, int]:
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
    """
    Check if cached metadata is stale compared to plan.
    Returns (is_stale, reason)
    """
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
            # Clean up stale cache files
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

    # Check for existing partial file and clean it
    if tmp_file.exists():
        print(f"[INFO] Cleaning up stale partial file: {tmp_file}")
        tmp_file.unlink()

    # Register signal handler for clean interrupt
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
    parser = argparse.ArgumentParser(description="sync image planner and downloader")
    parser.add_argument("os", nargs="?")
    parser.add_argument("version", nargs="?")
    parser.add_argument("arch", nargs="?", default="amd64")
    parser.add_argument("--execute", action="store_true", help="download using an existing plan")
    parser.add_argument("--plan-id", help="existing plan id for execute mode")
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
        version = canonical_version(cfg, os_name, args.version)
        arch = canonical_arch(cfg, os_name, args.arch)
    except ValueError as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        print(f"Supported OS: {', '.join(cfg.get('default_os', {}).keys())}", file=sys.stderr)
        return 1

    plan = build_plan(cfg, os_name, version, arch)
    print("[DRY-RUN OK]")
    print(json.dumps(plan, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
