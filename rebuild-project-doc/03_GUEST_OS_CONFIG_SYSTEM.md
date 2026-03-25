# 03 - Guest OS Config System (configure + clean)

Last updated: 2026-03-25
Primary sources:
- `phases/configure_guest.sh`
- `phases/clean_guest.sh`
- `config/guest/<os>/*.env`

## 1) Config Layering
For `--os <os> --version <ver>` the runtime loads:
1. `config/guest/<os>/default.env` (if present)
2. `config/guest/<os>/<ver>.env` (if present; overrides default)

## 2) Current Configure Flow
`configure_guest.sh` phase order (actual script):
1. Resolve config + runtime context
2. SSH preflight
3. Optional cloud-init wait
4. Baseline official repo test
5. Repo backup
6. Repo selection: official -> vault -> official-fallback
7. Update/upgrade
8. Package install
9. Optional reboot and SSH-down/SSH-up wait
10. Timezone/locale
11. cloud-init OpenStack config write
12. Disable auto updates
13. growpart check
14. Disable firewall
15. SELinux relabel (dnf-repo only)
16. SSH policy enforcement
17. Services enable/disable
18. Write configure state JSON + `.ready`

## 3) Repo Mode Semantics (Active)
`repo_mode_used` values currently emitted:
- `official`
- `vault`
- `official-fallback`
- `failed`

Related JSON booleans:
- `official_degraded`
- `vault_attempted`
- `vault_reachable`
- `vault_used`

## 4) Clean Flow
`clean_guest.sh` performs cleanup and then:
- restores official repo files from backup (`apt` or `dnf-repo` path)
- powers off via OpenStack API
- waits for server `SHUTOFF`
- writes clean state JSON + `.ready`

## 5) OS/Driver Notes
- Debian/Ubuntu flow uses `GUEST_REPO_DRIVER=apt`
- Rocky/AlmaLinux uses `GUEST_REPO_DRIVER=dnf-repo`
- Alpine/Arch guest defaults are present but should be treated as newer/less-validated in full pipeline history

## 6) Historical Terminology Clarification
- Old docs/logs describe a dedicated `LEGACY_MIRROR`/`ols` step.
- Current active script no longer uses that mode in main configure path.
- Keep old terms only when reading historical AI logs.
