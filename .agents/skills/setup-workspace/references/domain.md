# Domain Docs

How shaping, execution, and review skills consume this repository's domain documentation when exploring the codebase.

## Before Exploring, Read These

- **`GLOSSARY.md`** at the repo root, or
- **`GLOSSARY-MAP.md`** at the repo root if it exists: it points at one `GLOSSARY.md` per bounded context. Read each glossary relevant to the task.
- **`docs/adr/`**: read Architecture Decision Records that touch the area under modification. In multi-context repos, also check `src/<context>/docs/adr/` for context-scoped decisions.

If any of these files do not exist yet, **proceed silently**. Do not flag their absence or create empty placeholders upfront. The `shape-domain` skill (invoked by `/shape-grill`) creates them lazily as terms and decisions crystallize.

## File Structure

Single-context repo (default):

```text
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

Multi-context repo (indicated by `GLOSSARY-MAP.md` at the root):

```text
/
├── GLOSSARY-MAP.md
├── docs/adr/                          <- system-wide decisions
└── src/
    ├── ordering/
    │   ├── GLOSSARY.md
    │   └── docs/adr/                  <- context-specific decisions
    └── billing/
        ├── GLOSSARY.md
        └── docs/adr/
```

## Use the Glossary Vocabulary

When naming a domain concept in a spec, ticket title, test description, or code identifier, use the exact canonical term defined in `GLOSSARY.md`. Avoid synonyms listed under `_Avoid_`.

If a needed domain concept is missing from `GLOSSARY.md`, note the gap so `shape-domain` can resolve and record it.

## Flag ADR Conflicts

If a proposed design or change contradicts an existing ADR, surface the conflict explicitly:

> _Contradicts ADR-0002 (postgres-for-write-model), worth reopening because..._
