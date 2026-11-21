---
name: env-handoff
description: "Compact the current conversation into a portable handoff document in $TMPDIR with context pointers and suggested skills for a fresh agent session."
disable-model-invocation: true
---

# Cross-Session Context Handoff

Serialize the essential state of the current conversation into a portable Markdown handoff file in the OS temporary directory so a fresh agent session (in a new directory, new harness, or forked task) can continue without losing context.

## When Handoff Earns Its Keep

Use `/env-handoff` specifically when work is **traveling across a boundary**:

- Switching to a different agent harness or CLI session
- Moving into a separate repository or prototype directory (`/shape-prototype`)
- Handing an in-flight investigation to a collaborator
- Forking an unexpected side task mid-phase without derailing the active thread

## Execution Process

### 1. Resolve Target Path in `$TMPDIR`

Write the handoff file to `${TMPDIR:-/tmp}/handoff-<slug>-$(date +%s).md` (never inside the repository working tree) and report the absolute path to the user.

### 2. Reference Artifacts via Context Pointers

Keep the handoff document compact and high-signal by pointing to persisted artifacts rather than copying their contents:

- Reference specs, tickets (`.scratch/<feature>/` or issue URLs), `GLOSSARY.md`, ADRs (`docs/adr/`), commits, and branch names by path or identifier.
- Summarize only the **unpersisted session state**: decisions settled in chat, ruled-out dead ends, and the immediate next step.
- Tailor the focus to any argument the user passed when invoking `/env-handoff`.

### 3. Redact Secrets & Recommend Next Skills

1. Replace any API keys, tokens, credentials, or sensitive environment values with `<REDACTED>`.
2. Include a `## Suggested Skills` section naming the exact skills the receiving agent should invoke first (e.g., `/shape-grill`, `/shape-spec`, `/dev-implement`, `dev-tdd`, or `debug-loop`).

## Handoff Document Template

```markdown
# Handoff: <Topic or Feature Title>

**Objective for Next Session**: <Focused goal of the receiving agent>
**Active Branch / Directory**: `<branch-name>` in `<repo-path>`

## Context Pointers (Read First)
- **Spec / Ticket**: `<path or issue URL>`
- **Domain & ADRs**: `GLOSSARY.md`, `docs/adr/<relevant-adr>.md`
- **Relevant Commits / Files**: `<commit SHAs and key module paths>`

## Decisions & Findings Established in This Session
- <Key decision or root-cause finding not yet written to repo docs>
- <Dead end ruled out and why>

## Suggested Skills for Next Session
- `<skill-name>`: <why and when to invoke it>
```
