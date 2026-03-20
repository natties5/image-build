You are working inside my existing image-build repository.

Your task is to reorganize and simplify the configuration/layout/documentation/history structure
WITHOUT breaking the current working behavior.

This is a controlled cleanup and architecture-hardening task.
Do NOT redesign the entire system.
Do NOT change the intended pipeline concept.
Do NOT change guest VM policy.
Do NOT break the current Ubuntu flow.
Do NOT break the current multi-OS official auto-download support branch behavior.

Current intent of the repository

This repository is an OpenStack image pipeline project.
The long-term direction is:
Discover -> Download -> Build -> Config -> Validate -> Publish -> Reuse

But right now, we must preserve the current working state:
- Ubuntu is the reference implementation
- multi-OS support currently focuses on official auto-discover + auto-download
- jump-host driven execution must keep working
- config-driven version selection must keep working

Main problem to solve

The config/library/control layout is becoming messy and hard to reason about.
Config is spread across too many places and responsibilities are mixed.

I want you to reorganize the repository so the concepts are cleaner and easier to maintain,
but I do NOT want a big rewrite or a behavior change.

What I want conceptually

I want the repo to clearly separate these layers:

1) Control config
   - local operator / VS Code / jump-host control settings
   - which branch / remote path / expected project / mode defaults

2) Runtime sync config
   - local-only files that must be copied to jump host for remote phase execution
   - for example guest access / openrc path / remote runtime values

3) OS config
   - per-OS discover/download behavior
   - MIN_VERSION, MAX_VERSION, ALLOW_EOL, ARCH, official source URLs, artifact preferences

4) Guest policy config
   - VM policy only
   - root login intent
   - password auth intent
   - mirror intent
   - locale/timezone intent
   - cloud-init intent
   - firewall intent
   - package intent
   - must remain separate from controller/runtime logic

5) Pipeline/data outputs
   - cache
   - manifests
   - runtime state
   - logs

Repository cleanup goal

Reorganize the repo so it becomes much easier to answer:
- what is local-only?
- what gets synced to jump host?
- what is per-OS config?
- what is guest policy?
- what is OpenStack runtime config?
- what is output/state/log?

Do this with the smallest safe change set possible.

Critical constraints

1) Do NOT change guest VM policy or intended guest outcome.
2) Do NOT redesign pipeline phases from scratch.
3) Do NOT break Ubuntu behavior.
4) Do NOT break the current multi-OS download behavior.
5) Do NOT move secrets into tracked files.
6) Do NOT break jump-host driven execution.
7) Do NOT remove scripts/control.sh as the operator entrypoint.
8) Do NOT change the conceptual flow of the project.

Required outcome

Create a cleaner layered structure and make the loading flow more obvious.

Use a structure concept like this if helpful:

- deploy/local/              # local-only, gitignored
- config/control/            # tracked control templates/defaults if needed
- config/runtime/            # runtime templates/defaults if needed
- config/os/                 # per-OS config
- config/guest/              # guest policy config
- lib/control_*.sh           # controller helpers
- lib/runtime_*.sh           # runtime sync/load helpers
- lib/os_*.sh                # OS helper logic
- phases/                    # phase logic
- manifests/                 # stable machine-readable outputs
- runtime/state/             # live execution state
- logs/                      # logs
- doc/                       # long-form documentation

You do NOT have to use exactly this structure,
but the final structure must make responsibilities much clearer.

Required loading flow

Make the effective config loading flow explicit and simple:

Local operator
-> load control config
-> load local-only runtime config
-> connect/sync to jump host
-> sync required runtime config
-> select OS/mode/version
-> load OS config
-> run phase
-> phase reads normalized inputs
-> write manifests/state/logs

I want this flow to be understandable from code and docs.

Rules to prevent future config drift

Implement/normalize these rules where appropriate:

- phase scripts must not search many unrelated config files by themselves
- phase scripts should read normalized inputs from helper functions
- controller is responsible for assembling and syncing required runtime config
- local-only config and tracked config must be clearly separated
- guest policy config must never be mixed with jump-host control config
- OS config must never be mixed with guest policy config
- output/state/log files must be clearly separate from config

Documentation requirements

Add or improve documentation so the repo is understandable.

Use documentation layering like this:

1) Top-level README
   - short overview
   - current supported scope
   - quick start
   - where to look next

2) /doc/
   - architecture overview
   - operator guide
   - config layout guide
   - jump-host config guide
   - multi-OS download guide
   - branch/workflow guidance
   - change history guidance

3) per-OS docs only if needed
   - only for special caveats
   - avoid duplication

Required docs to add or update

Please create or update these docs if useful:

- doc/architecture-overview.md
- doc/config-layout.md
- doc/operator-guide.md
- doc/jump-host-config.md
- doc/commit-history-and-branching.md

Also add one Thai summary file:
- doc/summary-config-reorg-th.md

The Thai summary must explain:
- what was messy before
- what structure was cleaned up
- where each config type now lives
- what gets synced to jump host
- what stays local-only
- where OS config lives
- where guest policy lives
- where logs/state/manifests live
- how to read the repo now
- what was intentionally NOT changed

Commit history / branch history requirements

I want future history to be easier to understand.

Please add a simple, practical strategy for commit history and change tracking.

What I want:
- conventional commit style where useful
- branch naming guidance
- a place to record important architecture decisions
- a place to record major change milestones

Implement/document this with a minimal practical solution, for example:
- doc/commit-history-and-branching.md
- doc/adr/ for architectural decision records
- optional CHANGELOG.md only if useful and not overkill

Recommended guidance to document:
- feat: ...
- fix: ...
- refactor: ...
- docs: ...
- chore: ...

Recommended branch naming examples:
- codex/<topic>
- fix/<topic>
- feat/<topic>
- refactor/<topic>

Also define where operators/developers should look to understand “what changed recently”.

Migration requirement

This cleanup must not break current branch behavior.
If files need to move, keep compatibility wrappers or compatibility loading as needed.
Prefer gradual migration over hard breaks.

Work order

1) Inspect the current branch and inventory:
   - current config files
   - local-only files
   - control/runtime helpers
   - phase scripts
   - docs
   - manifest/state/log paths

2) Summarize the current problems clearly.

3) Propose the smallest safe cleanup plan.

4) Show diffs in logical chunks.

5) Apply the cleanup.

6) Validate:
   - bash -n relevant scripts
   - shellcheck if available
   - verify Ubuntu path still works
   - verify multi-OS download path still works
   - verify scripts/control.sh still works
   - verify jump-host runtime config sync still works

7) Commit.

8) Push current branch.

Commit message

Use:
refactor: organize config layers docs and history without changing pipeline behavior

Final output requirements

At the end, provide:
- architecture summary
- new config flow summary
- what changed
- what did NOT change
- docs added/updated
- commit/history strategy summary
- Thai summary path
Do not ask follow-up questions unless a real missing file or secret blocks implementation.
Prefer the smallest safe cleanup that improves clarity without changing behavior.
Keep Ubuntu and the current multi-OS official auto-download behavior intact.

git checkout codex/add-multi-os-auto-download-support
git pull --ff-only origin codex/add-multi-os-auto-download-support