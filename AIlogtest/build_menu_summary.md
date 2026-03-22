# Build Menu — Implementation & Logic Test
Date: 2026-03-22T14:57:13Z
Branch: fix/fresh-clone-and-paths

## Menu Structure Implemented

```
--- Build ---
  1) Auto   — select OS  → run latest version
  2) Auto   — select OS  → run all versions
  3) Auto   — ALL OS, all versions
  4) Manual — select OS + version (full pipeline)
  5) Manual — select OS + version (step-by-step)
  6) Back
```

## Helper Functions

### In lib/common_utils.sh
- `_build_list_ready`: reads runtime/state/sync/*.json, checks for *.ready and *.dryrun-ok per entry
- `_build_latest_ready_version`: sort -V on ready entries → tail -1
- `_build_all_ready_versions`: sort -V all ready entries for a given OS

### In scripts/control.sh
- `_build_select_os`: numbered list with [ready: vX vY] / [not downloaded: vX] tags per OS
- `_build_select_version`: numbered list blocks dryrun-only entries with error + "Sync first" hint
- `_build_preflight`: 5-point check (openrc loaded / openstack.env / guest-access.env / sync .ready / guest config)
- `_build_run_pipeline`: runs 5 phases in order (import_base, create_vm, configure_guest, clean_guest, publish_final), stops on failure
- `_build_run_one_phase`: single phase with dependency guard (checks prior phase .ready)
- `_build_step_status`: shows ✓/✗/○ per phase (import/create/configure/clean/publish)
- `_menu_build_auto_os_latest`: select OS → auto latest version → preflight → pipeline
- `_menu_build_auto_os_all`: select OS → all ready versions → preflight each → pipeline each
- `_menu_build_auto_all`: all OS + all ready versions → preflight each → pipeline each
- `_menu_build_manual_full`: select OS + version → preflight → full pipeline
- `_menu_build_manual_step`: select OS + version → preflight → interactive step-by-step

## Sync ↔ Build Relationship
- Only `.ready` images appear as selectable in `_build_select_version`
- `.dryrun-ok` images show with "[not downloaded]" warning and are BLOCKED from pipeline
- No `.ready` and no `.dryrun-ok` = not shown at all in OS list
- `_build_preflight` also re-checks `.ready` before any pipeline run

## Windows Test State (runtime/state/sync)
- ubuntu 18.04: dryrun-only
- ubuntu 20.04: dryrun-only
- ubuntu 22.04: ready (fake .ready created for testing)
- ubuntu 24.04: ready (fake .ready created for testing)
- debian 12: dryrun-only
- fedora 41: dryrun-only
- almalinux 8: dryrun-only
- almalinux 9: dryrun-only
- rocky 8: dryrun-only
- rocky 9: dryrun-only

Note: On the Linux host (production), `.ready` files reflect actually downloaded images.

## Test Results

| Test | Description                      | Result    | Notes |
|------|----------------------------------|-----------|-------|
| 1    | Build menu appears               | PASS      | 6 options displayed correctly |
| 2    | _build_list_ready output         | PASS      | Returns "os ver status" lines |
| 3    | latest version detection         | PASS      | ubuntu 24.04 correctly selected |
| 4    | OS list shows status tags        | PASS      | [ready: 22.04 24.04] / [not downloaded: 12] |
| 5    | dryrun-only blocks pipeline      | PASS      | Pipeline NOT started for debian |
| 6    | preflight fails gracefully       | PASS      | "✗ settings/openstack.env missing" |
| 7    | step-by-step shows state icons   | PASS      | ○ import/create/configure/clean/publish |
| 8    | dependency check out-of-order    | PASS      | "✗ create not done yet" |
| 9    | ShellCheck                       | WARN      | shellcheck not available on Windows Git Bash |
