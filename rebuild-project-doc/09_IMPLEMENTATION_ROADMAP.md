# 09 - Implementation Roadmap (From Current State)

Last updated: 2026-03-25

## Completed/Present
- sync discovery/download with checksum and state model
- Fedora primary+fallback behavior
- Alpine and Arch sync/config onboarding
- guest configure vault fallback model
- clean stage official repo restore before shutdown
- Rocky and AlmaLinux 8/9/10 recovery logs captured

## Priority Next
1. Align direct CLI `build` dispatcher with interactive build menu behavior.
2. Remove or archive obsolete legacy scripts (`*_one.sh` paths) after confirming no active dependencies.
3. Harden docs/tests around Alpine and Arch full pipeline (not only sync path).
4. Clean remaining legacy terminology drift in historical notes where confusing.
5. Add regression checks for repo mode JSON contract (`official`, `vault`, `official-fallback`, `failed`).

## Documentation Rule
Keep this roadmap tied to code reality, not planned architecture text.
