---
name: shape-tickets
description: "Decompose a specification or plan into tracer-bullet vertical slice tickets with explicit blocking edges and publish them to the issue tracker."
disable-model-invocation: true
---

# Tracer-Bullet Ticket Decomposition

Break a specification, plan, or shaped conversation into an acyclic task graph of **tickets**: context-window-sized **tracer-bullet** vertical slices, each declaring the upstream tickets that **block** it.

## Preconditions

Check `docs/agents/issue-tracker.md` for the repository's configured tracker (GitHub, GitLab, or local `.scratch/<feature-slug>/issues/`). If unconfigured, ask whether to write local `.scratch/` tickets or suggest running `/setup-workspace`.

## Decomposition Process

### 1. Ingest Specification and Prefactoring Seams

1. Read the active conversation context or fetch the referenced specification file/issue.
2. Explore affected modules using `GLOSSARY.md` terminology and respecting `docs/adr/`.
3. Identify **prefactoring** opportunities ("Make the change easy, then make the easy change"). Schedule any structural prefactoring as the earliest unblocked ticket(s).

### 2. Draft Tracer-Bullet Vertical Slices

Decompose the feature into vertical slices governed by four rules:

1. **Vertical, Never Horizontal**: Each ticket cuts a narrow, complete path through *every* required layer (schema, domain logic, API/CLI interface, UI, and seam tests). Never create horizontal tickets that build an entire layer in isolation (e.g., "create all database tables" or "write all tests").
2. **Independently Verifiable**: Every completed ticket leaves the codebase green and produces observable, testable behavior.
3. **Single-Context Sizing**: Size each ticket so an implementer agent can complete it comfortably within a single fresh context window.
4. **Minimal Blocking Edges**: Assign each ticket its exact `Blocked by` dependencies. Tickets with no blockers form the initial ready **frontier**.

#### Exception: Wide Refactors Use Expand-Contract

When a mechanical change (renaming a core symbol, changing a shared signature, migrating a column) has a wide **blast radius** across dozens of call sites, do not force a vertical slice. Sequence it as **Expand-Contract**:

1. **Expand ticket**: Introduce the new interface or column alongside the old one so existing callers remain green.
2. **Migrate batch tickets**: Migrate call sites in bounded batches (per package or directory), each blocked by the Expand ticket.
3. **Contract ticket**: Remove the deprecated interface or column once all migrate batches complete, blocked by every migrate ticket.

### 3. Quiz the User on the Task Graph

Present the proposed numbered ticket breakdown before publishing:

- **Title**: concise behavioral summary using `GLOSSARY.md` terms
- **Blocked by**: upstream ticket numbers (or `None - ready on frontier`)
- **What it delivers**: end-to-end observable behavior unlocked by this slice

Ask the user to confirm:

1. Is the ticket granularity right (neither too coarse nor over-fragmented)?
2. Are the blocking edges minimal and accurate?
3. Should any slices be merged, split, or reordered?

Iterate until the user approves the DAG.

### 4. Publish Tickets in Dependency Order

Publish approved tickets using the templates in [assets/ticket-templates.md](./assets/ticket-templates.md), always creating blockers first so downstream tickets can reference real IDs:

- **Local Markdown Tracker**: Write one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md` (numbered `01`, `02`, ... in topological order). Never combine multiple tickets into one file.
- **GitHub / GitLab Tracker**: Create one issue per ticket in topological order, wire native blocking links (and parent sub-issue links if derived from a spec issue), and apply the `ready-for-agent` label. Leave the parent spec issue open.
