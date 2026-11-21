# Design It Twice (Parallel Interface Exploration)

Use this parallel subagent workflow when exploring alternative interface shapes for a module or deepening candidate (based on John Ousterhout's *Design It Twice* principle).

## Execution Process

### 1. Frame the Problem Space for the User

Present a concise overview of the design problem before launching subagents:

- Core invariants and behavioral requirements the interface must satisfy
- Dependency category from [references/deepening.md](../references/deepening.md)
- A brief illustrative sketch grounding the constraints

### 2. Dispatch 3+ Parallel Subagents with Orthogonal Constraints

Spawn at least three subagents concurrently, each in a **fresh context window**, providing the target file paths, `GLOSSARY.md` terms, and `arch-design` vocabulary. Assign each subagent a distinct design objective:

- **Subagent 1 (Maximum Depth)**: *"Minimize surface area to 1-3 entry points maximum. Hide maximum orchestration complexity behind the seam."*
- **Subagent 2 (Caller Ergonomics)**: *"Optimize for the 90% common caller path so default usage requires minimal parameters and zero setup boilerplate."*
- **Subagent 3 (Explicit Ports & Extensibility)**: *"Design around explicit data-oriented inputs/outputs and composable boundary adapters."*

Require each subagent to return:

1. Public interface signature (types, methods, invariants, error modes)
2. Concrete caller usage example
3. Complexity hidden inside the implementation
4. Adapter and seam testing strategy
5. Trade-offs (where leverage is high vs. where flexibility is constrained)

### 3. Compare and Recommend

Present the designs sequentially, contrast them across **depth**, **locality**, and **seam placement**, and state an opinionated recommendation (or synthesized hybrid) with clear justification.
