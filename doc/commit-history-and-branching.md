# Commit History and Branching Strategy

This project follows a structured approach to commit messages and branch naming to maintain a clean and understandable history.

## Branch Naming Guidance

Branches should be named according to their purpose:

- `codex/<topic>`: Main development branches for new features or major refactorings.
- `feat/<topic>`: Small to medium features.
- `fix/<topic>`: Bug fixes.
- `refactor/<topic>`: Code reorganization or cleanup without behavior changes.
- `docs/<topic>`: Documentation updates.

Example: `codex/add-multi-os-auto-download-support`

## Conventional Commit Style

We encourage the use of conventional commit messages for better clarity:

- `feat: ...`: Introducing a new feature.
- `fix: ...`: Fixing a bug.
- `refactor: ...`: Reorganizing or cleaning up code.
- `docs: ...`: Updating documentation.
- `chore: ...`: Routine tasks (e.g., updating dependencies, CI changes).

Example: `refactor: organize config layers docs and history without changing pipeline behavior`

## Change Tracking

Important architectural decisions and major change milestones should be recorded.

### 1. Architectural Decision Records (ADR)
Located in `doc/adr/`. Each ADR should be numbered and dated, documenting:
- The context of the decision.
- The alternatives considered.
- The chosen solution and its rationale.

### 2. Major Change History
For each significant refactor or feature, a summary document should be created in `doc/`.
Example: `doc/summary-config-reorg-th.md`

## Summary of Recent Changes
To understand what changed recently, developers and operators should check:
1. `git log --oneline --graph`
2. Relevant summary files in `doc/`.
3. ADRs in `doc/adr/`.
