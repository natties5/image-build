# refactor_ols_removal_and_new_os_summary

## Starting State
- Host: `192.168.90.48` (user `root`), repo: `/mnt/vol-image/image-build`, branch: `fix/fresh-clone-and-paths`.
- Pre-existing dirty file before this task: `config/os/almalinux/sync.env`.
- Fedora sync was archive-only and failed for current Fedora releases.
- Alpine and Arch OS/guest configs were not present.
- Legacy `OLS`/`ols_` references existed across active scripts, legacy files, and docs.

## What Changed and Why
- Fedora sync fallback support:
  - `config/os/fedora/sync.env`: switched primary to `dl.fedoraproject.org`, added `INDEX_URL_FALLBACK` to archives, updated tracked to `41 42 43`.
  - `phases/sync_download.sh`: added primary->fallback checksum resolution and explicit URL-source logging.
  - `phases/sync_download.sh`: added hash-only checksum normalization for Alpine per-file `.sha512` artifacts (derive filename from checksum artifact name).
- Upstream auto-discovery:
  - `lib/common_utils.sh`: Fedora discovery now checks releases first, archives fallback.
  - `lib/common_utils.sh`: added Alpine discovery (`v3.xx`, `releases/cloud`, qcow2 presence).
  - `lib/common_utils.sh`: added Arch discovery return (`latest`) and expanded sync/build OS lists.
- New OS support:
  - Added `config/os/alpine/sync.env`.
  - Added `config/os/arch/sync.env`.
  - Added guest configs:
    - `config/guest/alpine/default.env`
    - `config/guest/alpine/3.21.env`
    - `config/guest/arch/default.env`
    - `config/guest/arch/latest.env`
- Control menu/dispatch OS loops:
  - `scripts/control.sh`: added `alpine` and `arch` in all relevant sync/build loops and help text.
- Clean phase refactor:
  - `phases/clean_guest.sh`: removed package-cache cleaning execution block.
  - `phases/clean_guest.sh`: removed `cache` from `steps_completed` state JSON list.
- OLS removal (whole-repo scope selected):
  - Purged all `OLS`, `ols_`, and `ols-` tokens across repo text files (active scripts, legacy configs, AI logs, design docs, legacy phase script).
- Debian future-proofing:
  - `config/os/debian/sync.env`: `CODENAME_MAP="12:bookworm 13:trixie 14:forky 15:duke"`.
- README update:
  - Added Alpine and Arch rows in OS support table.

## Verification Results
- Syntax checks:
  - `bash -n phases/sync_download.sh` -> OK
  - `bash -n phases/configure_guest.sh` -> OK
  - `bash -n phases/clean_guest.sh` -> OK
- Shellcheck:
  - `shellcheck -e SC1091 phases/configure_guest.sh phases/clean_guest.sh phases/sync_download.sh` -> OK
- Required assertions:
  - `grep -R 'OLS' config/guest/` -> no matches
  - `grep -R 'INDEX_URL_FALLBACK' config/os/fedora/sync.env | wc -l` -> `1`
  - `ls config/os/alpine/sync.env config/os/arch/sync.env` -> both exist
  - `ls config/guest/alpine/default.env config/guest/arch/default.env` -> both exist
- Sync dry-run checks:
  - `bash scripts/control.sh sync dry-run --os alpine` -> success, selected `generic_alpine-3.21.6-x86_64-bios-cloudinit-r0.qcow2` (hash-only checksum handling validated)
  - `bash scripts/control.sh sync dry-run --os arch` -> success, selected `Arch-Linux-x86_64-cloudimg.qcow2`
  - `bash scripts/control.sh sync dry-run --os fedora` -> success
    - Fedora 41 used fallback archive URL
    - Fedora 42 and 43 used primary releases URL

## Git / Commit / Push
- Commit hash: _to be filled after commit_

## Unresolved Items
- None functionally unresolved for requested scope.
- Note: `config/os/almalinux/sync.env` was pre-existing dirty state before this task.
