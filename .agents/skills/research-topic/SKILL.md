---
name: research-topic
description: Investigate a technical question against primary sources using a fresh-context background subagent and save a cited Markdown report. Use when researching documentation, third-party APIs, library internals, or specifications, or when invoked by shape-wayfinder.
---

# Primary-Source Research Investigator

Delegate documentation, API, and specification reading legwork to a **background subagent** with a **fresh context window**, keeping the primary conversation window clean and unblocked.

## Execution Protocol

### 1. Dispatch a Fresh-Context Background Subagent

Launch a research subagent in a fresh context window with a focused brief stating:

1. The exact technical question or decision that depends on the findings.
2. Relevant repository context pointers (`GLOSSARY.md`, `package.json` / dependency versions, `docs/adr/`).
3. The target output file path where the cited Markdown report should be saved.

### 2. Verify Claims Against Primary Sources Only

The research subagent must ground every finding in **primary sources**:

- Official upstream documentation and specification RFCs
- Actual library or framework source code, type definitions (`.d.ts`, `.pyi`, Rust/Go source), and release changelogs
- Live CLI `--help` output or verified API schema responses

Trace every secondary claim back to the authoritative source that owns it before recording it.

### 3. Emit a Cited Markdown Report

Write a concise, structured Markdown document to the repository's research notes directory (matching existing conventions such as `docs/research/<slug>.md` or `.scratch/<effort>/research-<slug>.md`):

```markdown
# Research: <Question or Topic>

**Summary Verdict**: <1 to 3 sentences directly answering the question>

## Key Findings
- **<Finding 1>**: <Concrete mechanics, version constraints, and trade-offs> ([Source](url-or-file-path))
- **<Finding 2>**: <Concrete mechanics, version constraints, and trade-offs> ([Source](url-or-file-path))

## Verified Code / Schema Excerpts
<Minimal, decision-relevant signature or configuration snippet verified from primary source>

## Primary Sources Consulted
1. [<Source Title / File>](<URL or repo path>) - <Version / Commit>
```

Return a one-line **context pointer** to the saved Markdown file so `/shape-grill`, `/shape-wayfinder`, or `/shape-spec` can consume the findings on demand.
