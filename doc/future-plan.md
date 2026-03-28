# Image Lifecycle Automation - Future Plan

## Overview

This document outlines the future automation plan for the OpenStack image build pipeline.

## Current State

### Working Components
- Version tracking: config/os/<os>/sync.env
- Image discovery: sync_download.sh
- Build pipeline: import → create → configure → publish
- Guest configuration: config/guest/<os>/

### Manual Steps Required
- Version check must be triggered manually
- Pipeline must be run manually
- No notification system
- No error recovery

---

## Future Automation Plan

### Architecture Overview

```
[Check Script] → [Detect New Version] → [Telegram Notify] → [Wait Approval]
                                                                            ↓
[Success] ← [Publish] ← [Configure] ← [Create VM] ← [Import] ← [Sync] ← [Approve]
                                      ↓
                              [Fail? → AI Fix → Retry]
```

### Phase 0: Version Detection

**Current:**
- Manual trigger required

**Future:**
- Scheduled check via cron/systemd timer (every 6-12 hours)
- LTS-only tracking
- State stored in: runtime/state/tracked-versions.json

**New Files:**
- scripts/check_versions.sh

**Config:**
- config/tracked.env (OS families + LTS versions to track)

---

### Phase 1: Approval Mechanism

**Flow:**
1. New version detected
2. Send Telegram notification with version details
3. Wait for approval (reply to Telegram OR manual command)
4. If approved → trigger pipeline
5. If rejected → log and stop

**New Files:**
- lib/telegram_notify.sh
- scripts/approve_build.sh

**Config:**
- config/notification.env
  - TELEGRAM_BOT_TOKEN
  - TELEGRAM_CHAT_ID
  - TELEGRAM_ENABLED=true/false

---

### Phase 2: Build Pipeline

**Phases:**
1. Sync - Download base image
2. Import - Upload to Glance
3. Create - Boot VM
4. Configure - Customize guest OS
5. Publish - Upload final image

**State Tracking:**
- Each phase writes state to: runtime/state/<phase>/<os>-<version>.json
- Status: pending | running | success | failed

---

### Phase 3: AI-Assisted Error Recovery

**Flow:**
```
Phase Failed
    ↓
Collect logs from: runtime/logs/<phase>/<os>-<version>.log
    ↓
Send to AI API (with context: OS, version, error message)
    ↓
Receive suggestion
    ↓
Apply fix (auto or manual)
    ↓
Retry phase (max 3 retries)
    ↓
If all retries fail → Notify admin
```

**New Files:**
- lib/ai_assist.sh
- lib/error_handler.sh

**Config:**
- config/ai_config.env
  - AI_API_ENDPOINT
  - AI_API_KEY
  - AI_MODEL
  - AI_MAX_TOKENS
  - AI_RETRY_LIMIT=3

---

### Phase 4: Publishing

**Current:**
- Single project publish
- Direct to Glance

**Future:**
- Publish to single OpenStack project
- No staging environment needed
- Final image name format: <os>-<version>-YYYYMMDD

---

## Notification Events

| Event | Message | Action Required |
|-------|---------|-----------------|
| New LTS version detected | "New Ubuntu 24.04 LTS detected (build 20250328)" | None (wait for approval) |
| Build started | "Starting build for Ubuntu 24.04 LTS" | None |
| Phase failed | "Configure phase failed. AI suggests: [fix]. Retry? [Yes/No]" | Manual approval for risky fixes |
| Build completed | "Image ubuntu-24.04 ready in Glance" | None |
| Build failed (final) | "All retries failed. Manual intervention required." | Admin action required |

---

## File Structure (New Files)

