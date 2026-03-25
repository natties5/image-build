# 01 - Start Project Blueprint (Current)

Last updated: 2026-03-25

## 1) Project Intent
Portable, menu-driven OpenStack image build pipeline using local scripts and repo-tracked config.

Core rule:
- Input config in `.env`
- Runtime outputs in `runtime/state/*.json` + flag files + `runtime/logs/*`

## 2) Top-Level Architecture
- Entrypoint: `scripts/control.sh`
- Shared libraries: `lib/`
- Phase scripts: `phases/`
- Tracked config: `config/os/*`, `config/guest/*`
- User/runtime settings: `settings/*.env` (gitignored)
- Runtime outputs: `runtime/`
- Downloaded images: `workspace/images/`

## 3) Active OS Matrix
Current sync/build menu paths include:
- ubuntu
- debian
- fedora
- rocky
- almalinux
- alpine
- arch

## 4) Phase Chain
Logical chain:
1. `sync_download`
2. `import_base`
3. `create_vm`
4. `configure_guest`
5. `clean_guest`
6. `publish_final`

## 5) Current Implementation Notes
- `sync_download.sh` is fully active with discovery + checksum validation.
- `import_base.sh`, `create_vm.sh`, `configure_guest.sh`, `clean_guest.sh`, `publish_final.sh` are implemented.
- Interactive Build menu in `scripts/control.sh` executes phases.
- Direct command `scripts/control.sh build ...` remains a placeholder (NOT IMPLEMENTED path in dispatcher).

## 6) Repo Mode Model (Current)
In active `configure_guest.sh`:
- Start with official repo validation
- If degraded and vault enabled: inject vault + validate
- If vault fails/unreachable: retry official as last resort
- Outcomes: `official`, `vault`, `official-fallback`, `failed`

`clean_guest.sh` restores official repo files from backup before capture/poweroff.

## 7) Historical Clarification
- Older design docs/logs mention `OLS` and `LEGACY_MIRROR` phase-first logic.
- Current active flow is vault-centric fallback as described above.

## 8) Source of Truth Priority
When docs conflict, trust in this order:
1. `phases/*.sh`
2. `scripts/control.sh`
3. `lib/*.sh`
4. `config/os/*` + `config/guest/*`
5. README and docs
6. AI logs (historical context)
