---
name: router-skills
description: "Route your current engineering, shaping, architecture, debugging, planning, or git task to the right skill or workflow in this repository."
disable-model-invocation: true
---

# Workspace Skill & Workflow Router

Navigate the 29 modular skills in this repository without memorizing every slash command. Before recommending that a user skip a step or describing a skill's internals, read that skill's `SKILL.md` directly.

## 1. The Main Flow (`Idea -> Ship`)

The primary software delivery spine. Keep steps 1 to 3 in **one unbroken context window** (inside the ~150k token smart zone), then clear or delegate per ticket in step 4:

1. **`/setup-workspace`** *(Once per repo)*: Configure `docs/agents/issue-tracker.md`, `GLOSSARY.md` layout, and steering context pointers.
2. **`/shape-grill`**: Stateful design-tree interview (`shape-grilling`) that updates `GLOSSARY.md` and `docs/adr/` inline (`shape-domain`).
   - *Detours during grilling*: Need runnable state/UI answers? Use `/env-handoff` -> `shape-prototype` -> `/env-handoff`. Need external API/doc facts? Dispatch `research-topic`.
3. **`/shape-spec`** -> **`/shape-tickets`**: Synthesize the agreed design into a path-free spec with confirmed public test **seams**, then slice into dependency-ordered **tracer-bullet** tickets.
4. **Execute Tickets**:
   - **Single Ticket**: Run **`/dev-implement`** (executes the 5-stage pipeline: `git-branch-lifecycle` -> `dev-tdd` -> `review-diff` -> `git-commit-stager` -> `git-safety-guard`). Clear context (`/clear`) between tickets.
   - **Full Multi-Ticket Spec**: Run **`/dev-parallel`** to dispatch parallel fresh-context implementer subagents in isolated git worktrees across the unblocked DAG **frontier**.
5. **`/env-retro`**: Audit the completed session to upgrade navigation pointers, automated checks, and `CODING_STANDARDS.md`.

## 2. On-Ramps & Specialized Flows

| Situation / Goal | Entry Command or Skill | How It Connects |
| :--- | :--- | :--- |
| **Huge, foggy multi-session epic** | **`/shape-wayfinder`** | Charts a `wayfinder:map` of decision tickets; once clear, merges into `/shape-spec`. |
| **Hard bug or performance regression** | **`debug-loop`** *(Model-invoked)* | Builds a tight **red feedback loop**, minimizes repro, tests ranked hypotheses, and locks fix at a seam. |
| **Codebase feels shallow or tangled** | **`/arch-survey`** + **`arch-design`** | Scans high-churn modules with the deletion test, renders an HTML report in `$TMPDIR`, and grills on candidates. |
| **Review a branch or diff standalone** | **`review-diff`** *(Model-invoked)* | Spawns parallel **Standards** (repo rules + Fowler smells) and **Spec** review subagents. |
| **Switch harness, directory, or session** | **`/env-handoff`** | Compacts session pointers into `$TMPDIR` without duplicating repo files. |
| **Design multi-agent loops, hooks, or `GEMINI.md`** | **`/plan-agents`** -> **`/plan-hooks`** -> **`/plan-instruction`** | Architects bounded ($N \le 5$) multi-agent systems and pointer-driven steering files. |
| **Optimize prompts, prose, or `SKILL.md` files** | **`refine-prompt`**, **`refine-text`**, **`/gen-skill`**, **`/refine-skill`** | Dual-mode prompt engineering (Markdown/Pydantic), hype-free prose, and skill authoring/pruning. |
| **Stage and verify Git commits safely** | **`git-branch-lifecycle`** -> **`git-commit-stager`** -> **`git-safety-guard`** | Enforces clean base sync, explicit pathspec staging, secret scanning, and stash-isolated test gates. |

## 3. Managing Phase Boundaries

At the boundary between two phases (e.g., after `/shape-tickets` or after a bug fix), consult [references/phase-boundaries.md](./references/phase-boundaries.md) to choose in strict order between **Continue**, **`/clear`**, **`/env-handoff`**, **Subagent**, and **`/compact`**.
