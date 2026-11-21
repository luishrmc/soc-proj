---
name: dev-implement
description: "Execute a single ticket or specification end-to-end through the 5-stage Git and TDD development pipeline."
disable-model-invocation: true
---

# Single-Ticket Implementation Pipeline

Execute a shaped specification or tracer-bullet ticket end-to-end. This skill serves as the central orchestrator connecting the repository's **5-Stage Autonomous Development Pipeline**:

```text
[Stage 1: git-branch-lifecycle]
               │
               ▼
[Stage 2: Code Modification Loop (dev-tdd)]
               │
               ▼
[Stage 3: Two-Axis Diff Audit (review-diff)]
               │
               ▼
[Stage 4: Explicit Pathspec Staging (git-commit-stager)]
               │
               ▼
[Stage 5: Verified Commit Gate (git-safety-guard)]
```

## Execution Pipeline

### Stage 0: Ticket & Context Ingestion

1. If the user passes a ticket or spec reference (issue number, URL, or `.scratch/<feature-slug>/issues/<NN>-<slug>.md` path), fetch its full contents from the configured tracker (`docs/agents/issue-tracker.md`) and state its title and acceptance criteria before modifying any code. If the reference is ambiguous, ask the user to clarify.
2. Read `GLOSSARY.md` and relevant `docs/adr/` records so all new symbols, types, and test names adhere to the repository's ubiquitous language.

### Stage 1: Branch Initialization (`git-branch-lifecycle`)

1. Inspect the active Git branch and working tree state.
2. If the repository is still on the default base branch (`main`/`master`) with a clean working tree, invoke `git-branch-lifecycle` to synchronize the base branch, generate a collision-free task branch (`feat/<ticket-id>-<slug>` or `fix/<ticket-id>-<slug>`), and emit `.agent/lifecycle-state.json`.
3. If the user already checked out a dedicated feature or worktree branch for this ticket, verify working tree readiness and record the active branch context.

### Stage 2: Code Modification Loop (`dev-tdd`)

1. Call the Skill tool with `dev-tdd` (or follow `skills/dev-tdd/SKILL.md`).
2. Confirm the public **seams** under test (using the seams defined in the spec/ticket, or confirming with the user if unspecified).
3. Implement the ticket one vertical slice at a time:
   - Write one failing test at the public seam (**Red**).
   - Write the minimal production implementation to pass the test (**Green**).
   - Run targeted test files and static typechecking after each slice.
4. Once all acceptance criteria are implemented, execute the full project test suite and typechecker to confirm zero regressions.

### Stage 3: Two-Axis Code Review (`review-diff`)

1. Call the Skill tool with `review-diff` against the base branch or starting commit (`git diff <base>...HEAD`).
2. Audit the changes across both independent axes via parallel fresh-context subagents:
   - **Standards Axis**: Repository coding standards + Fowler code smell baseline.
   - **Spec Axis**: Complete fidelity to the ticket/spec acceptance criteria without scope creep.
3. Remediate any hard standard violations or missing spec requirements identified by `review-diff` and re-verify tests.

### Stage 4: Selective Staging & Commit Drafting (`git-commit-stager`)

1. Invoke `git-commit-stager` to audit the dirty working tree via `git status --porcelain=v1`.
2. Stage modified and created files strictly by explicit pathspec (`git add -- "$FILE"`), filtering out untracked scratch artifacts or sensitive files.
3. Generate a validated Conventional Commits 1.0.0 message and write `.agent/commit-staging-manifest.json`.

### Stage 5: Pre-Flight Safety Audit & Commit (`git-safety-guard`)

1. Invoke `git-safety-guard` to consume `.agent/commit-staging-manifest.json`.
2. Audit staged additions for plaintext secrets, oversized blobs, and binary artifacts, run non-interactive lint/test suites under worktree isolation, and execute the official `git commit`.
3. If working from a local `.scratch/` ticket, update its `**Status:**` to `resolved`.
