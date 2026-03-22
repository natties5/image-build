# Auto-Promote Guest Config — Implementation Summary
Date: 2026-03-23T00:22:00Z
Branch: fix/fresh-clone-and-paths

## Logic Implemented
Location: lib/config_store.sh → _auto_promote_guest_config()
Triggered by: phases/publish_final.sh after publish.ready written

## Promote Rules
| Rule | Condition | Action |
|------|-----------|--------|
| 1 | publish.ready exists | required |
| 2 | version.env exists | required |
| 3 | default.env exists | required |
| 4 | version >= default | promote |
| 4 | version < default | skip (no downgrade) |
| 4 | version == default | update content |

## Examples
| Scenario | Result |
|----------|--------|
| default=24.04, run 26.04 passes | promote → default=26.04 |
| default=24.04, run 18.04 passes | skip (18.04 < 24.04) |
| default=24.04, run 24.04 passes | update default content (if different) |
| run 24.04 but no publish.ready | skip |

## Test Results
| Test | Description | Result |
|------|-------------|--------|
| 1 | function exists in config_store.sh | PASS |
| 2 | called from publish_final.sh + config_store sourced | PASS |
| 3 | newer version (26.04) promotes over 24.04 | PASS |
| 4 | older version (18.04) blocked by 24.04 | PASS |
| 5 | same version (24.04) would update content | PASS |
| 6 | dry-run promote 24.04 → unchanged (same content, no commit) | PASS |
| 7 | blocked when publish.ready missing | PASS |
| 8 | blocked when 18.04 < default 24.04 | PASS |
| 9 | shellcheck | WARN (shellcheck not installed on Windows Git Bash) |

## Changes Made
- **lib/config_store.sh**: added `_auto_promote_guest_config()` (lines 71–149)
- **phases/publish_final.sh**: sourced `config_store.sh`; calls auto-promote after `state_mark_ready`
