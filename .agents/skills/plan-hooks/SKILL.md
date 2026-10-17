---
name: plan-hooks
description: Inspects workspace context, agent definitions, tool allowlists, and loop topologies to design and recommend lifecycle hooks, validation interceptors, telemetry monitors, and convergence gates. Triggers during lifecycle planning, guardrail audits, safety governance, loop termination design, or runtime setup. Do not trigger for writing application code, executing tests directly, or implementing raw hook script files.
---
# Hook Recommender

Autonomous runtime architect skill for analyzing agent topologies, tool permissions, and operational risk boundaries to recommend deterministic lifecycle hooks, validation interceptors, and loop gates.

## When to Use

Activate this skill when:

- Planning agent runtime lifecycles and governance guardrails.
- Auditing multi-agent topologies for unbounded recursion, unverified code synthesis, or state corruption risks.
- Designing pre-execution interceptors, post-execution verifiers, and convergence termination gates.
- Configuring `.gemini/GEMINI.md` runtime hook registrations and middleware pipelines.

Do not activate when:

- Writing application feature code or business logic.
- Executing test suites or running CI/CD scripts directly.
- Authoring final shell scripts or hook implementations during the recommendation phase.
- Handling simple single-turn prompts without multi-agent execution or state mutation.

---

## Lifecycle Hook Taxonomy

Every recommended hook must be mapped to one of four deterministic lifecycle phases:

### 1. Pre-Step / Interceptor

- **Role**: Validates preconditions, sanitizes inputs, snapshots workspace state, and gates tool permissions before agent execution.
- **Characteristics**: Typically blocking. Prevents agent invocation if prerequisites fail (e.g., dirty git tree, missing dependencies, unauthorized tool scope).

### 2. Mid-Execution / Telemetry

- **Role**: Observes runtime execution in-flight, tracks latency, logs tool calls, enforces rate limits, and monitors recursion depth.
- **Characteristics**: Primarily non-blocking to preserve execution throughput, escalating to blocking only when rate limits or safety boundaries are breached.

### 3. Post-Step / Verifier

- **Role**: Inspects agent artifacts, diffs, and output payloads against deterministic validation suites (syntax linters, schema validators, unit tests).
- **Characteristics**: Strictly blocking. Rejects unverified mutations or malformed payloads before they propagate downstream.

### 4. Convergence / Loop Gate

- **Role**: Manages loop state machines, tracks iteration budgets ($N \le 5$), enforces exit conditions, and handles rollback actions.
- **Characteristics**: Strictly blocking. Halts execution or rolls back state when loop budgets are exhausted or convergence stagnation is detected.

---

## Discovery and Ingestion Workflow

Execute the three-stage audit sequentially before generating hook recommendations.

### Stage 1: Context and Workflow Analysis

1. Inspect `.gemini/GEMINI.md` and workspace configuration files to map:
   - Active agent roles, interaction topologies (Supervisor-Worker, State Relay), and routing contracts.
   - Declared tool allowlists, runtime access levels, and execution privileges per agent.
2. Inspect package manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, etc.) and repository layout to determine available validation tooling (linters, test harnesses, typecheckers).
3. Identify existing git hooks, CI pipelines, and existing hook scripts in `.gemini/hooks/` or `.husky/`.

### Stage 2: Failure Surface Audit

1. Identify critical risk surfaces across agent interactions:
   - State mutation risks: Unchecked file edits, unauthorized deletions, or out-of-scope diffs.
   - Shell and execution risks: Execution of unvetted terminal commands, environment pollution, or secret exposure.
   - Loop runaway risks: Unbounded retry loops, oscillation between failing states, or missing iteration counters.
   - Silent failures: Suppressed exit codes, hallucinated payload schemas, or unvalidated tool responses.
2. Establish failure boundaries requiring strict, blocking verification vs. telemetry observation.

### Stage 3: Interceptor-to-Profile Binding

1. Bind interceptors to specific handoff edges in the agent topology:
   - Pre-execution gates to Planner and Executor handoffs.
   - Boundary verifiers immediately following Executor file writes.
   - Feedback and convergence gates between Verifier and Orchestrator state transitions.
2. Ensure every autonomous feedback loop is bound to at least one blocking post-step verifier and one loop-gate termination hook.

---

## Standardized Output Schema

Present findings using the four-section layout below:

### 1. Workspace Safety & Integrity Assessment

- **Risk Profile Summary**: Core vulnerability points (uncontrolled file mutations, external network access, unbounded retry loops).
- **Side-Effect Boundaries**: Isolated agents vs. privileged mutation agents.
- **Loop Governance Status**: Assessment of existing loop termination guards and convergence controls.

### 2. Recommended Hooks Matrix

| Hook Identifier | Lifecycle Phase | Attached Agent / Tool | Execution Type (Blocking / Non-Blocking) | Failure Policy (Fail-Closed / Retry / Alert) | Purpose & Value Justification |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `[slug-id]` | `Pre-Step` / `Mid-Execution` / `Post-Step` / `Convergence` | `[Agent slug or tool name]` | `Blocking` / `Non-Blocking` | `Fail-Closed` / `Retry` / `Alert` | `[Concise operational justification]` |

*Field Definitions:*

- **Execution Type**: `Blocking` (halts execution until pass) or `Non-Blocking` (runs asynchronously or emits telemetry without halting).
- **Failure Policy**: `Fail-Closed` (immediately halts pipeline and triggers rollback), `Retry` (re-queues action with feedback), or `Alert` (logs warning and continues).

### 3. Hook Implementation Blueprint

For each critical blocking hook, provide:

- **Hook Trigger Mechanism**: Execution type (e.g., shell script, Node.js/Python script, git hook, or runtime middleware).
- **Input Payload Contract**: JSON schema or stdin payload passed to the hook.
- **Exit Code & Contract**: Deterministic exit codes (`0` for success, non-zero for failure) and structured failure diagnostic schema emitted to stderr/stdout.
- **Remediation Action**: Automated action triggered on failure (e.g., `git reset --hard HEAD`, feedback packet routing).

### 4. Integration with `GEMINI.md`

Scaffold the runtime configuration block for `.gemini/GEMINI.md` registering the recommended hooks into the agent execution pipeline.

---

## Operational and Negative Constraints

- Apply least intrusion: Use non-blocking telemetry for passive metrics; reserve blocking execution strictly for destructive mutations, verification gates, and loop termination.
- Guarantee deterministic exits: Every multi-agent loop must enforce a hard cap of $N \le 5$ iterations via a convergence loop gate.
- Output recommendations and blueprints only: Do not generate full production code scripts or execute commands during recommendation.
- Do not use em-dashes or en-dashes anywhere in output; use standard hyphens or colons.
- Eliminate vague advice: Provide exact script paths, payload schemas, and exit code specifications.