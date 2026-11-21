---
name: setup-workspace
description: "Configure this repository for engineering skills: set up its issue tracker, triage label vocabulary, domain documentation layout, and context pointers."
disable-model-invocation: true
---

# Setup Workspace

Scaffold the repository configuration consumed by downstream shaping, execution, and review skills:

- **Issue tracker**: where specs and tickets live (GitHub Issues, GitLab Issues, or local markdown files under `.scratch/`)
- **Triage labels**: label vocabulary mapping for the five canonical triage states
- **Domain docs**: where `GLOSSARY.md` and Architecture Decision Records (`docs/adr/`) reside

Explore the repository first, present findings, confirm choices with the user, and write the configuration files.

## Process

### 1. Explore the Repository

Read existing repository state before asking questions:

- `git remote -v` and `.git/config`: detect GitHub or GitLab remote hosts.
- `GEMINI.md`, `AGENTS.md`, and `CLAUDE.md` at the repo root: check which instruction file exists and whether an `## Agent skills` section is already present.
- `GLOSSARY.md` and `GLOSSARY-MAP.md` at the repo root (or legacy `CONTEXT.md` / `CONTEXT-MAP.md`). If legacy files exist, offer to rename them via `git mv` to `GLOSSARY*`.
- `docs/adr/` and `src/*/docs/adr/` directories.
- `docs/agents/`: check if prior setup files already exist.
- `.scratch/`: check if local markdown issue tracking is already in use.
- Monorepo signals: `pnpm-workspace.yaml`, `workspaces` in `package.json`, Cargo workspaces, or populated `packages/*` directories with independent `src/` trees.

### 2. Present Findings and Confirm Sections

Summarize detected files and walk through configuration sections in order. Lead each question with a recommended answer so a single "yes" accepts it. Skip any section already settled by exploration.

#### Section A: Issue Tracker

Propose the tracker matching `git remote -v`, or offer the four supported options:

- **GitHub**: issues live in GitHub Issues via the `gh` CLI ([references/issue-tracker-github.md](./references/issue-tracker-github.md)).
- **GitLab**: issues live in GitLab Issues via the `glab` CLI ([references/issue-tracker-gitlab.md](./references/issue-tracker-gitlab.md)).
- **Local markdown**: issues live as files under `.scratch/<feature-slug>/` ([references/issue-tracker-local.md](./references/issue-tracker-local.md)).
- **Other** (Linear, Jira, custom): ask the user for a one-paragraph workflow description and record it in `docs/agents/issue-tracker.md`.

When GitHub or GitLab is chosen, verify CLI connectivity with `gh repo view` or `glab repo view`.

#### Section B: Triage Label Vocabulary

Ask whether to keep the five canonical triage labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`):

> Do you want to keep the default triage labels? (recommended: **yes**)

If the repository uses custom label names, record the mapping in `docs/agents/triage-labels.md` ([references/triage-labels.md](./references/triage-labels.md)).

#### Section C: Domain Documentation Layout

Default to **single-context** (one `GLOSSARY.md` and `docs/adr/` at the repository root) without asking unless monorepo signals were detected. If monorepo signals exist, offer **multi-context** (root `GLOSSARY-MAP.md` pointing to per-package `GLOSSARY.md` and `docs/adr/` directories).

### 3. Draft and Confirm Context Pointers

Show the user a preview of:

1. The `## Agent skills` context pointer block to insert into the repository's primary instruction file (`GEMINI.md`, `AGENTS.md`, or `CLAUDE.md`).
2. The generated files under `docs/agents/` (`issue-tracker.md`, `domain.md`, and `triage-labels.md`).

Wait for user confirmation or edits before writing to disk.

### 4. Write Configuration Files

Select the existing instruction file in priority order (`GEMINI.md`, `AGENTS.md`, `CLAUDE.md`). Edit only the file that already exists; if none exists, ask the user which one to create. Update any existing `## Agent skills` section in place:

```markdown
## Agent skills

### Issue tracker

[One-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[One-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[One-line summary of layout: "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Write `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, and `docs/agents/domain.md` using the templates in `references/`. If using GitHub or GitLab, create any missing labels on the remote tracker via `gh label create` or `glab label create`.
