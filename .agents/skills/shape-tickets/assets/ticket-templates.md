# Ticket Templates

Use these templates when publishing approved tracer-bullet tickets in `shape-tickets`. Omit brittle file paths and raw code snippets unless inlining a concise type shape or state machine from a validated prototype.

## 1. Local Markdown Ticket Template (`.scratch/<feature-slug>/issues/<NN>-<slug>.md`)

Write one file per ticket, numbered sequentially from `01` in topological order:

```markdown
# <NN>: <Ticket Title>

**What to build:** End-to-end observable behavior this slice makes work from the caller or user perspective (never a layer-by-layer chore list).

**Blocked by:** <NN - Title of blocking ticket(s), or "None (can start immediately)">

**Status:** ready-for-agent

## Acceptance Criteria

- [ ] Observable behavioral criterion 1
- [ ] Observable behavioral criterion 2
- [ ] Seam test coverage verified green
```

---

## 2. Issue Tracker Template (GitHub / GitLab Issues)

Publish in topological order (blockers first) so real issue numbers can be wired as blocking edges:

```markdown
## Parent

Part of #<parent-spec-issue-number> (omit this section if no parent spec issue exists)

## What to Build

End-to-end observable behavior this slice delivers from the user or caller perspective, written using `GLOSSARY.md` domain vocabulary.

## Acceptance Criteria

- [ ] Observable behavioral criterion 1
- [ ] Observable behavioral criterion 2
- [ ] Public seam tests passing

## Blocked By

- #<blocker-issue-number> (or "None - can start immediately"; omit section if native tracker blocking links are wired)
```
