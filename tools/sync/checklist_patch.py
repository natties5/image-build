#!/usr/bin/env python3
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CHECKLIST_PATH = REPO_ROOT / "docs" / "checklist-current-plan.md"


def main() -> int:
    if not CHECKLIST_PATH.exists():
        raise FileNotFoundError(f"missing checklist file: {CHECKLIST_PATH}")

    content = CHECKLIST_PATH.read_text(encoding="utf-8")
    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())