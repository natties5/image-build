# AIlogtest Index and Continuation Guide

Last updated: 2026-03-25
Purpose: make session history navigable, separate current truth from historical context.

## Read First (Current Truth Path)
1. `refactor_ols_removal_and_new_os_summary.md`
2. `rocky_8_9_10_repo_recovery_and_clean_summary.md`
3. `almalinux_8_9_10_repo_recovery_and_clean_summary.md`
4. `auto_discover_fix_summary.md`
5. `README.md` + `rebuild-project-doc/00_INDEX.md`

## Current Milestone Logs (Most Relevant)
- `refactor_ols_removal_and_new_os_summary.md`
  - Fedora sync fallback, Alpine/Arch additions, broad terminology cleanup milestone.
- `rocky_8_9_10_repo_recovery_and_clean_summary.md`
  - Rocky 8/9/10 recovery and clean-stage success context.
- `almalinux_8_9_10_repo_recovery_and_clean_summary.md`
  - AlmaLinux 8/9/10 recovery and clean-stage success context.

## Functional Feature Logs (Useful References)
- Sync and discovery:
  - `sync_test_summary.md`
  - `menu_sync_test_summary.md`
  - `auto_discover_summary.md`
  - `auto_discover_fix_summary.md`
  - `download_test_summary.md`
  - `download_progress_fix_summary.md`
- Settings/status/build UX:
  - `settings_menu_test_summary.md`
  - `settings_bugfix_summary.md`
  - `settings_ux_improvement_summary.md`
  - `status_menu_summary.md`
  - `build_menu_summary.md`
  - `guest_access_menu_summary.md`

## Historical / Superseded-Flow Logs
These are preserved for history but include old terminology (`OLS`, `LEGACY_MIRROR-first`, jump-host execution notes):
- `vault_logic_summary.md`
- `doc_vault_update_summary.md`
- `guest_configure_summary.md`
- `build_rocky9_summary.md`
- `build_almalinux9_summary.md`
- `rebuild_rocky_summary.md`
- `fix_repo_driver_summary.md`

Use them for timeline/context, not as current design source.

## Raw Runtime Logs
`AIlogtest/logs/*.log` stores command/runtime log artifacts from specific runs.

## Continuation Rules for Next Session
- Source of truth priority:
  1. `phases/*.sh`, `scripts/control.sh`
  2. `config/os/*`, `config/guest/*`
  3. `rebuild-project-doc/*`
  4. AIlogtest historical files
- If a summary conflicts with active scripts, trust script behavior.
- Treat legacy wording as historical unless verified in code.
