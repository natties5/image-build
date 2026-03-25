# Doc Update â€” Vault Fallback + Failure Behavior

> Historical Context Note
> This summary is preserved as a run record. Terminology and flow may be superseded by current code (see AIlogtest/00_INDEX.md and ebuild-project-doc/00_INDEX.md).

Date: 2026-03-22T00:00:00+07:00
Branch: fix/fresh-clone-and-paths

## Files Updated
| File | Changes |
|------|---------|
| 03_GUEST_OS_CONFIG_SYSTEM.md | vault flow, failure behavior, repo_mode values |
| 05_CONFIG_SCHEMA_REFERENCE.md | VAULT config fields, runtime JSON fields |
| config/guest/ubuntu/24.04.env | +3 VAULT lines |
| config/guest/ubuntu/default.env | +3 VAULT lines |
| config/guest/debian/12.env | +3 VAULT lines |
| config/guest/debian/default.env | +3 VAULT lines |
| config/guest/rocky/9.env | +3 VAULT lines |
| config/guest/rocky/default.env | +3 VAULT lines |
| config/guest/almalinux/9.env | +3 VAULT lines |
| config/guest/almalinux/default.env | +3 VAULT lines |
| config/guest/fedora/41.env | +3 VAULT lines |
| config/guest/fedora/default.env | +3 VAULT lines |

## New Repo Flow
official â†’ LEGACY_MIRROR â†’ vault â†’ official-fallback â†’ failed

## New Config Fields Added
- GUEST_ENABLE_VAULT_FALLBACK
- GUEST_VAULT_URL
- GUEST_VAULT_VALIDATION_COMMAND

## New Runtime JSON Fields
- repo_mode_used
- repo_mode_reason
- official_degraded
- legacy_mirror_attempted / vault_attempted
- failure_phase / failure_reason

## Vault URLs Per OS
| OS | Vault URL |
|----|-----------|
| ubuntu | old-releases.ubuntu.com |
| debian | archive.debian.org |
| rocky | dl.rockylinux.org/vault/rocky |
| almalinux | repo.almalinux.org/vault |
| fedora | archives.fedoraproject.org |

