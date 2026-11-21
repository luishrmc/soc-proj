# GLOSSARY.md Format

## Structure

```markdown
# {Context Name}

{One or two sentence description of what this bounded context is and why it exists.}

## Language

**Order**:
A confirmed customer request to purchase one or more line items at a locked price.
_Avoid_: Purchase, transaction, basket

**Invoice**:
A formal payment request issued to a Customer after fulfillment.
_Avoid_: Bill, receipt, statement

**Customer**:
An organization or individual holding a billing relationship and placing Orders.
_Avoid_: Client, buyer, account
```

## Authoring Rules

- **Be opinionated**: When multiple synonyms exist for a concept, select one canonical term and list all rejected alternatives under `_Avoid_`.
- **Keep definitions tight**: Maximum one to two declarative sentences stating what the concept *is* in the domain, never how it is implemented in code.
- **Domain-specific terms only**: Exclude general software engineering terms (such as middleware, retry policy, cache, DTO, or webhook) unless they carry a specialized domain meaning unique to this project.
- **Cluster when large**: Group related terms under `###` subheadings once the glossary grows past 15 entries.

## Single-Context vs. Multi-Context Resolution

- If `GLOSSARY-MAP.md` exists at the root, read it to locate the relevant bounded context glossary (`./src/<context>/GLOSSARY.md`).
- If only a root `GLOSSARY.md` exists, maintain all terms there.
- If neither exists, create the root `GLOSSARY.md` lazily when the first domain term is settled.
