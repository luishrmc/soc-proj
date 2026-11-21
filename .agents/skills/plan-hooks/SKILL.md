---
name: plan-hooks
description: "Design deterministic lifecycle hooks, validation interceptors, telemetry monitors, and loop convergence gates for agent workflows."
disable-model-invocation: true
---

# Lifecycle Hook Architect

Analyze agent topologies, tool permissions, and failure surfaces to design deterministic pre-step interceptors, mid-execution telemetry, post-step verifiers, and loop convergence gates.

## Lifecycle Hook Taxonomy

Map every recommended hook to one of four lifecycle phases:

1. **Pre-Step Interceptor (Blocking)**: Validates preconditions (clean git tree via `git-branch-lifecycle`, required manifests, path allowlists) before agent or tool execution begins.
2. **Mid-Execution Telemetry (Non-Blocking)**: Tracks tool invocation counts, latency, and recursion depth; escalates to blocking only when rate limits or safety boundaries are breached.
3. **Post-Step Verifier (Blocking)**: Inspects mutations and staged diffs against deterministic checks (linters, typecheckers, seam tests, and `git-safety-guard` secret scans).
4. **Convergence Gate (Blocking)**: Tracks loop iteration counters ($N \le 5$), detects identical-error stagnation, and triggers clean rollback or human escalation when the budget is reached.

## Audit and Binding Pipeline

### Stage 1: Context and Toolchain Discovery

1. Inspect `GEMINI.md`, `AGENTS.md`, `CLAUDE.md`, and `plan-agents` profiles to map active roles and tool scopes.
2. Parse repository manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, `Makefile`) to extract existing deterministic check commands.
3. Inspect existing hooks in `.gemini/hooks/`, `.claude/hooks/`, `.husky/`, or `.git/hooks/`.

### Stage 2: Failure Surface Mapping

Identify high-risk mutation edges requiring blocking enforcement:

- Destructive Git or filesystem operations (`git push --force`, `git reset --hard`, out-of-worktree writes).
- Unverified code commits bypassing lint or test suites.
- Unbounded retry oscillations on failing tests.

### Stage 3: Handoff Binding

Bind each autonomous feedback loop to at least one blocking **Post-Step Verifier** and one **Convergence Gate** ($N \le 5$).

## Standardized Output Schema

### 1. Workspace Safety Assessment

- **Risk Profile**: Primary mutation and execution surfaces.
- **Loop Governance**: Evaluation of current iteration caps and rollback boundaries.

### 2. Recommended Hooks Matrix

| Hook ID | Lifecycle Phase | Target Agent / Tool | Execution Mode | Failure Policy | Operational Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `[slug-id]` | `Pre-Step` / `Mid-Execution` / `Post-Step` / `Convergence` | `[Agent or tool]` | `Blocking` / `Non-Blocking` | `Fail-Closed` / `Retry` / `Alert` | `[Concise justification]` |

### 3. Hook Implementation Blueprint

For each blocking hook, specify:

- **Trigger & Script Path**: Executable path (e.g., `.gemini/hooks/<hook-name>.sh`).
- **Input Payload & Exit Codes**: Stdin JSON schema, exit `0` on pass, non-zero exit codes with structured diagnostic stderr on block.
- **Remediation Action**: Automated recovery command or context pointer routed back to the agent.
