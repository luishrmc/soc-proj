---
name: git-safety-guard
description: Security and verification gatekeeper that audits staged changes for secrets, executes test/lint suites, and holds sole authority to execute the final git commit.
---

# Git Safety Guard

Stage 4 gatekeeper skill for autonomous agent development loops. Audits staged patches for exposed credentials, blocks invalid artifacts, runs non-interactive verification suites in isolated worktrees, and executes the official Git commit.

## Overview & Authority Boundary

This skill serves as Stage 4 in the autonomous agent development pipeline:

`git-branch-lifecycle` -> `Code Modification Loop` -> `git-commit-stager` -> `git-safety-guard` -> `git-release-tagger`

### Entry Contract
* Staged Git index prepared by Stage 3 (`git-commit-stager`).
* Input manifest `.agent/commit-staging-manifest.json` containing `full_commit_message`, `staged_files`, and change metadata.

### Core Invariant
This skill holds the exclusive authority across the agent pipeline to execute `git commit`. No prior stage is permitted to persist Git commit objects. If any verification check fails, execution aborts immediately, leaving the index intact for inspection.

---

## Pre-Flight Verification Protocol

Execute all checks non-interactively in strict sequence.

### 1. Verification Manifest Ingestion
Verify that Stage 3 generated the staging manifest:

```bash
MANIFEST_FILE=".agent/commit-staging-manifest.json"

if [ ! -f "$MANIFEST_FILE" ]; then
  echo "FATAL: Staging manifest '$MANIFEST_FILE' not found. Stage 3 must run before safety verification." >&2
  exit 1
fi

STAGED_COUNT=$(git diff --staged --name-only 2>/dev/null | wc -l | tr -d ' ')
if [ "$STAGED_COUNT" -eq 0 ]; then
  echo "FATAL: Git index is empty. No staged changes to commit." >&2
  exit 2
fi
```

### 2. Secret and Sensitive Data Audit
Inspect additions in the staged diff:

```bash
# Extract only added lines from staged diff
STAGED_ADDITIONS=$(git diff --staged -U0 --no-color 2>/dev/null | grep -E '^\+[^\+]' || true)

# 1. Inspect private key blocks
if echo "$STAGED_ADDITIONS" | grep -E -- "-----BEGIN [A-Z ]*PRIVATE KEY-----" >/dev/null 2>&1; then
  echo "SECURITY VIOLATION: Staged diff contains private key headers." >&2
  exit 10
fi

# 2. Inspect cloud provider tokens
if echo "$STAGED_ADDITIONS" | grep -E -- "(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}" >/dev/null 2>&1; then
  echo "SECURITY VIOLATION: Staged diff contains AWS access key identifiers." >&2
  exit 11
fi

# 3. Inspect GitHub, OpenAI, and Slack API tokens
if echo "$STAGED_ADDITIONS" | grep -E -- "gh[pousr]_[A-Za-z0-9_]{36,}|sk-(proj-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[0-9A-Za-z]{10,}" >/dev/null 2>&1; then
  echo "SECURITY VIOLATION: Staged diff contains provider API tokens." >&2
  exit 12
fi

# 4. Inspect hardcoded secret assignments
if echo "$STAGED_ADDITIONS" | grep -iE "(api[_-]?key|secret|password|auth[_-]?token|private[_-]?key)\s*[:=]\s*['\"][A-Za-z0-9_\-\.]{12,}['\"]" >/dev/null 2>&1; then
  # Allow non-sensitive test placeholders
  SUSPICIOUS=$(echo "$STAGED_ADDITIONS" | grep -iE "(api[_-]?key|secret|password|auth[_-]?token|private[_-]?key)\s*[:=]\s*['\"][A-Za-z0-9_\-\.]{12,}['\"]")
  if ! echo "$SUSPICIOUS" | grep -iE "(mock|fake|dummy|test|example)" >/dev/null 2>&1; then
    echo "SECURITY VIOLATION: Hardcoded credential assignment detected in staged diff." >&2
    exit 13
  fi
fi

# 5. Inspect forbidden filenames in staged index
while IFS= read -r STAGED_FILE; do
  [ -z "$STAGED_FILE" ] && continue
  case "$STAGED_FILE" in
    *.env|.env.*|*.pem|*.key|*id_rsa*|*id_ed25519*|*.pfx|*.p12)
      echo "SECURITY VIOLATION: Staged path '$STAGED_FILE' is a forbidden sensitive file." >&2
      exit 14
      ;;
  esac
done < <(git diff --staged --name-only)
```

### 3. Artifact and File Size Guards
Inspect file sizes and binary objects within the staged index:

