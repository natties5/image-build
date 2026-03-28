#!/usr/bin/env python3
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = REPO_ROOT / "config" / "sync-config.json"


def load_config() -> dict:
    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


def canonical_os(config: dict, os_name: str) -> str:
    value = os_name.strip().lower()
    if value in config["default_os"]:
        return value
    raise ValueError(f"unsupported os: {os_name}")


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


def build_plan(config: dict, os_name: str, version: str, arch: str) -> dict:
    src = config["default_os"][os_name]["sources"][version]
    release_name = src["release_name"]
    artifact_type = src["artifact_type"]
    listing_url = src["listing_url"]

    requested = {
        "os": os_name,
        "version": version,
        "arch": arch,
    }

    plan_seed = json.dumps(requested, sort_keys=True).encode("utf-8")
    plan_id = hashlib.sha256(plan_seed).hexdigest()[:12]
    cache_key = hashlib.sha256(
        f"{os_name}|{version}|{arch}|{listing_url}|{artifact_type}".encode("utf-8")
    ).hexdigest()[:16]

    state_root = Path(config["state_root"])
    plan_dir = REPO_ROOT / state_root / plan_id
    plan_dir.mkdir(parents=True, exist_ok=True)

    artifact_candidates = []
    for pattern in src["filename_patterns"]:
        if arch == "x86_64" and "amd64" in pattern:
            artifact_candidates.append(pattern)
        elif arch == "aarch64" and "arm64" in pattern:
            artifact_candidates.append(pattern)

    if not artifact_candidates:
        artifact_candidates = list(src["filename_patterns"])

    plan = {
        "plan_id": plan_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "phase_scope": "sync-only-phase-0-6",
        "input": requested,
        "resolved": {
            "os": os_name,
            "version": version,
            "release_name": release_name,
            "arch": arch,
            "artifact_type": artifact_type,
            "listing_url": listing_url,
            "checksum_file": src["checksum_file"],
            "filename_candidates": artifact_candidates,
            "selected_filename": artifact_candidates[0]
        },
        "paths": {
            "plan_dir": str(plan_dir.relative_to(REPO_ROOT)),
            "plan_file": str((plan_dir / "plan.json").relative_to(REPO_ROOT)),
            "run_file": str((plan_dir / "run.json").relative_to(REPO_ROOT)),
            "manifest_file": str((plan_dir / "manifest.json").relative_to(REPO_ROOT)),
            "logs_file": str((plan_dir / "logs.jsonl").relative_to(REPO_ROOT)),
            "cache_dir": f"cache/official/{os_name}/{release_name}/{arch}/{artifact_type}/{cache_key}",
            "report_dir": "reports/sync",
            "global_log_file": "logs/sync/sync.log.jsonl"
        },
        "guards": {
            "dry_run_required_before_download": True,
            "strict_version_required": True,
            "checksum_required_for_download_phase": True,
            "re_resolve_on_execute_allowed": False
        },
        "status": {
            "phase_0_input_normalized": True,
            "phase_1_policy_loaded": True,
            "phase_2_source_discovery": "planned",
            "phase_3_version_guard": "planned",
            "phase_4_dry_run_plan": "created",
            "phase_5_cache": "pending",
            "phase_6_download": "pending"
        }
    }

    with (plan_dir / "plan.json").open("w", encoding="utf-8") as f:
        json.dump(plan, f, indent=2, ensure_ascii=False)

    manifest = {
        "plan_id": plan_id,
        "summary": {
            "os": os_name,
            "version": version,
            "release_name": release_name,
            "arch": arch,
            "selected_filename": artifact_candidates[0],
            "listing_url": listing_url
        }
    }

    with (plan_dir / "manifest.json").open("w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    return plan


def main() -> int:
    parser = argparse.ArgumentParser(description="sync image dry-run planner")
    parser.add_argument("os", help="target os, e.g. ubuntu or debian")
    parser.add_argument("version", help="target version or alias, e.g. 22.04 or jammy")
    parser.add_argument("arch", nargs="?", default="amd64", help="target arch, default amd64")
    args = parser.parse_args()

    config = load_config()
    os_name = canonical_os(config, args.os)
    version = canonical_version(config, os_name, args.version)
    arch = canonical_arch(config, os_name, args.arch)

    plan = build_plan(config, os_name, version, arch)
    print("[DRY-RUN OK]")
    print(json.dumps(plan, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())