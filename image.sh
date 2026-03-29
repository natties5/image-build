#!/bin/sh
# Central Image CLI Entry Point
# Usage: image.sh <command> [options]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python "${SCRIPT_DIR}/image_cli.py" "$@"