```bash
MAX_BYTES=5242880 # 5MB limit

while IFS= read -r STAGED_FILE; do
  [ -z "$STAGED_FILE" ] && continue

  # Block forbidden directory patterns
  case "$STAGED_FILE" in
    node_modules/*|venv/*|.venv/*|target/*|dist/*|build/*|vendor/*)
      echo "REJECTED: Staged path '$STAGED_FILE' belongs to an ignored dependency or build folder." >&2
      exit 20
      ;;
  esac

  # Block oversized blobs
  BLOB_SIZE=$(git cat-file -s ":$STAGED_FILE" 2>/dev/null || echo 0)
  if [ "$BLOB_SIZE" -gt "$MAX_BYTES" ]; then
    echo "REJECTED: Staged file '$STAGED_FILE' exceeds 5MB size limit ($BLOB_SIZE bytes)." >&2
    exit 21
  fi
done < <(git diff --staged --name-only)

# Block unapproved binary additions
BINARY_COUNT=$(git diff --staged --numstat 2>/dev/null | grep '^-	-' | wc -l | tr -d ' ')
if [ "$BINARY_COUNT" -gt 0 ]; then
  echo "REJECTED: Staged changes contain raw binary additions." >&2
  git diff --staged --numstat | grep '^-	-' >&2
  exit 22
fi
```

### 4. Verification Suite Execution with Worktree Isolation
Isolate unstaged changes so tests run exclusively against the staged index:

```bash
UNSTAGED_CHANGES=$(git status --porcelain=v1 2>/dev/null | grep -E '^ [MD?]' || true)
STASH_ACTIVE=0

if [ -n "$UNSTAGED_CHANGES" ]; then
  git stash push --keep-index --include-untracked --quiet -m "safety-guard-isolation" || {
    echo "FATAL: Failed to isolate unstaged working tree changes." >&2
    exit 30
  }
  STASH_ACTIVE=1
fi

# Cleanup handler to ensure unstaged changes restore upon failure or exit
cleanup() {
  if [ "$STASH_ACTIVE" -eq 1 ]; then
    git stash pop --quiet >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# 1. Execute Linting Suite
LINT_CMD=""
# Project-specific (Cora Z7-10): VHDL lint hook, then the VUnit suite through the Makefile
if [ -f ".agents/hooks/vhdl-lint.sh" ] && [ -f "cora7z/app/hw/Makefile" ]; then
  LINT_CMD="bash .agents/hooks/vhdl-lint.sh"
elif [ -f "package.json" ] && grep -q '"lint"' package.json; then
  LINT_CMD="npm run lint --silent"
elif [ -f "Makefile" ] && grep -q '^lint:' Makefile; then
  LINT_CMD="make lint"
elif command -v ruff >/dev/null 2>&1 && [ -f "pyproject.toml" ]; then
  LINT_CMD="ruff check ."
fi

if [ -n "$LINT_CMD" ]; then
  timeout 180s $LINT_CMD || {
    echo "VERIFICATION FAILED: Linter command failed: $LINT_CMD" >&2
    exit 31
  }
fi

# 2. Execute Test Suite
TEST_CMD=""
if [ -f "cora7z/app/hw/Makefile" ] && grep -q '^test:' cora7z/app/hw/Makefile; then
  TEST_CMD="make -C cora7z/app/hw test"
elif [ -f "package.json" ] && grep -q '"test"' package.json; then
  TEST_CMD="npm test -- --silent"
elif [ -f "Makefile" ] && grep -q '^test:' Makefile; then
  TEST_CMD="make test"
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
  TEST_CMD="pytest -q"
elif [ -f "go.mod" ]; then
  TEST_CMD="go test ./..."
elif [ -f "Cargo.toml" ]; then
  TEST_CMD="cargo test --quiet"
fi

if [ -n "$TEST_CMD" ]; then
  timeout 300s $TEST_CMD || {
    echo "VERIFICATION FAILED: Test suite failed: $TEST_CMD" >&2
    exit 32
  }
fi
```

---

## Execution & Commit Protocol

When all verification checks succeed, execute the commit.

### 1. Extract Validated Commit Message
Read the commit message directly from the Stage 3 manifest:

```bash
COMMIT_MSG_TMP=$(mktemp)

# Parse full_commit_message from JSON manifest using python
python3 -c '
import json, sys
with open(".agent/commit-staging-manifest.json") as f:
    data = json.load(f)
msg = data.get("full_commit_message", "")
if not msg.strip():
    sys.exit("Manifest full_commit_message is empty")
print(msg)
' > "$COMMIT_MSG_TMP" || {
  echo "FATAL: Failed to extract commit message from manifest." >&2
  rm -f "$COMMIT_MSG_TMP"
  exit 40
}
```

### 2. Execute Non-Interactive Commit
Invoke `git commit` using the message file to prevent shell escaping errors:

