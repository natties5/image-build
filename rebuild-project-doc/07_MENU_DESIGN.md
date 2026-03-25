# 07 - Menu Design (Current Behavior)

Last updated: 2026-03-25
Primary source: `scripts/control.sh`

## 1) Main Menu
- Settings
- Sync
- Build
- Resume
- Status
- Cleanup
- Exit

## 2) Sync Menu
Implemented and active:
- dry-run all OS
- dry-run one OS
- download one OS+version
- download all versions in one OS
- download all OS
- show sync results

Supports OS set:
- ubuntu, debian, fedora, almalinux, rocky, alpine, arch

## 3) Build Menu
Interactive menu includes:
- auto latest per OS
- auto all versions per OS
- auto all OS
- manual full pipeline
- manual step-by-step

Build menu functions execute phase scripts.

## 4) Status Menu
Implemented:
- dashboard
- build state details
- log viewing

Reads from runtime state/log paths.

## 5) Settings Menu
Implemented flows include:
- OpenRC load/validate
- resource selection
- guest access edits
- settings show/validate helpers

## 6) Known Inconsistencies
- `dispatch_command build ...` is still placeholder and does not match interactive build capabilities.
- Resume/Cleanup include partial or placeholder behavior depending on subpath.

## 7) Terminology
Menu and status should present repo outcomes as:
- official
- vault
- official-fallback
- failed

Legacy `ols` wording should be treated as historical only.
