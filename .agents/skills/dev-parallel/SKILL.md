---
name: dev-parallel
description: "Implement a multi-ticket specification on an integration branch by dispatching parallel fresh-context implementer subagents across the unblocked ticket frontier."
disable-model-invocation: true
---

# Parallel Task-Graph Spec Orchestrator

Implement a complete specification and its associated DAG of tickets onto a single **integration branch** by scheduling isolated **implementer subagents** in parallel across the ready **frontier**.

## Architectural Rules

- **Task Graph Execution**: Treat the tickets produced by `/shape-tickets` as a directed acyclic graph (DAG) with explicit blocking edges. The **frontier** consists of all open tickets whose blocking dependencies are completely resolved.
- **Fresh Context Per Subagent**: Start every exploration, implementer,reviewer, and merger subagent with a **fresh context window** so zero accumulated context pollution leaks between tickets.
- **Sparse Context Pointers**: Communicate with subagents using compact **context pointers** (paths or issue numbers for the spec, ticket, `GLOSSARY.md`, `docs/adr/`, and exploration notes) rather than pasting duplicate documents into prompts.

## Orchestration Steps

### 1. Ingest the Spec and Task Graph

1. Read the specification and all associated tickets from the tracker configured in `docs/agents/issue-tracker.md` (or `.scratch/<feature-slug>/`).
2. Construct the dependency graph and identify the initial unblocked **frontier**.

### 2. Optional Upfront Exploration Subagent

If the tickets require shared codebase discovery or external API lookup, dispatch a single read-only **exploration subagent** with a fresh context window first. Have it write concise markdown notes to `$TMPDIR` (or `.scratch/<feature-slug>/notes/`) so downstream implementer subagents can read the pointer directly without repeating exploration.

### 3. Initialize the Integration Branch

Create and check out a dedicated integration branch (`feat/<spec-slug>-integration`) from the synchronized base branch using `git-branch-lifecycle` conventions.

### 4. Dispatch Parallel Implementer Subagents Across the Frontier

For each unblocked ticket on the current frontier, create an isolated git worktree (`git worktree add`) on its own ticket branch based on the integration branch tip, and launch a fresh **implementer subagent** in the background:

- Each implementer subagent verifies its worktree is based on the integration branch tip.
- Each implementer subagent calls `dev-tdd` to build its ticket's vertical slices test-first at the agreed seams.
- Each implementer subagent merges the current integration branch tip into its ticket branch, verifies tests pass, and commits via `git-commit-stager` and `git-safety-guard` conventions before reporting completion.

### 5. Merge Completed Tickets and Advance the Frontier

1. As each implementer subagent finishes, merge its verified ticket branch into the integration branch using a **merger subagent** (or clean fast-forward/merge commit).
2. If the tracker is GitHub/GitLab and no draft PR exists yet, open a draft PR after the first ticket merges into the integration branch.
3. Recompute the **frontier** of newly unblocked tickets and immediately spawn fresh implementer subagents for every newly unblocked ticket to maximize concurrency.

### 6. Integration Review and Cleanup

1. Once all tickets in the DAG are merged, call `review-diff` across the entire integration branch (`git diff <base-branch>...HEAD`).
2. Dispatch a single fresh **implementer subagent** to resolve any Standards or Spec findings surfaced by `review-diff`.
3. Remove all temporary implementer git worktrees (`git worktree remove`), mark each ticket resolved on the tracker, and report the completed integration branch (or mark the PR ready for review).
