---
name: plan-skill
description: Inspects workspace context, dependency manifests, and conversation history to evaluate project scope and recommend a prioritized, loop-aligned suite of modular skills. Triggers during project planning, architectural setup, workspace scoping, or when auditing missing capabilities for autonomous workflows. Do not trigger for direct code implementation, single-turn prompts, or when executing existing skills.
---
# Skill Recommender

System skill for analyzing workspace constraints and project requirements to recommend a prioritized, loop-mapped suite of modular agent skills grounded in verified ecosystem documentation.

## When to Use

Activate this skill when:

- Scoping a new software project, workspace, or multi-agent pipeline.
- Auditing existing workspace configurations (`GEMINI.md`, skill manifests) for missing operational skills.
- Establishing an iterative development loop (Plan, Execute, Verify, Refine) and determining required agent capabilities.
- Evaluating architectural dependencies and identifying specialized tooling needs before implementation.

Do not activate when:

- Implementing application code or authoring full skill files directly.
- Executing an existing operational skill or running tests.
- Handling trivial single-turn requests that do not involve project architecture or multi-agent workflows.

---

## Ingestion and Discovery Workflow

Execute the following three-stage discovery pipeline sequentially before formulating skill recommendations:

### Stage 1: Workspace Context Ingestion

1. Inspect project root and directory trees to detect project structure, configuration files, and existing skill directories.
2. Parse dependency manifests to identify languages, runtimes, package managers, and core frameworks:
   - Node.js / TypeScript: `package.json`, `tsconfig.json`, `pnpm-lock.yaml`, `yarn.lock`
   - Python: `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.cfg`
   - Rust: `Cargo.toml`, `Cargo.lock`
   - Go: `go.mod`, `go.sum`
   - General build systems: `Makefile`, `Dockerfile`, `docker-compose.yml`, GitHub Actions workflows in `.github/workflows/`
3. Inspect project configuration files:
   - Check `.gemini/GEMINI.md` or repository guidelines for established project rules, agent roles, and execution policies.
   - Catalog existing installed skills to avoid redundant recommendations.

### Stage 2: Functional Gap Identification

1. Compare user scope and technical goals against detected workspace tools.
2. Identify missing operational capabilities across four primary vectors:
   - Domain-specific execution (e.g., specialized ORM handling, API client generation, LaTeX authoring).
   - Verification and testing (e.g., test runner isolation, linter gates, mutation testing, schema validation).
   - Automated remediation (e.g., patch generation from compiler diagnostics, regression fixing).
   - Governance and orchestration (e.g., DAG task planning, dependency boundaries).
3. Record each gap with concrete failure modes that would occur if unaddressed (e.g., hallucinated API endpoints, silent test failures, unformatted outputs).

### Stage 3: Ecosystem Verification via Live Search

1. Formulate targeted search queries to verify official documentation, stable package releases, and current ecosystem standards for each candidate capability.
2. Filter candidate tools and skill patterns against strict criteria:
   - Must cite official documentation, active repositories, or established design standards.
   - Reject unmaintained packages, deprecated APIs, archived tools, and hypothetical libraries.
   - Confirm compatibility with the project runtime version identified in Stage 1.
3. Normalize recommendations into modular, single-responsibility skill concepts.

---

## Loop Philosophy Mapping

Every recommended skill must be explicitly assigned to one of four iterative execution loop phases:

- **Phase 1: Plan**: Scoping, task breakdown, interface contract design, and architectural governance. Skills in this phase define task boundaries and produce structured execution specifications.
- **Phase 2: Execute**: Domain-specific implementation, code generation, patch drafting, and content authoring. Skills in this phase perform atomic modifications based on Plan phase specifications.
- **Phase 3: Verify / Critique**: Static analysis, type checking, test execution, schema validation, and security auditing. Skills in this phase evaluate candidate outputs against deterministic rubrics without modifying application code.
- **Phase 4: Refine**: Automated feedback patching, test-driven remediation, diagnostic analysis, and loop convergence checks. Skills in this phase remediate failures identified in Verify and decide whether to loop or terminate ($N \le 5$).

---

## Standardized Output Schema

Present all recommendations using the following four-part layout:

### 1. Workspace and Stack Diagnostics

- **Detected Runtime & Languages**: List detected languages, runtimes, and package managers.
- **Core Frameworks & Tools**: List web frameworks, ORMs, test harnesses, and linters found.
- **Project Scope & Architecture**: Summary of user goals and workflow requirements.
- **Existing Skills**: Catalog of skills already configured in the workspace.

### 2. Recommended Skills Matrix

| Skill Slug | Loop Phase | Capability Provided | Official Reference / Documentation Grounding | Priority (Critical / Recommended / Optional) |
| :--- | :--- | :--- | :--- | :--- |
| `[slug-name]` | `Plan` / `Execute` / `Verify` / `Refine` | `[Concise description of operational role]` | `[Official package/tool URL or standard documentation reference]` | `Critical` / `Recommended` / `Optional` |

*Priority Definitions:*

- **Critical**: System cannot execute, test, or verify correctly without this skill.
- **Recommended**: Prevents frequent regressions, improves code quality, or enforces consistency.
- **Optional**: Provides ergonomics, advanced telemetry, or secondary optimizations.

### 3. Loop Mechanics and Justification

- **Capability Justifications**: Provide rationale for each recommended skill, specifying how it resolves an identified functional gap.
- **Interaction Flow**: Detail the sequence showing how the output of each skill transitions into the next:
  1. How Plan output formats hand off to Execute skills.
  2. How Execute diffs or artifacts transition to Verify validation gates.
  3. How Verify diagnostic logs route into Refine remediation loops.
  4. Explicit termination conditions and convergence bounds ($N \le 5$).

### 4. Implementation Roadmap

Numbered list of recommended skills in order of creation, prioritizing foundation skills (Phase 1 and Phase 3 test gates) before execution and refinement modules.

---

## Operational and Negative Constraints

- Recommend capabilities and structural mappings only; do not generate full skill code or implementation files during recommendation.
- Ground every recommendation in verified ecosystem documentation; never invent package names or hallucinate APIs.
- Assign each skill a single, well-defined responsibility; never recommend monolithic skills combining execution, verification, and orchestration.
- Enforce loop termination bounds; all refinement and verification loops must specify a maximum iteration cap of 5 cycles.
- Do not use em-dashes or en-dashes anywhere in output; use standard hyphens or colons.