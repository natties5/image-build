You are working inside my existing image-build repository.

Read this file completely and use it as the source of truth for the refactor.

Goal
Refactor and simplify the current control framework into a VS Code friendly, jump-host driven control panel that is easy to use and logically correct.

This is an incremental refactor.
Do NOT redesign the OpenStack image pipeline from scratch.
Preserve the currently working Ubuntu pipeline behavior and guest VM policy/end-state.

Critical non-negotiable constraints

1) Do NOT change the intended guest VM configuration policy or desired end-state.
Do NOT change:
- root login intent
- password auth intent
- apt/repo mirror intent
- locale/timezone targets
- cloud-init behavior targets
- firewall intent
- package intent
- any intended final guest image outcome

You may only change:
- control flow
- menu/controller behavior
- SSH/jump-host workflow
- git sync/bootstrap workflow
- wrappers
- validation
- state handling
- multi-OS structure
- logging
- bug fixes
- rerun safety
- UX of the control menu
- version/manifest logic

2) Do NOT store real secrets in tracked files.
Local-only SSH config, private keys, and jump-host env files are allowed only under a gitignored path such as deploy/local/.

3) Preserve the working Ubuntu implementation.
Ubuntu is the only real implemented OS flow for now.
Debian, CentOS, AlmaLinux, and Rocky Linux should be skeleton only:
- directories
- placeholders
- config stubs
- dispatch hooks
- clear “not implemented yet” behavior
Do NOT fake full support for non-Ubuntu OSes.

4) Do NOT broaden scope beyond this repository and current project.
Do NOT modify shared infrastructure behavior beyond preserving current safe behavior.

5) Keep the operator experience simple.
The current logic is too confusing and currently wrong in one important way:
it asks for Ubuntu version too early and appears to default to Ubuntu 18.04 instead of deriving versions from the downloaded manifest.
This must be fixed.

Current logic problem to fix

The current control flow is wrong because:
- it asks for OS version before download/discover has been run
- version choices are not being loaded dynamically from the manifest/summary
- preflight can fail because EXPECTED_PROJECT_NAME is not being passed automatically
- the menu is too “menu-first” and not dependency-aware

Correct logic requirements

Versions must not be chosen before the repository has completed the required download/discover step and produced manifest/summary data.

For Ubuntu:
- download/discover must happen first
- manifest/summary must be generated first
- available versions must be loaded from manifest/summary
- version choices must not be hardcoded as the source of truth
- if manifest is missing, the controller must clearly guide the operator to run download/discover first
- remove any incorrect fallback/default logic that effectively forces Ubuntu 18.04

Main control structure

The top-level controller must be simple and have these sections:

1) SSH
2) Git
3) Pipeline
4) Exit

SSH section requirements

SSH menu should support at least:
- connect to jump host
- validate SSH connectivity
- show safe target info
- back

Behavior:
- connect should open a normal interactive SSH session
- when the operator exits that SSH session, control should return to the menu
- do not fake persistent session state
- do not build a fake logout manager

Git section requirements

Git menu should support at least:
- bootstrap-remote-repo
- sync-safe
- sync-code-overwrite
- sync-clean
- git status
- git branch info
- optional push only if it is safe and meaningful
- back

Most important Git requirement:
Fix the problem where the workflow fails if the jump-host path exists but the repository is not present there.

Required behavior:
- if REMOTE_PATH does not exist, create parent path safely and clone repo there
- if REMOTE_PATH exists but is empty, clone repo there
- if REMOTE_PATH exists and is already a git repo, operate normally
- if REMOTE_PATH exists but contains unexpected non-repo files, fail safely and explain instead of destroying content

Destructive sync requirements:
- destructive sync modes must never run silently
- interactive mode must ask for confirmation
- non-interactive mode must require --yes
- clearly explain what will be reset/cleaned
- local-only files under deploy/local/ must never be removed by default

Pipeline section requirements

Pipeline must be simple and dependency-aware.

Pipeline menu should contain:
- Manual
- Auto by OS
- Auto by OS Version
- Status
- Logs
- Back

Manual flow requirements

Manual mode must work like this:

1) Select OS
2) Ensure remote repo exists (bootstrap if needed or offer bootstrap)
3) Run Download/Discover first
4) Read manifest/summary
5) Show available versions loaded from manifest
6) Select version
7) Choose one phase:
   - preflight
   - import
   - create
   - configure
   - clean
   - publish
   - status
   - logs
   - change-version
   - change-os
   - back
8) Run selected phase
9) Return to the same menu after completion

Important Manual rules:
- do not ask for version before download/discover
- do not hardcode Ubuntu 18.04 as the default choice
- version list must come from manifest/summary
- if manifest is missing, instruct the operator to run download/discover first

Auto flow requirements

Auto mode must be split into two separate modes:

