# Vault Logic Implementation — configure_guest.sh
Date: 2026-03-22T17:51:15Z
Branch: fix/fresh-clone-and-paths

## What Changed
File: phases/configure_guest.sh

### New tracking variables
- _REPO_MODE_USED, _REPO_MODE_REASON
- _OLS_ATTEMPTED, _OLS_REACHABLE
- _VAULT_ATTEMPTED, _VAULT_REACHABLE
- _OFFICIAL_DEGRADED

### Phase 5 — new flow
official → OLS → vault → official-fallback → failed

### Phase 5b (NEW) — Vault Injection
- triggered when: OLS fails OR OLS unreachable
- checks GUEST_VAULT_URL reachable via curl
- injects vault URL for apt (sources.list + .sources) OR dnf (*.repo)
- validates with GUEST_VAULT_VALIDATION_COMMAND
- rollback to backup if vault validation fails

### Phase 5c (NEW) — Official Last Resort
- triggered when: both OLS and vault failed
- re-tests official repo one more time
- if fails → repo_mode=failed → pipeline STOP

### JSON output new fields
repo_mode_used, repo_mode_reason,
official_degraded, ols_attempted, ols_reachable,
vault_attempted, vault_reachable

## Test Results
| Test | Description | Result |
|------|-------------|--------|
| 1 | tracking variables | PASS |
| 2 | vault injection code | PASS |
| 3 | official last resort | PASS |
| 4 | JSON new fields | PASS |
| 5 | git diff targeted | PASS |
| 6 | shellcheck | PASS (info only) |

## repo_mode_used values in production
| value | meaning |
|-------|---------|
| official | normal — OLS disabled or skipped |
| ols | OLS mirror used successfully |
| vault | OLS failed — vault used |
| official-fallback | OLS+vault failed — back to official |
| failed | all options exhausted — pipeline stopped |
