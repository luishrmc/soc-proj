# ADR Format

Architecture Decision Records live in `docs/adr/` and use four-digit sequential numbering: `0001-<slug>.md`, `0002-<slug>.md`, and so on.

## Core Template

```markdown
# {Short Title of the Decision}

{1 to 3 concise paragraphs: what is the context, what did we decide, and what trade-offs justified the choice.}
```

An ADR does not require ceremony. Recording *what* was decided and *why* in a single focused section is sufficient for most decisions.

## Optional Sections

Include these sections only when they add non-obvious value:

- **Status**: `proposed | accepted | deprecated | superseded by ADR-NNNN`
- **Considered Options**: summarize rejected alternatives when a future developer might be tempted to re-propose them.
- **Consequences**: document non-obvious operational or architectural downstream effects.

## Qualifying Criteria Checklist

Before proposing an ADR, verify all three conditions are met:

1. **Hard to reverse**: migrating away later requires significant rework.
2. **Surprising without context**: the code alone does not explain why this design was chosen.
3. **Real trade-off**: viable alternatives were weighed and rejected for specific reasons.

### Examples of Qualifying Decisions

- **Architectural shape**: Event-sourced write model vs. state-stored relational tables.
- **Cross-context integration**: Asynchronous domain events vs. synchronous RPC between modules.
- **High-lock-in dependencies**: Primary datastore, authentication provider, or execution runtime.
- **Deliberate deviations**: Writing raw SQL in a specific hot path inside an ORM-based codebase.
