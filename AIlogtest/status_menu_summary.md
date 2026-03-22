# Status Menu — Implementation Summary
Date: 2026-03-23T00:00:00+07:00
Branch: fix/fresh-clone-and-paths

## Menu Structure
--- Status ---
  1) Dashboard
  2) Show Build State
  3) Show Logs
  4) Back

## Functions Implemented
- _status_dashboard(): table view all OS/version/phase ✓/✗/○
- _status_build_state(): detail view per OS/version with JSON fields
- _status_show_logs(): log viewer with tail-50 or full log option

## Data Sources
- runtime/state/<phase>/<os>-<ver>.ready  → ✓
- runtime/state/<phase>/<os>-<ver>.failed → ✗
- runtime/state/<phase>/<os>-<ver>.json   → detail fields
- runtime/logs/<phase>/<os>-<ver>.log     → log content

## Dashboard Sample Output
```
  ╔══════════════════════════════════════════════════════════════╗
  ║                  Pipeline Status Dashboard                   ║
  ╚══════════════════════════════════════════════════════════════╝

  OS           VERSION  import     create     configure  clean      publish    
  ────────── ─────── ──────────────────────────────────────────────────
  ubuntu       18.04    ○        ○        ○        ○        ○        
  ubuntu       20.04    ○        ○        ○        ○        ○        
  ubuntu       22.04    ○        ○        ○        ○        ○        
  ubuntu       24.04    ✓        ✓        ✓        ✓        ✓        
  debian       12       ○        ○        ○        ○        ○        
  fedora       41       ○        ○        ○        ○        ○        
  almalinux    8        ○        ○        ○        ○        ○        
  almalinux    9        ○        ○        ○        ○        ○        
  rocky        8        ○        ○        ○        ○        ○        
  rocky        9        ✓        ✓        ✓        ✓        ✓        

  Legend: ✓ = ready   ✗ = failed   ○ = not started
```

## Build State Sample Output (ubuntu 24.04)
```
  === Build State: ubuntu 24.04 ===

  import      : ✓ ready
    image_name    : base-ubuntu-24.04
  create      : ✓ ready
  configure   : ✓ ready
  clean       : ✓ ready
  publish     : ✓ ready
    final_image   : ubuntu-24.04-20260322
```

## Test Results
| Test | Description | Result |
|------|-------------|--------|
| 1 | menu 4 options | PASS |
| 2 | dashboard shows OS | PASS |
| 3 | dashboard icons correct (✓/○) | PASS |
| 4 | build state shows JSON fields | PASS |
| 5 | log files listed | PASS |
| 6 | dispatch command mode | PASS |
| 7 | shellcheck --severity=error | PASS |
