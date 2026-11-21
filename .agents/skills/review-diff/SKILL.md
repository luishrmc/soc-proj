---
name: review-diff
description: Review code changes since a fixed git reference along two independent axes (Standards compliance and Spec fidelity) using parallel fresh-context subagents. Use when reviewing a branch, PR, or working diff, when the user asks to "review since X", or when invoked by dev-implement or dev-parallel.
---

# Two-Axis Parallel Diff Review

Execute a rigorous two-axis code review of the diff between `HEAD` and a fixed git reference (`<fixed-point>`):

- **Standards Axis**: Does the diff obey the repository's documented coding standards and avoid structural code smells?
- **Spec Axis**: Does the diff faithfully implement every requirement in the originating specification or ticket without scope creep?

Run both axes as **parallel subagents with fresh context windows** so neither axis masks or dilutes the other.

## Execution Process

### 1. Pin and Verify the Fixed Point

1. Identify the `<fixed-point>` reference (a branch name such as `main`, a commit SHA, tag, or `HEAD~N`). If unspecified and not inferable from `.agent/lifecycle-state.json`, ask the user.
2. Verify the ref resolves (`git rev-parse --verify <fixed-point>`) and confirm the three-dot diff (`git diff <fixed-point>...HEAD`) is non-empty. Capture the commit list via `git log <fixed-point>..HEAD --oneline`.

### 2. Locate the Originating Specification or Ticket

Search for the spec/ticket source in priority order:

1. Issue or ticket identifiers in commit messages or branch names (`#123`, `PROJ-102`), fetched via `docs/agents/issue-tracker.md`.
2. A path or issue number passed directly by the caller.
3. A local spec or ticket file under `.scratch/<feature-slug>/`, `docs/`, or `specs/`.
4. If no spec exists and the user confirms none was written, skip the Spec subagent and note `"Spec axis skipped: no specification provided"` in the final report.

### 3. Gather Standards Sources and Smell Baseline

1. Locate all repository standards documents (`CODING_STANDARDS.md`, `CONTRIBUTING.md`, `GEMINI.md`, `AGENTS.md`, `CLAUDE.md`, `GLOSSARY.md`).
2. Load the 12-item Fowler code smell baseline from [references/smell-baseline.md](./references/smell-baseline.md). Documented repository standards always override the baseline, and anything already enforced by automated linters/formatters is skipped.

### 4. Dispatch Parallel Subagents

Spawn both subagents concurrently with fresh context windows:

- **Standards Subagent Brief**:
  Provide the diff command (`git diff <fixed-point>...HEAD`), commit log, discovered repo standards file paths, and the full contents of [references/smell-baseline.md](./references/smell-baseline.md). Instruct it:
  > "Report per file/hunk: (a) any breach of a documented repo standard (cite the file and rule); and (b) any Fowler baseline smell (name the smell and quote the hunk). Separate hard documented-standard violations from baseline smell judgment calls. Skip rules already enforced by linters/typecheckers. Keep under 400 words."

- **Spec Subagent Brief**:
  Provide the diff command (`git diff <fixed-point>...HEAD`), commit log, and the full spec/ticket text. Instruct it:
  > "Report: (a) spec requirements or acceptance criteria that are missing or only partially implemented; (b) unrequested behavior or scope creep present in the diff; and (c) implemented requirements whose logic or edge-case handling contradicts the spec. Quote the exact spec line for each finding. Keep under 400 words."

### 5. Aggregate Without Merging Axes

Present the findings under two separate top-level headings: `## Standards Review` and `## Spec Review`.

Do not merge or re-rank findings across the two axes (code that obeys every standard while building the wrong feature must clearly show **Standards: PASS / Spec: FAIL**, and vice versa). Conclude with a one-line summary stating total findings per axis and the highest-severity issue within each axis.
