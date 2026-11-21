---
name: plan-agents
description: "Synthesize loop-based multi-agent architectures with deterministic convergence gates, least-privilege tool isolation, and GEMINI.md pointers."
disable-model-invocation: true
---

# Multi-Agent Topology Architect

Analyze workspace structure and project requirements to design bounded, single-responsibility multi-agent topologies (Supervisor-Worker, Critic-in-the-Loop, or Autonomous State Relay).

## Ingestion and Analysis Pipeline

Execute three sequential stages before generating the architecture deliverable:

### Stage 1: Workspace and Context Ingestion

1. Inspect repository manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Makefile`) to identify active languages, test runners, linters, and typecheckers.
2. Read `GLOSSARY.md`, `docs/adr/`, and user requirements to establish functional boundaries and sensitive paths requiring write isolation.

### Stage 2: Loop Pattern Identification

1. Map iterative workflows to bounded loop topologies:
   - **Code-Test-Refine**: Implementation (`dev-tdd`) followed by compiler/test validation and remediation.
   - **Draft-Critique-Verify**: Artifact generation followed by parallel two-axis review (`review-diff`).
   - **Plan-Execute-Audit**: DAG task decomposition (`shape-tickets`) followed by worktree execution (`dev-parallel`) and safety gating (`git-safety-guard`).
2. Define deterministic loop exit conditions:
   - Objective verification command returning exit code `0`.
   - Hard iteration ceiling ($N \le 5$) preventing unbounded execution.
   - Clean rollback command (`git checkout --` or worktree reset) when the iteration budget is exhausted.

### Stage 3: Single-Responsibility Role Decomposition

Decompose workflows into isolated roles with strict least-privilege tool permissions:

- **Orchestrator**: Maintains task-graph state, tracks iteration counters, and routes context pointers. Read-only on application source code.
- **Planner**: Decomposes specs into acyclic ticket graphs (`shape-tickets`). Read-only mode.
- **Executor**: Applies atomic code changes within an assigned worktree or file scope (`dev-tdd`).
- **Verifier**: Runs test suites, static analysis, and two-axis diff audits (`review-diff`). Read-only on application source code.

## Deliverable Schema

### Section 1: Orchestration Topology and Loop Mechanics

- **Interaction Model**: Routing pattern (Supervisor-Worker, State Relay, or Critic-in-the-Loop) with a Mermaid flowchart showing handoffs and verification gates.
- **Loop Governance**: Entry prerequisites, 4-tier verification rubric (Compilation, Behavioral Seam Tests, Diff Scope, Secret/Artifact Hygiene), and termination criteria ($N \le 5$).

### Section 2: Agent Specification Profiles

Provide a specification table for each decomposed agent:

| Parameter | Specification |
| :--- | :--- |
| **Agent Name & Role** | Slug (`[role]-agent`) and single-responsibility scope |
| **Target Model** | Model tier (Flash for low-latency routing, Pro for high-reasoning synthesis) |
| **Tool Permissions** | Explicit allowlist of permitted tools |
| **Context Pointer Contract** | Input and output schemas passing file/issue pointers rather than duplicated payloads |
| **System Directive** | Positive, imperative instructions and completion criteria |

### Section 3: System Integration Blueprint

- **Context Pointers**: Lightweight registration block for `GEMINI.md` / `AGENTS.md` linking to agent definitions and companion `plan-hooks` interceptors.
