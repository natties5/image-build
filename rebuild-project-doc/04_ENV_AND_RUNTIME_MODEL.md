# 04 - Env and Runtime Model

Last updated: 2026-03-25

## 1) Input Categories
Tracked config:
- `config/os/<os>/sync.env`
- `config/guest/<os>/default.env`
- `config/guest/<os>/<version>.env`
- `config/guest/access.env`, `base.env`, `config.env`, `policy.env`

User/local settings (gitignored templates -> local files):
- `settings/openstack.env`
- `settings/guest-access.env`
- `settings/openrc-file/*`

## 2) Runtime Output Contract
Each phase writes:
- JSON manifest: `runtime/state/<phase>/<os>-<ver>.json`
- quick flag: `runtime/state/<phase>/<os>-<ver>.<flag>`
- log file: `runtime/logs/<phase>/<os>-<ver>.log`

Common flags:
- success: `.ready`
- dry-run success (sync): `.dryrun-ok`
- failure: `.failed`

## 3) State Dependencies
- `import` expects sync state/json
- `create` expects import ready/json
- `configure` expects create ready/json
- `clean` expects create ready/json (uses server/guest context)
- `publish` expects create ready/json (server+volume IDs)

## 4) Session/UI Runtime Files
- `runtime/session/active-profile.env`
- `runtime/state/*` and `runtime/logs/*` used by Status menu and build selectors

## 5) Observed Reality vs Legacy Docs
- Build scripts are active in `phases/`
- Menu paths use runtime state files heavily
- Direct CLI `build` dispatcher remains placeholder text
