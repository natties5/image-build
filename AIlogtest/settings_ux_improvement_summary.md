# Settings UX Improvement — Summary

Date: 2026-03-22T00:00:00+07:00
Branch: fix/fresh-clone-and-paths
Commit: 8519921 (pre-commit — new commit follows)

---

## Changes Made

### Change 1: Show list → type ID/name (all resource steps)

- All resource steps now show a **reference table** first (not a numbered pick list)
- User **types** a name or ID (free text), not a number
- Validates against list:
  - Exact match (case-insensitive) → resolves and saves both name and ID
  - Not found → prints warning but **accepts anyway** ("saving as-is")
- Empty Enter = **skip** (keeps existing saved value, prints "(kept: <value>)")
- Applied to: Project, Network, Flavor, Volume Type, Security Group, Floating Network

### Change 2: python3 detection fix (Windows MS Store stub)

- Added `_detect_python()` in `lib/common_utils.sh`
- Tests **actual execution** (`python -c "import sys; sys.exit(0)"`) not just `command -v`
- Respects `PYTHON3` env var set by `_setup_windows_python_path()` if already working
- `PYTHON3=$(_detect_python)` called once at the start of `_settings_select_resources()`
- If no working Python found:
  - `_print_ref_table` prints "(python not available — cannot display table)"
  - Network list uses project-scoped JSON only (no dedup merge)
  - Note printed: "network list may contain duplicates"
  - All other steps still work (just no table display)

### Change 3: SSH Public Key (OpenStack keypair)

- Added keypair selection step (2e.5) in `_settings_select_resources()`
- Fetches: `openstack_cmd keypair list -f json`
- Shows reference table: Name | Fingerprint
- Saved to: `KEY_NAME` in `settings/openstack.env`
- If skipped: `KEY_NAME=""` (will use password auth)
- `KEY_NAME=""` added to `settings/openstack.env.template` with comment
- `_settings_show()` now displays **SSH Keypair** field

### Security Group: client-side project filter

- Fetches **all** security groups (avoids `--project` flag that requires admin in some setups)
- Filters client-side by `OS_PROJECT_ID` match (via Python)
- If filtered result is empty → shows all (full-list fallback)

---

## Test Results

| Test | Description                        | Result    |
|------|------------------------------------|-----------|
| 1    | python detection — no Store trigger | WARN (no python in test env — expected) |
| 2    | table format in code                | PASS      |
| 3    | empty input = skip/keep             | PASS      |
| 4    | KEY_NAME in template                | PASS      |
| 5    | keypair list command                | PASS      |
| 6    | SSH Keypair in Show Settings        | PASS      |
| 7    | secgroup project filter             | PASS      |
| 8    | Settings box appears once           | PASS      |
| 9    | ShellCheck                          | WARN (not installed — bash -n syntax check: PASS) |

---

## Files Modified

| File | Change |
|------|--------|
| `scripts/control.sh` | Replaced `_settings_select_resources()` with table+type UX; added keypair step; updated `_settings_show()` for KEY_NAME |
| `lib/common_utils.sh` | Added `_detect_python()` function |
| `settings/openstack.env.template` | Added `KEY_NAME=""` with comment |
| `AIlogtest/settings_ux_improvement_summary.md` | This file |