```
project-root/
├── doc/
│   └── future-plan.md          # This document
├── scripts/
│   ├── check_versions.sh       # Version detection script
│   ├── approve_build.sh         # Approval trigger
│   └── run_pipeline.sh          # Full pipeline orchestration
├── lib/
│   ├── telegram_notify.sh      # Telegram integration
│   ├── ai_assist.sh            # AI API integration
│   └── error_handler.sh         # Error collection + retry logic
├── config/
│   ├── notification.env         # Telegram config
│   ├── ai_config.env            # AI API config
│   └── tracked.env              # OS families to track
└── runtime/
    └── state/
        ├── tracked-versions.json    # Current tracked versions
        └── pending-approvals.json   # Waiting for approval
```

---

## Implementation Priority

### P0 - Essential (Phase 1)
- [ ] Create check_versions.sh
- [ ] Create telegram_notify.sh
- [ ] Create config/notification.env
- [ ] Implement version comparison logic
- [ ] Store tracked versions in JSON

### P1 - Important (Phase 2)
- [ ] Create approve_build.sh
- [ ] Implement approval workflow
- [ ] Add Telegram interactive callbacks

### P2 - Enhancement (Phase 3)
- [ ] Create ai_assist.sh
- [ ] Create error_handler.sh
- [ ] Create config/ai_config.env
- [ ] Integrate AI fix suggestions

### P3 - Future (Phase 4)
- [ ] Add cron/systemd timer for scheduled checks
- [ ] Multi-project publishing support
- [ ] Staging environment (if needed)

---

## Configuration Templates

### config/notification.env
```bash
# Telegram Bot Configuration
TELEGRAM_ENABLED=true
TELEGRAM_BOT_TOKEN="your-bot-token"
TELEGRAM_CHAT_ID="your-chat-id"
TELEGRAM_PARSE_MODE="Markdown"
```

### config/ai_config.env
```bash
# AI API Configuration
AI_ENABLED=true
AI_API_ENDPOINT="https://api.openai.com/v1/chat/completions"
AI_API_KEY="your-api-key"
AI_MODEL="gpt-4"
AI_MAX_TOKENS=2000
AI_RETRY_LIMIT=3
```

### config/tracked.env
```bash
# OS Families to Track (LTS only)
TRACKED_OS="ubuntu debian rocky almalinux"
TRACKED_VERSIONS_UBUNTU="22.04 24.04"
TRACKED_VERSIONS_DEBIAN="12"
TRACKED_VERSIONS_ROCKY="8 9"
TRACKED_VERSIONS_ALMALINUX="8 9"
```

---

## State Files

### runtime/state/tracked-versions.json
```json
{
  "last_check": "2026-03-28T10:00:00Z",
  "versions": {
    "ubuntu": {
      "22.04": {
        "checksum": "sha256:abc123...",
        "url": "https://...",
        "downloaded": true,
        "last_updated": "2026-03-15"
      },
      "24.04": {
        "checksum": "sha256:def456...",
        "url": "https://...",
        "downloaded": true,
        "last_updated": "2026-03-20"
      }
    }
  }
}
```

### runtime/state/pending-approvals.json
```json
{
  "pending": [
    {
      "os": "ubuntu",
      "version": "24.04.1",
      "detected_at": "2026-03-28T10:05:00Z",
      "checksum": "sha256:xyz789...",
      "url": "https://...",
      "status": "waiting_approval",
      "notified": true
    }
  ]
}
```

---

## Testing Plan

1. **Version Detection Test**
   - Run check_versions.sh manually
   - Verify JSON state file created
   - Verify Telegram notification sent

2. **Approval Test**
   - Send approval command
   - Verify pipeline triggered

3. **Error Recovery Test**
   - Simulate phase failure
   - Verify AI consulted
   - Verify retry logic works

4. **Full Pipeline Test**
   - Complete build from sync to publish
   - Verify final image in Glance

---

## Notes

- All new scripts must follow existing project bash style
- Use lib/core_paths.sh for path resolution
- Use lib/common_utils.sh for logging
- Use lib/state_store.sh for state management
- Error logs stored in: runtime/logs/<phase>/<os>-<version>.log

---

## Changelog

| Date | Author | Description |
|------|--------|-------------|
| 2026-03-28 | - | Initial plan created |