```bash
export GIT_TERMINAL_PROMPT=0
export GIT_PAGER=cat

git commit --quiet -F "$COMMIT_MSG_TMP" || {
  COMMIT_STATUS=$?
  echo "FATAL: git commit execution rejected (exit code: $COMMIT_STATUS)." >&2
  rm -f "$COMMIT_MSG_TMP"
  exit 41
}

rm -f "$COMMIT_MSG_TMP"
```

### 3. Immediate Post-Commit State Verification
Verify that `HEAD` updated and the index is clean:

```bash
COMMITTED_SHA=$(git rev-parse --verify HEAD 2>/dev/null)
INDEX_STILL_DIRTY=$(git diff --staged --name-only 2>/dev/null | wc -l | tr -d ' ')

if [ -z "$COMMITTED_SHA" ] || [ "$INDEX_STILL_DIRTY" -ne 0 ]; then
  echo "FATAL: Commit completed with invalid state. Staged index not empty." >&2
  exit 42
fi
```

---

## Failure & Remediation Matrix

| Failure Mode | Detection Signal | Root Cause | Agent Remediation Action |
| :--- | :--- | :--- | :--- |
| **Secret Detected** | Exit code `10-14` | Plaintext token, private key, or credential found in staged diff | Abort commit. Output file path and matching pattern rule. Retain index for developer inspection. Do not run `git commit`. |
| **Oversized / Binary File** | Exit code `20-22` | File exceeds 5MB, binary blob, or dependency directory added | Abort commit. Unstage offending path with `git reset HEAD -- <path>`. Notify upstream planner. |
| **Lint Failure** | Exit code `31` | Style check or static analysis failed | Abort commit. Emit linter stdout and stderr. Leave staged files intact. |
| **Test Suite Failure** | Exit code `32` | Regression detected by automated test command | Abort commit. Emit test runner failure output. Restore isolated stash. Leave files staged. |
| **Test Timeout** | Exit code `124` | Test runner exceeded maximum execution threshold | Abort commit. Log timeout duration. Restore unstaged changes from stash. |
| **Pre-Commit Hook Rejected** | Exit code `41` | Repository git hooks aborted commit execution | Capture `.git/hooks` diagnostic message. Abort without retry. |
| **Empty Changeset** | Exit code `2` | No files staged in the Git index | Abort execution. Log empty index state. |

---

## Output Contract & State Manifest

Upon successful completion or failure, write the manifest to `.agent/safety-guard-manifest.json` and standard output:

### Successful Commit Payload

```json
{
  "status": "COMPLETED",
  "stage": "git-safety-guard",
  "commit_status": "COMMITTED",
  "commit_sha": "d7a45e98b0a12f34c56789e0123456789abcdef0",
  "branch_name": "feat/proj-102-user-phone-validation",
  "verification_summary": {
    "secrets_scanned": true,
    "secrets_detected": false,
    "file_size_checked": true,
    "binary_guard_passed": true,
    "linter_passed": true,
    "tests_passed": true
  },
  "failure_reasons": [],
  "timestamp_utc": "2026-10-10T23:35:10Z"
}
```

### Aborted Verification Payload

```json
{
  "status": "FAILED",
  "stage": "git-safety-guard",
  "commit_status": "ABORTED",
  "commit_sha": null,
  "branch_name": "feat/proj-102-user-phone-validation",
  "verification_summary": {
    "secrets_scanned": true,
    "secrets_detected": true,
    "file_size_checked": true,
    "binary_guard_passed": true,
    "linter_passed": false,
    "tests_passed": false
  },
  "failure_reasons": [
    "SECURITY VIOLATION: Staged diff contains private key headers at src/auth/keys.ts."
  ],
  "timestamp_utc": "2026-10-10T23:35:10Z"
}
```

### Manifest Schema Fields
* `status` (string): Execution status (`COMPLETED` or `FAILED`).
* `stage` (string): Constant identifier `git-safety-guard`.
* `commit_status` (string): State indicator (`COMMITTED` or `ABORTED`).
* `commit_sha` (string or null): Full 40-character SHA of the generated commit object.
* `branch_name` (string): Target branch containing the commit.
* `verification_summary` (object): Boolean status flags for each safety gate.
* `failure_reasons` (array of strings): Diagnostic list of safety or test failures.
* `timestamp_utc` (string): ISO-8601 UTC timestamp of execution completion.

---

## Negative Constraints

* Never execute `git commit` if any secret check, lint run, or test suite fails.
* Never bypass pre-commit hooks using `--no-verify`.
* Never scan whole repository history; restrict secret auditing to staged additions (`git diff --staged -U0`).
* Never run tests against a dirty working tree without applying `git stash --keep-index` isolation.
* Never pass commit message strings directly through command line arguments (`-m "$MSG"`).
* Never discard uncommitted work with destructive reset commands upon test failures.