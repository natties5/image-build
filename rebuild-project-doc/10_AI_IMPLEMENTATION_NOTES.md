# 10 - AI Implementation Notes (Current Session Baseline)

Last updated: 2026-03-25

## 1) Truth Source Priority
1. Active scripts in `phases/` and `scripts/control.sh`
2. Current config in `config/os` and `config/guest`
3. Runtime schema from `lib/state_store.sh` usage
4. README and `rebuild-project-doc`
5. AI logs (historical, may contain superseded behavior)

## 2) Terminology Constraints
- Current configure repo flow: official/vault/official-fallback
- Treat `OLS` and old LEGACY_MIRROR-first flow as historical context unless code explicitly uses it

## 3) Editing Rules for Future Sessions
- Prefer minimal diffs that align docs to code truth
- Mark historical logs clearly instead of rewriting history
- Keep local-workspace-first assumptions; avoid jump-host-centric instructions in current docs

## 4) Validation Checklist After Doc Changes
- `rg -n "OLS|ols" rebuild-project-doc README.md` should return no active-design usage
- docs mention Alpine/Arch and Fedora fallback where sync is described
- menu docs match current `scripts/control.sh` behavior
- repo mode docs match `configure_guest.sh` JSON fields

## 5) Handoff Pointer
Before any new architecture change, re-read:
1. `rebuild-project-doc/00_INDEX.md`
2. `rebuild-project-doc/06_OPENSTACK_PIPELINE_DESIGN.md`
3. `AIlogtest/00_INDEX.md`
