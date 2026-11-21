---
name: shape-domain
description: Build and sharpen a project's ubiquitous domain model. Use when discussing codebase terminology, resolving overloaded domain concepts, writing or updating GLOSSARY.md, or recording Architecture Decision Records (ADRs) in docs/adr/.
---

# Domain Modeling

Actively build and sharpen the project's domain model while designing features. This skill governs the *active* modeling discipline: challenging imprecise terms, stress-testing relationships with concrete scenarios, and persisting resolved definitions and architectural decisions immediately.

## Repository Layout

Most repositories use a single bounded context:

```text
/
├── GLOSSARY.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

When `GLOSSARY-MAP.md` exists at the repository root, the project spans multiple bounded contexts:

```text
/
├── GLOSSARY-MAP.md
├── docs/
│   └── adr/                          <- system-wide decisions
└── src/
    ├── ordering/
    │   ├── GLOSSARY.md
    │   └── docs/adr/                  <- context-specific decisions
    └── billing/
        ├── GLOSSARY.md
        └── docs/adr/
```

Create files lazily: initialize `GLOSSARY.md` only when the first domain term is resolved, and create `docs/adr/` only when the first qualifying ADR is approved.

## Active Modeling Protocol

### 1. Challenge Against the Glossary

When the user uses a term that conflicts with `GLOSSARY.md`, surface the mismatch immediately:
> "Your glossary defines 'Cancellation' as X, whereas here it sounds like Y. Should we refine the glossary or use a distinct term?"

### 2. Sharpen Overloaded Language

When a vague or overloaded noun appears (such as `account`, `item`, `record`, or `handler`), propose a canonical domain term and list rejected synonyms under `_Avoid_`.

### 3. Stress-Test with Concrete Scenarios

Probe boundaries between domain concepts using concrete edge-case scenarios that force explicit cardinality, lifecycle, and ownership rules.

### 4. Cross-Reference with Existing Code

Verify user claims against the implementation. When code behavior diverges from the user's mental model, point out the exact discrepancy so the user can decide which is authoritative.

### 5. Update `GLOSSARY.md` Inline

The moment a domain term is agreed upon, write or update its entry in `GLOSSARY.md` following [references/glossary-format.md](./references/glossary-format.md). Capture definitions inline during conversation rather than batching at the end.

Keep `GLOSSARY.md` strictly limited to pure domain concepts and ubiquitous language. Exclude file paths, database schemas, and implementation details.

### 6. Gate ADRs by Three Criteria

Offer to record an ADR in `docs/adr/NNNN-<slug>.md` (following [references/adr-format.md](./references/adr-format.md)) only when **all three** conditions hold:

1. **Hard to reverse**: changing course later carries substantial engineering cost.
2. **Surprising without context**: a future engineer reading the code would ask why this path was chosen.
3. **Result of a real trade-off**: genuine alternatives existed and one was selected for concrete reasons.
