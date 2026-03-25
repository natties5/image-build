# Vault Logic Implementation â€” configure_guest.sh

> Historical Context Note
> This summary is preserved as a run record. Terminology and flow may be superseded by current code (see AIlogtest/00_INDEX.md and ebuild-project-doc/00_INDEX.md).

Date: 2026-03-22T17:51:15Z
Branch: fix/fresh-clone-and-paths

## What Changed
File: phases/configure_guest.sh

### New tracking variables
- _REPO_MODE_USED, _REPO_MODE_REASON
- _LEGACY_MIRROR_ATTEMPTED, _LEGACY_MIRROR_REACHABLE
- _VAULT_ATTEMPTED, _VAULT_REACHABLE
- _OFFICIAL_DEGRADED

### Phase 5 â€” new flow
official â†’ LEGACY_MIRROR â†’ vault â†’ official-fallback â†’ failed

### Phase 5b (NEW) â€” Vault Injection
- triggered when: LEGACY_MIRROR fails OR LEGACY_MIRROR unreachable
- checks GUEST_VAULT_URL reachable via curl
- injects vault URL for apt (sources.list + .sources) OR dnf (*.repo)
- validates with GUEST_VAULT_VALIDATION_COMMAND
- rollback to backup if vault validation fails

### Phase 5c (NEW) â€” Official Last Resort
- triggered when: both LEGACY_MIRROR and vault failed
- re-tests official repo one more time
- if fails â†’ repo_mode=failed â†’ pipeline STOP

### JSON output new fields
repo_mode_used, repo_mode_reason,
official_degraded, legacy_mirror_attempted, legacy_mirror_reachable,
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
| official | normal â€” LEGACY_MIRROR disabled or skipped |
| ols | LEGACY_MIRROR mirror used successfully |
| vault | LEGACY_MIRROR failed â€” vault used |
| official-fallback | LEGACY_MIRROR+vault failed â€” back to official |
| failed | all options exhausted â€” pipeline stopped |

