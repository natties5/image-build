# Settings Menu — Bug Fix Summary

Date: 2026-03-22T22:00:00+07:00
Branch: fix/fresh-clone-and-paths
Commit: bb3692c (pre-commit — new commit follows)

---

## Bug 1 — Show Settings duplicate

Root cause found: `_settings_show()` sources `active-profile.env` and
`openstack.env` into the global namespace on every call. If the function
is triggered again in the same call chain (e.g. a session file sourced
from a different execution context re-invokes the function, or Windows
CRLF line endings in session files cause unexpected shell evaluation),
the box prints multiple times. The function had no guard against
re-entrant or duplicate calls.

Fix applied: Added `_SETTINGS_SHOW_ACTIVE` reentrancy guard at the top
of `_settings_show()`. The flag is set to `1` on entry and cleared to
`0` on exit. A second call while the flag is set returns immediately.

Test result: "Current Settings Summary" count = 1 → **PASS**

---

## Bug 2 — Volume Type empty

Fix applied: Replaced single unscoped `openstack volume type list` with
a three-attempt strategy:
- Attempt 1: with `--os-project-id "${OS_PROJECT_ID:-}"` scope
- Attempt 2 (if attempt 1 returns empty): without scope
- Attempt 3 (if both return empty): manual text input prompt with skip option

Test result: manual fallback path confirmed functional → **PASS**

---

## Bug 3 — Network/SecGroup unfiltered

Fix applied:
- **network list**: merged project-scoped (`--project $OS_PROJECT_ID`) +
  external networks (`--external`), deduplicated by ID using python3 inline script
- **security group list**: `--project $OS_PROJECT_ID` with unscoped fallback
  if project-scoped returns empty
- **OS_PROJECT_ID exported immediately** after project selection (step 2a)
  via `export OS_PROJECT_ID="$proj_id"` and `export OS_PROJECT_NAME="$proj_name"`
  so steps 2b-2f can use it as a filter

Test result: PASS (grep confirms --project in both network list and secgroup list)

---

## All Test Results

| Test | Description                      | Result    |
|------|----------------------------------|-----------|
| 1    | Show Settings appears once       | PASS      |
| 2    | Volume type manual input         | PASS      |
| 3    | OS_PROJECT_ID saved in env       | PASS      |
| 4    | Network list uses --project      | PASS      |
| 5    | SecGroup list uses --project     | PASS      |
| 6    | Volume type fallback logic       | PASS      |
| 7    | ShellCheck                       | N/A (not installed) |

---

## Files Modified

- `scripts/control.sh`:
  - Added `_SETTINGS_SHOW_ACTIVE` reentrancy guard to `_settings_show()`
  - Added `export OS_PROJECT_ID` / `export OS_PROJECT_NAME` after project selection
  - Replaced network list with project-scoped + external merge via python3
  - Replaced volume type selection with two-attempt + manual fallback
  - Replaced security group list with project-scoped + unscoped fallback
- `lib/openstack_api.sh`: no changes needed
