# OpenRC Endpoint Test Summary

Date: 2026-03-22T16:00:00+07:00
Tested on: Linux host 192.168.90.48 (`/mnt/vol-image/image-build`)

---

## OpenRC Files Found

```
settings/openrc-file/openrc-nutpri.sh   (internalURL, HTTP)
settings/openrc-file/openrc-nutpub.sh   (publicURL,   HTTPS)
settings/openrc-file/test-insecure.sh   (dummy — not tested)
settings/openrc-file/test-secure.sh     (dummy — not tested)
```

---

## Test Results Per File

### openrc-nutpri.sh
- OS_AUTH_URL     : `http://172.90.2.43:5000/v3`
- OS_ENDPOINT_TYPE: `internalURL`
- OS_INTERFACE    : `internalURL`
- OS_INSECURE     : NOT SET (HTTP endpoint — no TLS, no --insecure needed)
- Token (plain)   : **PASS**
- Token (--insecure): **PASS**
- SSL check       : HTTP 200 (plain and --insecure both OK)
- Self-signed cert: N/A (HTTP, not HTTPS)
- Recommended flags: *none needed*
- Reachable from 192.168.90.48: **YES**

### openrc-nutpub.sh
- OS_AUTH_URL     : `https://skystack-ars-srb-1.openlandscape.cloud:5000/v3`
- OS_ENDPOINT_TYPE: `publicURL`
- OS_INTERFACE    : `publicURL`
- OS_INSECURE     : NOT SET
- Token (plain)   : **FAIL** — connection timeout from 192.168.90.48
- Token (--insecure): **FAIL** — connection timeout from 192.168.90.48
- SSL check       : HTTP 000 (no network access from this host)
- Self-signed cert: unknown (host unreachable from Linux host)
- Recommended flags: --insecure likely needed when used from Windows/external
- Reachable from 192.168.90.48: **NO** (public internet not accessible from this host)

---

## Auto-Selection Logic Implemented

File: `scripts/control.sh`
Function: `_auto_select_openrc()`

Detection method: `uname -s` + grep for `internalURL|internal` in openrc content

| Environment | Prefers | Reason |
|-------------|---------|--------|
| Linux       | openrc-nutpri.sh | uname=Linux + contains "internalURL" |
| Windows/other | openrc-nutpub.sh | uname≠Linux + does NOT contain "internal" |
| Single file | any single file | always auto-selected regardless of env |
| Ambiguous   | manual list | fallback to interactive selection |

Integration: inserted into `_settings_load_openrc()` — runs before interactive list when `${#files[@]} -gt 1`.

---

## Recommendation

On Linux host 192.168.90.48:
- **Only `openrc-nutpri.sh` works** — public endpoint is network-unreachable from this host
- `_auto_select_openrc()` will correctly pick `openrc-nutpri.sh` (Linux + "internalURL" match)
- No `--insecure` or `OS_INSECURE` needed (HTTP endpoint, no TLS)

On Windows (Git Bash, developer laptop):
- `_auto_select_openrc()` will pick `openrc-nutpub.sh` (non-Linux + no "internal" match)
- `--insecure` may be needed if the public endpoint uses a self-signed cert
  (could not test from Linux host — verify separately from Windows)
