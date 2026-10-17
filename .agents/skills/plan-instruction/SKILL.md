---
name: plan-instruction
description: Ingests workspace context, repository layout, and PLAN stage artifacts (agent topologies, modular skills, and lifecycle hooks) to synthesize an authoritative, production-grade GEMINI.md instruction file. Triggers when initializing a workspace, finalizing the PLAN phase, compiling agent architectures, or updating global rules. Do not trigger for writing application code, executing tests directly, or handling simple single-turn prompts.
---
# Gemini MD Architect

System context engineer skill for synthesizing workspace realities and PLAN phase specifications into an authoritative, production-grade `GEMINI.md` project instruction file.

## When to Use

Activate this skill when:

- Initializing a new repository or workspace instruction file (`GEMINI.md`).
- Finalizing the PLAN stage after running `agent-architect`, `skill-recommender`, and `hook-recommender`.
- Consolidating multi-agent topologies, modular skill mappings, and lifecycle hooks into global runtime instructions.
- Updating or refactoring project-wide system directives, runtime guardrails, or build workflows.

Do not activate when:

- Implementing application features or writing business logic directly.
- Executing tests, running linters, or debugging build scripts.
- Designing individual agent roles or authoring isolated `SKILL.md` files.
- Responding to single-turn queries that do not alter global workspace governance.

---

## Discovery and Ingestion Pipeline

Execute the three-stage ingestion pipeline sequentially before drafting `GEMINI.md`:

### Stage 1: Workspace Reality Ingestion

1. Inspect root filesystem, directory structure, and version control status (`git status --porcelain`).
2. Parse dependency manifests to identify languages, runtimes, package managers, and toolchains:
   - Node.js / TypeScript: `package.json`, `tsconfig.json`, `pnpm-lock.yaml`, `yarn.lock`
   - Python: `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.cfg`
   - Rust: `Cargo.toml`, `Cargo.lock`
   - Go: `go.mod`, `go.sum`
   - General build systems: `Makefile`, `Dockerfile`, `docker-compose.yml`, `.github/workflows/`
3. Inspect existing command runners, scripts, and linters to extract exact verification commands (`npm test`, `pytest`, `cargo test`, `eslint`, `flake8`, `golangci-lint`).

### Stage 2: Synthesis of PLAN Stage Artifacts

Consolidate outputs generated across preceding planning modules:

1. **Agent Architecture (from `agent-architect`)**:
   - Agent roles, unique slugs, model tier assignments (Flash vs. Pro), and tool allowlists.
   - Interaction topology (Supervisor-Worker, Critic-in-the-Loop, State Relay).
   - Loop governance: entry criteria, evaluation gates, and hard iteration caps ($N \le 5$).
2. **Modular Skills Inventory (from `skill-recommender`)**:
   - Approved skills matrix categorized across loop phases (Plan, Execute, Verify, Refine).
   - Capability triggers and documentation grounding for each skill.
3. **Runtime Hooks and Gates (from `hook-recommender`)**:
   - Interceptors, post-execution verifiers, and convergence loop gates.
   - Hook execution policies (Fail-Closed, Retry, Alert) and trigger paths in `.gemini/hooks/`.

### Stage 3: Verification of Ecosystem Standards

1. Conduct targeted web search queries to verify modern context engineering conventions, formatting standards, and platform configuration specifications.
2. Confirm current conventions for model system instructions:
   - Delimiter syntax (markdown headings, XML tags, code blocks).
   - High-density constraint expression.
   - Behavioral invariants and negative guardrail structures.

---

## Context Engineering Guidelines

Enforce strict context engineering rules when authoring `GEMINI.md`:

1. **High Signal-to-Noise Ratio**: Eliminate conversational filler, redundant greetings, and vague aspirations. Use direct, imperative directives ("Execute tests via...", "Never mutate...").
2. **Token Budget Discipline**: Keep instructions compact, scannable, and dense. Use tables for multi-variable mappings and bulleted lists for sequential constraints.
3. **Structural Delimiters**: Separate distinct operational domains with explicit Markdown headings (`##`, `###`) and horizontal rules (`---`).
4. **Explicit Anti-Patterns**: Every directive must clearly define boundaries. State explicit negative constraints ("DO NOT") to prevent common model regressions and hallucinations.

---

## Target `GEMINI.md` Blueprint

Construct the target `GEMINI.md` file using the following six-section schema:

```markdown
# [Project Name] - System Instructions & Workspace Context

## 1. Project Mission & Core Architecture
- One-paragraph technical summary of purpose and domain.
- Core design patterns, runtime stack, and workspace topology.

## 2. Multi-Agent Orchestration & Loop Topology
- Roles, model assignments, and permissions (synthesized from agent-architect).
- Feedback loop state machines, handoffs, and deterministic exit gates.

## 3. Modular Skills & Capability Map
- Inventory of enabled workspace skills and when to invoke each.

## 4. Runtime Hooks & Safety Governance
- Pre-execution assertions, post-execution verifiers, and loop convergence hooks.

## 5. Development Workflows & Commands
- Exact bash commands for build, test, lint, format, and local simulation.

## 6. Critical Guardrails & Negative Constraints
- Strictly forbidden operations, security boundaries, and edge-case invariants.
```

---

## Operational Workflow

Follow this sequence to inspect, synthesize, validate, and write `GEMINI.md`:

### Step 1: Context Audit

Run read-only workspace inspections to collect repo metadata, manifests, active skills, and hook scripts. Assemble all PLAN outputs into an active planning context buffer.

### Step 2: Content Drafting

Draft the complete `GEMINI.md` strictly adhering to the Target Blueprint. Populate every section with project-specific commands, schemas, and table definitions without placeholders.

### Step 3: Verification Audit

Audit the draft against the completeness checklist:

- [ ] Contains all six blueprint sections.
- [ ] Incorporates agent profiles and loop constraints ($N \le 5$) from `agent-architect`.
- [ ] Maps modular skills across all four loop phases (Plan, Execute, Verify, Refine) from `skill-recommender`.
- [ ] Integrates lifecycle interceptors and hook scripts from `hook-recommender`.
- [ ] Provides runnable bash commands for build, lint, and test suites.
- [ ] Contains a dedicated Negative Constraints section with explicit prohibitions.
- [ ] Contains zero em-dashes, en-dashes, or conversational filler.

### Step 4: Emission and Storage

Present the complete `GEMINI.md` within a fenced markdown block for user review, or write the file directly to the workspace root or `.gemini/GEMINI.md` when requested.

---

## Operational and Negative Constraints

- Never use em-dashes or en-dashes; use standard hyphens or colons.
- Never output vague summaries or incomplete placeholder templates (`TODO`, `<insert code>`).
- Never combine unrelated responsibilities; keep `GEMINI.md` focused on system instructions, agent governance, and workspace context.
- Keep `SKILL.md` body concise, procedural, and under 500 lines.