A) Auto by OS
B) Auto by OS Version

Auto by OS flow:
1) Select OS
2) Ensure remote repo exists (bootstrap/sync if needed)
3) Validate jump host / control environment
4) Run download/discover for that OS
5) Generate manifest/summary
6) Load all discovered versions from manifest
7) If no versions found, stop and explain
8) For each discovered version, run:
   - preflight
   - import
   - create
   - configure
   - clean
   - publish
9) Record per-version results
10) Show final summary

Auto by OS Version flow:
1) Select OS
2) Ensure remote repo exists (bootstrap/sync if needed)
3) Validate jump host / control environment
4) Run download/discover for that OS
5) Generate manifest/summary
6) Load discovered versions from manifest
7) Select one version from discovered versions
8) Validate that the requested/selected version exists
9) Run full pipeline for that single version:
   - preflight
   - import
   - create
   - configure
   - clean
   - publish
10) Show final summary

Important Auto rules:
- do not ask for version before download/discover
- do not hardcode version choices
- version options must come from manifest/summary
- Ubuntu is the only real implemented OS now
- other OSes must remain skeleton / not implemented yet

Preflight requirements

Preflight must remain non-destructive.
Preflight must receive EXPECTED_PROJECT_NAME automatically from config/local env or equivalent control config.
The operator should not need to manually prepend EXPECTED_PROJECT_NAME every time.

Local-only jump-host config requirements

Design for local-only files under a gitignored path such as deploy/local/:
- SSH config
- private key
- jump-host env/config
- remote path
- branch
- default expected project if needed
- any local-only controller settings

Do NOT put real secrets in tracked files.
Do provide tracked example templates and concise docs.

Repository structure direction

Keep or refine the playbook-style structure:
- scripts/control.sh as operator entrypoint
- bin/ and/or lib/ helpers if needed
- phases/
- config/os/
- config/guest/
- deploy/ for local-only integration and example files
- runtime/
- manifests/
- logs/
- docs or /doc for documentation

Backward compatibility requirement

Existing scripts under scripts/ should continue to work where reasonable as wrappers or compatibility shims.
If scripts/control.sh is the current operator entrypoint, keep it working.
Do not break the main operator command.

VS Code integration

Include VS Code tasks and concise docs only if it helps and does not add unnecessary complexity.
Tasks must:
- call the controller
- not duplicate business logic
- not store secrets or real host details

Implementation philosophy

Keep it simple.
This refactor must simplify and correct the logic.
Avoid overengineering.
Prefer clear, reviewable, dependency-aware flow over complex abstractions.

Acceptance criteria

By the end, the repository should provide:
1) a simple top-level controller with:
   - SSH
   - Git
   - Pipeline
   - Exit

2) SSH menu that works and returns to menu after exiting SSH

3) Git menu that supports:
   - bootstrap remote repo
   - sync-safe
   - sync-code-overwrite
   - sync-clean
   - status / branch info

4) Pipeline menu that supports:
   - Manual
   - Auto by OS
   - Auto by OS Version
   - Ubuntu real implementation
   - multi-OS skeleton only for non-Ubuntu

5) version selection logic based on manifest/summary, not hardcoded Ubuntu 18.04 fallback

6) preflight that automatically uses EXPECTED_PROJECT_NAME from config/local env

7) local-only SSH/key/jump-host files inside repo tree but ignored by git

8) concise docs

Validation requirements

After patching:
- run bash -n on all shell scripts
- run shellcheck if available
- verify controller help/usage works
- verify SSH/Git/Pipeline menu routing works
- verify wrapper dispatch still works where applicable
- verify bootstrap remote repo logic works safely
- verify preflight remains non-destructive
- do not run destructive OpenStack operations unless strictly required for a specific bug fix
- do not do a full rebuild/publish unless specifically needed

Git workflow requirements

Before major edits:
- inspect the current branch
- summarize the bug and the simplified plan

Then:
- show diffs in logical chunks
- apply changes
- validate
- commit
- push current branch to GitHub

Use this commit message:
fix: simplify control flow and make version selection manifest-driven

Documentation output requirement

After the work is complete, create a Thai summary file at:

/doc/summary-control-refactor-th.md

That Thai summary must explain:
- what was wrong before
- what was changed
- how the new SSH flow works
- how the new Git flow works
- how Manual mode now works
- how Auto by OS works
- how Auto by OS Version works
- where local-only jump-host files should go
- what is implemented now
- what is skeleton only
- any known limitations remaining

The Thai summary should be written clearly for the operator, not for developers only.

Required work order

1) Read and understand this prompt file fully
2) Review current implementation and identify the exact logic bug
3) Explain the simplified target flow before editing
4) Patch the controller and related files
5) Validate
6) Commit and push
7) Write the Thai summary file under /doc