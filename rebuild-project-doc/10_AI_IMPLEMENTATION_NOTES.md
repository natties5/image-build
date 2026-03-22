# 10 — AI Implementation Notes

เอกสารนี้ไว้ใช้เป็น guardrails สำหรับ AI/Codex ที่จะเขียนโปรเจกต์ต่อ

---

## 1. Primary intent

Build a **portable, menu-driven, OpenStack image build pipeline**.

Do not turn the project into:
- a jump-host framework
- a Git-sync-to-remote tool
- a multi-root config maze

---

## 2. Non-negotiables

- `scripts/control.sh` is the user-facing entrypoint
- `openrc` is not stored in repo
- `settings/openstack.env` is the single OpenStack settings file
- `settings/guest-access.env` is the single guest access settings file
- input config files are `.env`
- runtime outputs are `.json`
- quick state uses flag files
- use menus plus direct command mode
- phase names must map to real pipeline stages

---

## 3. Preserve these qualities
- path centralization
- runtime state concept
- structured phases
- logs and recoverability
- cleanup and resume as first-class capabilities

---

## 4. Remove these qualities
- jump host assumptions
- deploy/local usage
- hidden config precedence
- duplicated helper logic in each phase
- multiple confusing entrypoints

---

## 5. Coding style guidance
- write small Bash functions
- do not hide errors
- always log long-running operations
- add timeout + last known status for waits
- prefer wrappers over repeating raw OpenStack commands
- write JSON runtime manifests consistently
- avoid clever one-liners when clarity matters

---

## 6. AI development order
1. core paths
2. common utils
3. openstack api wrappers
4. config store / state store
5. sync phase
6. settings menu
7. import/create
8. configure/clean
9. publish
10. resume/status/cleanup
11. tests

---

## 7. Testing guidance
- start with dry-run tests
- mock OpenStack CLI where possible
- validate config merge behavior
- validate state path generation
- validate menu command dispatch
- validate exists/recover/replace policies

---

## 8. Failure philosophy
If one phase fails:
- write log
- write JSON with failure_phase and failure_reason
- write `.failed`
- leave enough state for Resume/Cleanup/Reconcile to work

Do not:
- silently swallow errors
- destroy useful runtime evidence
- over-clean resources before user can inspect failure

---

## 9. Success philosophy
A run is truly successful only when:
- final image exists and is active
- runtime JSON records success
- relevant flags are written
- cleanup is either successful or explicitly marked as warning/partial

---

## 10. Best first slice for AI
Ubuntu 24.04 full path:
- settings
- sync dry-run
- sync download
- import
- create
- configure
- clean
- publish

Once stable, replicate pattern to other OS families.
