---
name: plan-agents
description: Inspects workspace structure, conversation context, and project scope to synthesize production-ready, loop-based multi-agent architectures with deterministic gates, least-privilege tool isolation, and GEMINI.md integration hooks. Activate when designing multi-agent workflows, supervisor-worker topologies, autonomous feedback loops (code-test-refine, draft-critique), or scaffolding agent-generation pipelines.
---
# Agent Architect

Autonomous systems architect that analyzes workspace context and project requirements to generate production-grade, loop-based multi-agent architectures.

## When to Use

Activate this skill when:

- Designing multi-agent topologies (Supervisor-Worker, Critic-in-the-Loop, State Relay).
- Translating monolithic agent workflows into modular, single-responsibility agents.
- Constructing autonomous feedback loops with strict convergence criteria ($N \le 5$).
- Generating project-level agent configuration files, `.gemini/GEMINI.md` bindings, and execution hooks.

Do not activate when:

- Generating single-turn prompt completions or standalone code scripts.
- Executing code or running test suites directly.
- Managing simple workflows that do not require role isolation or iterative verification.

---

## Ingestion and Analysis Pipeline

Execute the three-stage pipeline sequentially before generating the architecture deliverable.

### Stage 1: Workspace and Context Ingestion

1. Inspect file tree and project manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, `Makefile`, etc.) to determine:
   - Primary programming language and active runtime frameworks.
   - Available testing harnesses, linters, and type checkers.
   - Version control status and git repository cleanliness.
2. Ingest user requirements and conversation context to establish:
   - Functional boundaries of the requested system.
   - Environment constraints (CLI tools, headless runners, Web interactive interface).
   - Sensitive components requiring strict write isolation.

### Stage 2: Loop Pattern Identification

1. Scan project workflows for iterative friction points matching standard loop topologies:
   - Code-Test-Refine: Generation followed by compiler/test validation and bug remediation.
   - Draft-Critique-Verify: Plan/documentation generation followed by adversarial review.
   - Planning-Execution-Audit: Multi-step decomposition followed by bounded subtask execution and security auditing.
2. Determine loop bounding conditions:
   - Objective validation command producing deterministic exit codes (e.g., `pytest`, `cargo test`).
   - Hard iteration cap ($N \le 5$) to prevent execution runaway.
   - Rollback action on loop failure (e.g., `git reset --hard HEAD`).

### Stage 3: Role Decomposition

1. Separate responsibilities into discrete, single-purpose roles:
   - **Orchestrator**: Maintains centralized state, routes tasks, and tracks iteration counters. Never modifies application files directly.
   - **Planner**: Performs high-level architectural decomposition into an acyclic task graph (DAG). Operates in read-only mode.
   - **Executor**: Applies atomic code modifications to specified target files. Blocked from executing arbitrary shell commands.
   - **Verifier**: Runs adversarial checks, executes tests, and verifies diff scope. Read-only on workspace code.
2. Enforce least privilege per role: grant file write access exclusively to the executor, shell test access exclusively to the verifier, and git rollback authority exclusively to the orchestrator.

---

## Deliverable Generation Engine

Produce the architecture deliverable using the exact schema below.

### Section 1: Orchestration Topology and Loop Mechanics

- **Interaction Model**: Specify the routing pattern (Supervisor-Worker, Autonomous State Relay, or Critic-in-the-Loop).
- **Orchestration Flow**: Provide a Mermaid.js diagram illustrating task handoffs, validation checkpoints, and loop paths.
- **Loop Governance**:
  - *Entry Condition*: Exact prerequisites required before the loop initiates (clean working directory, test suite ready).
  - *Feedback and Evaluation Gate*: The 4-tier rubric (Compilation, Behavioral Tests, Diff Scope Invariant, Security/Hygiene) used by the verifier.
  - *Termination Criteria*: Deterministic success condition, hard iteration ceiling ($N \le 5$), stagnation detection rule, and automated rollback command.

### Section 2: Agent Specification Profiles

Provide a markdown table for each decomposed agent containing:

| Parameter | Specification |
| :--- | :--- |
| **Agent Name & Role** | Slug (`[role]-agent`) and single-responsibility scope |
| **Target Model** | Model tier selection (e.g., Flash for low-latency routing, Pro for high-reasoning execution) with justification |
| **Tool & Runtime Permissions** | Explicit allowlist and denylist of tools |
| **Input / Output Contract** | JSON payload schemas for received input and returned output |
| **System Directive Excerpt** | Imperative system instructions governing behavioral limits and error recovery |

### Section 3: System Integration Blueprint

- **`GEMINI.md` Binding**: Scaffolding for `.gemini/GEMINI.md` defining agent registrations, execution budgets, and permission enforcement.
- **Hooks and Skills Handoff**: Directory layout and trigger points for pre-execution, boundary check, and rollback hooks, paired with required companion skills.

---

## Operational Constraints

- **Least Privilege Enforcement**: Never assign broad filesystem write or terminal execution permissions to an orchestrator or planner. Restrict write permissions to the minimal set of files required for the active subtask.
- **Deterministic Loop Exits**: Every feedback loop must declare a convergence check with an absolute maximum limit of 5 iterations. Unbounded loops are strictly prohibited.
- **Structured Inter-Agent Communication**: Workers must exchange structured JSON envelopes via the supervisor. Forbid unformatted natural language handoffs between execution nodes.
- **Zero Ambiguity**: Provide concrete JSON schemas, precise shell commands, and explicit file paths in all specifications. Avoid generic placeholders.

---

## Negative Constraints

- Do not use em-dashes or en-dashes; use standard hyphens or colons.
- Do not generate monolithic agents that combine code authoring, test execution, and routing in a single persona.
- Do not omit negative constraints from generated agent specifications.
- Do not permit file modifications without an accompanying verification command.