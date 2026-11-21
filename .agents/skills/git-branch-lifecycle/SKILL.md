---
name: git-branch-lifecycle
description: Audit working tree cleanliness, synchronize the canonical upstream base branch, and create a collision-free feature or fix branch. Use when starting a new feature or bug-fix branch, syncing the base branch before implementation, or when invoked by dev-implement or dev-parallel.
---

# Git Branch Lifecycle

Stage 1 initialization skill for the autonomous development pipeline:

`git-branch-lifecycle` -> `dev-implement` (`dev-tdd` & `review-diff`) -> `git-commit-stager` -> `git-safety-guard`

## Entry & Exit Contracts

- **Entry**: Task description or ticket identifier (e.g., `"PROJ-102: Fix memory leak in websocket listener"`) inside a Git repository root.
- **Exit**: Working tree checked out on a synchronized, collision-free task branch (`feat/...`, `fix/...`, `refactor/...`), with `.agent/lifecycle-state.json` emitted ([references/manifest-schema.md](./references/manifest-schema.md)).

## Execution Protocol

### 1. Pre-Flight Invariants

Verify all repository preconditions before creating or switching branches:

1. **Repository Root**: Confirm execution inside a valid Git working tree (`git rev-parse --is-inside-work-tree`).
2. **Clean Working Tree**: Require `git status --porcelain=v1` to be empty. If uncommitted changes exist, halt immediately and report modified paths to the user.
3. **Zero Pending Operations**: Confirm no rebase, merge, cherry-pick, or revert markers exist in `.git/`.
4. **Dynamic Base Branch Resolution**: Resolve the canonical base branch from `refs/remotes/origin/HEAD`, falling back to probing `main`, `master`, `trunk`, and `develop`.

### 2. Automated Branch Creation (`scripts/create-branch.sh`)

Execute the bundled non-interactive helper script to synchronize the base branch, derive the Conventional Commits branch prefix and slug, resolve ref collisions, check out the branch, and emit `.agent/lifecycle-state.json`:

```bash
bash "$(dirname "$0")/scripts/create-branch.sh" "<task-or-ticket-description>"
```

When invoking from a workspace context pointer, run:

```bash
bash skills/git-branch-lifecycle/scripts/create-branch.sh "<task-or-ticket-description>"
```

### 3. Script Operations Summary

The helper script (`scripts/create-branch.sh`) enforces five deterministic steps:

1. Sets `GIT_TERMINAL_PROMPT=0` and `GIT_PAGER=cat` for non-interactive execution.
2. Fetches `origin/<base>` with `--prune` and fast-forwards the local base branch (`git merge --ff-only`). If local base has unpushed commits ahead of `origin`, halts immediately to protect local history.
3. Parses any leading ticket ID (`PROJ-102`, `GH-42`) and maps action verbs (`add`/`create`/`implement` -> `feat`, `fix`/`resolve` -> `fix`, `refactor`/`clean` -> `refactor`, `test` -> `test`, `doc` -> `docs`) into `<prefix>/<ticket-id>-<slug>` (truncated to 35 chars).
4. Checks local and remote refs for branch name collisions; if a collision exists, appends a deterministic UNIX timestamp suffix (`-<epoch>`) and validates via `git check-ref-format --branch`.
5. Checks out the new branch from `refs/heads/<base>` and writes `.agent/lifecycle-state.json`.

## Operational Guardrails

- Always preserve existing uncommitted work by halting on a dirty tree rather than running destructive reset or clean commands.
- Always branch from a verified, fast-forwarded canonical base branch rather than committing directly onto `main` or `master`.
- Consult [references/manifest-schema.md](./references/manifest-schema.md) for exit codes, failure recovery actions, and the JSON output contract.
