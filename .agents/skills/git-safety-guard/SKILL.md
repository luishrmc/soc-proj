---
name: git-safety-guard
description: Audit staged git diffs for secrets and binary artifacts, execute lint and test suites in stash-isolated worktrees, and run the final git commit. Use when verifying staged changes before committing, enforcing pre-commit security checks, or when invoked as Stage 5 of dev-implement.
---

# Git Safety Guard

Stage 5 verification and commit gatekeeper in the autonomous development pipeline:

`git-branch-lifecycle` -> `dev-implement` (`dev-tdd` & `review-diff`) -> `git-commit-stager` -> `git-safety-guard`

## Authority & Entry Contract

- **Entry Prerequisites**: Non-empty staged Git index and `.agent/commit-staging-manifest.json` emitted by `git-commit-stager`.
- **Exclusive Commit Authority**: This skill holds sole authority across the pipeline to run `git commit`. If any secret scan, artifact check, linter, or test suite fails, execution aborts immediately while keeping the staged index intact for remediation.

## Execution Protocol

### 1. Automated Verification and Commit (`scripts/verify-and-commit.sh`)

Execute the bundled non-interactive verification script to run all four pre-flight gates, commit using `-F` from the validated manifest, and write `.agent/safety-guard-manifest.json`:

```bash
bash skills/git-safety-guard/scripts/verify-and-commit.sh
```

### 2. The Four Pre-Flight Gates

The helper script (`scripts/verify-and-commit.sh`) enforces four sequential gates before calling `git commit`:

1. **Manifest & Index Presence (`Exit 1-2`)**: Confirms `.agent/commit-staging-manifest.json` exists and `git diff --staged --name-only` is non-empty.
2. **Staged Secret & Sensitive Path Scan (`Exit 10-14`)**: Inspects added lines (`git diff --staged -U0`) for private key headers (`-----BEGIN ... PRIVATE KEY-----`), AWS access key prefixes (`AKIA`, `ASIA`), provider tokens (`ghp_`, `sk-`, `xoxb-`), hardcoded password/secret assignments, and sensitive filenames (`*.env`, `*.pem`, `*.key`, `*id_rsa*`).
3. **Artifact, Dependency & Size Guard (`Exit 20-22`)**: Rejects staged paths inside dependency/build directories (`node_modules/`, `venv/`, `.venv/`, `target/`, `dist/`, `build/`), blobs exceeding 5 MB (`5242880` bytes), and unapproved raw binary additions.
4. **Stash-Isolated Lint & Test Execution (`Exit 30-32`)**: Stashes unstaged working tree modifications via `git stash push --keep-index --include-untracked` (with an automatic `EXIT` trap restoring the stash), then runs detected repository linters and test suites (`package.json`, `Makefile`, `pyproject.toml`, `go.mod`, `Cargo.toml`).

### 3. Non-Interactive Commit & Post-Check

When all gates pass, the script extracts `full_commit_message` from `.agent/commit-staging-manifest.json` into a temporary file, executes `git commit --quiet -F "$COMMIT_MSG_TMP"`, verifies `HEAD` advanced and the staged index is clean, and writes `.agent/safety-guard-manifest.json` ([references/safety-manifest.md](./references/safety-manifest.md)).
