---
name: plan-instruction
description: "Synthesize repository conventions and planning artifacts into a concise, pointer-driven GEMINI.md or AGENTS.md steering file."
disable-model-invocation: true
---

# Steering File Architect (`GEMINI.md` / `AGENTS.md`)

Compile workspace conventions and planning outputs from `plan-agents`, `router-skills`, and `plan-hooks` into a high-signal, low-context-load `GEMINI.md`, `AGENTS.md`, or `CLAUDE.md` steering file.

## Context Load & Pointer Principles

Every line in `GEMINI.md` / `AGENTS.md` sits permanently in the agent's context window on every turn. Protect the context window by enforcing three rules:

1. **Prefer Context Pointers Over In-File Dumps**: State what an out-of-context document contains and the branch condition for reading it (`See docs/agents/issue-tracker.md`, `See GLOSSARY.md`), rather than pasting long schemas or reference tables into the steering file.
2. **Treat the Environment as Source of Truth**: Cache only unwritten architectural conventions, non-obvious gotchas, and pointer paths. Leave standard one-file lookups (`package.json` scripts, directory trees) to the environment so the steering file never rots.
3. **Positive, High-Leverage Directives**: Express rules as concrete positive actions ("Run single test files after each red-green slice") and prune no-op sentences that models already follow by default.

## Ingestion Pipeline

### Stage 1: Workspace Reality Check

1. Inspect existing root instruction files (`GEMINI.md`, `AGENTS.md`, `CLAUDE.md`) and `docs/agents/*` pointer targets configured by `/setup-workspace`.
2. Inspect project manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Makefile`) to identify the verification commands that aren't obvious from a glance.

### Stage 2: Synthesis of Planning Artifacts

Consolidate outputs from prior planning skills if present in the session or repository:

1. **Agent Topology (from `plan-agents`)**: Role boundaries, fresh-context subagent rules, and loop convergence caps ($N \le 5$).
2. **Skill Routing (from `router-skills`)**: Active user-invoked orchestrators (`/shape-grill`, `/shape-spec`, `/shape-tickets`, `/dev-implement`, `/dev-parallel`) and model-invoked disciplines (`dev-tdd`, `review-diff`, `git-safety-guard`).
3. **Runtime Guardrails (from `plan-hooks`)**: Pre-step and post-step verification gates.

## Target Steering File Blueprint

Keep the generated steering file compact (under 100 lines) using this five-section structure:

```markdown
# <Project Name> - Agent Steering Instructions

## 1. Domain & Architecture Pointers
- Ubiquitous language lives in `GLOSSARY.md`. Read it before naming symbols, tests, or tickets.
- Architectural decisions live in `docs/adr/`. Flag any conflict before overriding an ADR.
- Issue tracker and triage conventions: see `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`.

## 2. Development Flow & Skill Routing
- Shaping: `/shape-grill` -> `/shape-spec` -> `/shape-tickets` in one unbroken context window.
- Execution: `/dev-implement` (single ticket) or `/dev-parallel` (multi-ticket worktree DAG), driving `dev-tdd` at confirmed public seams and closing with `review-diff`.
- Commits: Stage explicit pathspecs via `git-commit-stager` and commit via `git-safety-guard`.

## 3. Verification Commands
- Typecheck: `<exact command>`
- Single test file: `<exact command>`
- Full test suite & linter: `<exact command>`

## 4. Subagent & Context Hygiene
- Start every exploration, implementation, and review subagent with a fresh context window.
- Pass file paths and issue references as context pointers rather than duplicating text.

## 5. Non-Obvious Repository Conventions
- <Concise bullet list of repo-specific invariants that cannot be inferred from config files>
```

## Verification Checklist

- [ ] References `plan-agents`, `router-skills`, and `plan-hooks` accurately where applicable.
- [ ] Uses context pointers to `GLOSSARY.md`, `docs/adr/`, and `docs/agents/*` rather than inlining large reference blocks.
- [ ] Keeps total steering file length under 100 lines with zero em-dashes or en-dashes.
