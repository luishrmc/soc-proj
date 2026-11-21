---
name: env-retro
description: "Conduct a post-session retrospective to upgrade the coding agent environment across navigation pointers, automated checks, coding standards, and steering files."
disable-model-invocation: true
---

# Agent Environment Retrospective

Audit a completed coding session to improve the **agent environment** (steering pointers, automated checks, review standards, and tool ergonomics) so future sessions execute with lower friction and higher reliability.

## Execution Process

### 1. Load Agent Writing Mechanics and Session Sources

1. Consult `skills/gen-skill/references/skill-mechanics.md` for the context load, pointer, and pruning rules governing steering documents.
2. Inspect the current session context (or the transcript/commit log of a session specified by the user) alongside the repository's `GEMINI.md` / `AGENTS.md` / `CLAUDE.md`, `CODING_STANDARDS.md`, `package.json` / `Makefile`, and `.github/workflows/`.

### 2. Audit Across Seven Environment Categories

Evaluate the session for concrete environment upgrades across these seven levers:

1. **Navigation Pointers**: Did the agent spend excessive turns hunting for files or hidden cross-module dependencies? Propose a concise **context pointer** in `GEMINI.md` / `AGENTS.md` or `GLOSSARY.md`.
2. **Automated Checks & Guardrails**: Did the agent make a mistake that a linter, typechecker, test script, or pre-commit hook (`plan-hooks` / `git-safety-guard`) could catch automatically? Check existing `package.json`/`Makefile`/CI scripts first to wire up unwired checks rather than reinventing them.
3. **Coding Standards (`CODING_STANDARDS.md`)**: Did `review-diff` miss a recurring issue? Classify the mistake first:
   - **Mechanical violations** (banned imports, syntax patterns, file placement) belong in a deterministic linter rule or pre-commit check, never prose.
   - **Genuine judgment calls** (cross-file design consistency, idiom alignment) belong in `CODING_STANDARDS.md` (which is read only during `review-diff`, sparing the implementation agent's context window).
4. **Steering File Bloat (`GEMINI.md` / `AGENTS.md`)**: Are always-loaded steering files carrying bulky rules or stale command caches that should move into `CODING_STANDARDS.md`, automated checks, or disclosed `docs/agents/*.md` files?
5. **Tool Economy**: Did the agent run token-heavy or repetitive shell commands that a compact helper script in `scripts/` would streamline?
6. **No-Op Sediment**: Identify instructions in steering files or skills that repeat default model behavior and recommend deleting them via `/refine-skill`.
7. **Information Access**: Was the agent flying blind because dev server logs, test runner outputs, or schema definitions were inaccessible? Propose a read-only tee or inspection script.

### 3. Present Ranked Environment Upgrades

Present findings ordered from highest to lowest severity. For each candidate, state:

- **Observed Friction**: What went wrong or took too long during the session.
- **Target Artifact**: Exact file, script, linter rule, or skill to create/modify.
- **Proposed Change**: Concrete diff or one-line pointer ready to apply upon user confirmation.
