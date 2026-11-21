---
name: git-commit-stager
description: Audit dirty working trees after code modifications, stage permitted files strictly by explicit pathspec, and draft a validated Conventional Commit message. Use when staging changes, drafting commit messages, or when invoked as Stage 4 of dev-implement.
---

# Git Commit Stager

Stage 4 operational skill in the autonomous development pipeline:

`git-branch-lifecycle` -> `dev-implement` (`dev-tdd` & `review-diff`) -> `git-commit-stager` -> `git-safety-guard`

## Handoff Boundaries

- **Input**: Dirty working tree on an active task branch following code implementation and `review-diff` audit, plus optional `.agent/lifecycle-state.json`.
- **Output**: Selectively staged Git index (`git add -- "$FILE_PATH"`), excluded sensitive/artifact paths recorded in `unstaged_files`, and a drafted Conventional Commits 1.0.0 payload written to `.agent/commit-staging-manifest.json` ([references/commit-manifest.md](./references/commit-manifest.md)).
- **Authority Separation**: This skill prepares the index and commit manifest only; `git-safety-guard` holds exclusive authority to execute `git commit`.

## Execution Protocol

### 1. Explicit Pathspec Staging Invariant

Always stage files one by one using explicit, quoted relative pathspecs (`git add --quiet -- "$FILE"`). Avoid bulk wildcard commands (`git add .`, `git add -A`, `git add --all`, or unquoted globs) so untracked credentials, logs, and temporary build artifacts never enter the index.

### 2. Automated Staging and Commit Drafting (`scripts/stage-files.sh`)

Run the bundled helper script to parse `git status --porcelain=v1`, filter out sensitive and ignored paths, stage modified/created/deleted files by explicit pathspec, infer the Conventional Commits `type(scope): subject` header and bulleted body, and emit `.agent/commit-staging-manifest.json`:

```bash
bash skills/git-commit-stager/scripts/stage-files.sh [optional-custom-subject]
```

### 3. Script Operations Summary

The helper script (`scripts/stage-files.sh`) executes four deterministic phases:

1. **Porcelain Status Audit**: Verifies the working tree has modifications (`git status --porcelain=v1`). Automatically excludes `.env*`, `*.pem`, `*.key`, `*id_rsa*`, `*token*`, `*credential*`, `*.log`, `*.tmp`, `*.swp`, `__pycache__/*`, and any path matched by `git check-ignore`.
2. **Path-by-Path Staging**: Runs `git add --quiet -- "$FILE"` for modified and untracked source files and `git rm --quiet --cached --ignore-unmatch -- "$FILE"` for deleted tracked files.
3. **Conventional Commit Synthesis**: Infers `COMMIT_TYPE` (`feat`, `fix`, `refactor`, `test`, `docs`, `ci`, `build`, `chore`) and `COMMIT_SCOPE` from `.agent/lifecycle-state.json` and top-level directory consensus, enforces the 72-character header ceiling, and detects `BREAKING CHANGE` markers.
4. **Manifest Emission**: Writes `.agent/commit-staging-manifest.json` with `execution_authority: "DELEGATED_TO_GIT_SAFETY_GUARD"`.

Consult [references/commit-manifest.md](./references/commit-manifest.md) for the JSON manifest schema and edge-case handling rules.
