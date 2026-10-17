---
name: git-branch-lifecycle
description: Autonomous branch management skill that audits working tree state, syncs the default base branch, creates standardized feature/fix branches, and establishes tracking.
---

# Git Branch Lifecycle

Stage 1 initialization skill for autonomous agent development loops. Audits working tree cleanliness, discovers canonical upstream defaults, synchronizes local base refs, and creates standardized, collision-free working branches.

## Overview & Role in Pipeline

This skill serves as Stage 1 in the autonomous agent development pipeline:

`git-branch-lifecycle` -> `Code Modification Loop` -> `git-commit-stager` -> `git-safety-guard` -> `git-release-tagger`

### Entry Conditions
* Operator input provided: Task description string (for example, `"Add user phone validation"`) or ticket specification (for example, `"PROJ-102: Fix memory leak in websocket listener"`).
* Working directory is inside a valid Git repository root.

### Handoff Exit Conditions
* Repository is checked out on the newly created target branch.
* Base branch is verified clean and synchronized with upstream remote.
* Structured state manifest (`.agent/lifecycle-state.json`) is emitted for Stage 2 consumption.

---

## Pre-Flight Invariants & Safety Checks

Execute these non-interactive checks before altering any repository references.

### 1. Repository Root Verification
Ensure commands execute from the top-level directory of a valid Git repository:

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "FATAL: Current working directory is not a Git repository." >&2
  exit 1
}
```

### 2. Working Tree Cleanliness (Fail-Fast Policy)
Audit untracked and modified files using porcelain output:

```bash
STATUS_OUTPUT=$(git status --porcelain=v1 2>/dev/null)
if [ -n "$STATUS_OUTPUT" ]; then
  echo "FATAL: Working tree is dirty. Stashing is disabled for autonomous safety." >&2
  echo "$STATUS_OUTPUT" >&2
  exit 2
fi
```

### 3. Active Operation Check
Verify that no rebase, merge, cherry-pick, or revert operation is currently pending:

```bash
GIT_DIR=$(git rev-parse --git-dir)
if [ -d "$GIT_DIR/rebase-merge" ] || [ -d "$GIT_DIR/rebase-apply" ] || \
   [ -f "$GIT_DIR/MERGE_HEAD" ] || [ -f "$GIT_DIR/CHERRY_PICK_HEAD" ] || \
   [ -f "$GIT_DIR/REVERT_HEAD" ]; then
  echo "FATAL: Pending Git rebase, merge, or cherry-pick operation detected." >&2
  exit 3
fi
```

### 4. Dynamic Canonical Base Branch Discovery
Resolve the primary base branch dynamically without hardcoding:

```bash
# Attempt discovery from origin remote HEAD symref
BASE_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')

# Fallback probe across standard trunk naming conventions
if [ -z "$BASE_BRANCH" ]; then
  for CANDIDATE in main master trunk develop; do
    if git show-ref --quiet --verify "refs/remotes/origin/$CANDIDATE"; then
      BASE_BRANCH="$CANDIDATE"
      break
    fi
  done
fi

# Fallback to local default branch if remote refs are unavailable
if [ -z "$BASE_BRANCH" ]; then
  for CANDIDATE in main master trunk develop; do
    if git show-ref --quiet --verify "refs/heads/$CANDIDATE"; then
      BASE_BRANCH="$CANDIDATE"
      break
    fi
  done
fi

if [ -z "$BASE_BRANCH" ]; then
  echo "FATAL: Unable to resolve canonical base branch." >&2
  exit 4
fi
```

---

## Step-by-Step Execution Protocol

Execute all steps non-interactively using strict flags and environment variables.

### Step 1: Environment Isolation
Prevent terminal credential prompts and interactive pagers:

```bash
export GIT_TERMINAL_PROMPT=0
export GIT_PAGER=cat
```

### Step 2: Base Branch Synchronization
Fetch the latest remote state and fast-forward the local base branch:

```bash
# Switch to base branch
git checkout --quiet "$BASE_BRANCH"

# Prune and fetch remote base branch
git fetch --quiet --prune origin "$BASE_BRANCH"

# Verify local vs remote commit alignment
LOCAL_SHA=$(git rev-parse --verify "refs/heads/$BASE_BRANCH")
REMOTE_SHA=$(git rev-parse --verify "refs/remotes/origin/$BASE_BRANCH" 2>/dev/null || echo "$LOCAL_SHA")

AHEAD_COUNT=$(git rev-list --count "refs/remotes/origin/$BASE_BRANCH..refs/heads/$BASE_BRANCH" 2>/dev/null || echo 0)
BEHIND_COUNT=$(git rev-list --count "refs/heads/$BASE_BRANCH..refs/remotes/origin/$BASE_BRANCH" 2>/dev/null || echo 0)

if [ "$AHEAD_COUNT" -gt 0 ]; then
  echo "FATAL: Local base branch '$BASE_BRANCH' has $AHEAD_COUNT unpushed commits. Aborting." >&2
  exit 5
fi

if [ "$BEHIND_COUNT" -gt 0 ]; then
  git merge --ff-only "origin/$BASE_BRANCH" --quiet || {
    echo "FATAL: Fast-forward merge of base branch failed." >&2
    exit 6
  }
fi
```

### Step 3: Deterministic Branch Naming
Map the operator task input into a conventional, sanitized Git branch reference:

```bash
RAW_TASK_INPUT="$1"

# 1. Extract Ticket Slug if present (e.g., PROJ-102 or GH-42)
TICKET_ID=$(echo "$RAW_TASK_INPUT" | grep -oE '^[A-Za-z]+-[0-9]+' | tr '[:upper:]' '[:lower:]')
TASK_REMAINDER=$(echo "$RAW_TASK_INPUT" | sed -E 's/^[A-Za-z]+-[0-9]+[: ]*//')

# 2. Determine Conventional Commits Prefix
FIRST_WORD=$(echo "$TASK_REMAINDER" | awk '{print tolower($1)}')
case "$FIRST_WORD" in
  add|create|implement|feat|feature)
    TYPE_PREFIX="feat"
    ;;
  fix|resolve|patch|bug)
    TYPE_PREFIX="fix"
    ;;
  refactor|reorganize|clean)
    TYPE_PREFIX="refactor"
    ;;
  test|tests|coverage)
    TYPE_PREFIX="test"
    ;;
  doc|docs|document|documentation)
    TYPE_PREFIX="docs"
    ;;
  *)
    TYPE_PREFIX="chore"
    ;;
esac

# 3. Slugify Task Remainder
SLUG=$(echo "$TASK_REMAINDER" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g')

# Truncate slug to 35 characters without trailing hyphens
SLUG=$(echo "$SLUG" | cut -c 1-35 | sed -E 's/-+$//')

# 4. Assemble Candidate Branch Name
if [ -n "$TICKET_ID" ]; then
  TARGET_BRANCH="${TYPE_PREFIX}/${TICKET_ID}-${SLUG}"
else
  TARGET_BRANCH="${TYPE_PREFIX}/${SLUG}"
fi

# Fallback for empty slug
if [ "$TARGET_BRANCH" = "${TYPE_PREFIX}/" ]; then
  TARGET_BRANCH="${TYPE_PREFIX}/automated-task-$(date +%s)"
fi
```

### Step 4: Collision Detection and Resolution
Check for existing local or remote branches with the same target name:

```bash
COLLISION_FOUND=0

# Check local ref
if git show-ref --quiet --verify "refs/heads/$TARGET_BRANCH"; then
  COLLISION_FOUND=1
fi

# Check remote ref
if git ls-remote --exit-code --heads origin "$TARGET_BRANCH" >/dev/null 2>&1; then
  COLLISION_FOUND=1
fi

# Append deterministic timestamp suffix if collision exists
if [ "$COLLISION_FOUND" -eq 1 ]; then
  TIMESTAMP_SUFFIX=$(date +%s)
  TARGET_BRANCH="${TARGET_BRANCH}-${TIMESTAMP_SUFFIX}"
fi

# Final validation against Git ref format rules
git check-ref-format --branch "$TARGET_BRANCH" || {
  echo "FATAL: Branch name '$TARGET_BRANCH' violates Git reference rules." >&2
  exit 7
}
```

### Step 5: Branch Creation and Tracking Setup
Create and check out the new branch based on the synchronized base branch:

```bash
git checkout --quiet -b "$TARGET_BRANCH" "refs/heads/$BASE_BRANCH" || {
  echo "FATAL: Failed to create and checkout branch '$TARGET_BRANCH'." >&2
  exit 8
}
```

---

## Error Handling & Failure Recovery Matrix

| Failure Condition | Diagnostic Signal | Root Cause | Agent Remediation Action |
| :--- | :--- | :--- | :--- |
| **Dirty Working Tree** | `git status --porcelain` returns non-empty output | Uncommitted or untracked files left by operator or previous agent loop | **Halt immediately.** Do not stash or discard. Output diagnostic status listing modified files. Await operator cleanup or container reset. |
| **Pending Conflict/Rebase** | `.git/MERGE_HEAD` or `.git/rebase-merge` exists | Interrupted rebase, cherry-pick, or merge | Run `git rebase --abort 2>/dev/null \|\| git merge --abort 2>/dev/null`. If directory remains unclean, abort execution. |
| **Detached HEAD** | `git symbolic-ref -q HEAD` returns non-zero | Agent initialized on an isolated commit SHA | Discover canonical base branch (`main`/`master`) and run `git checkout --quiet <base_branch>` before branch creation. |
| **Base Divergence** | `git rev-list count origin..<base>` > 0 | Local base branch contains unpushed commits | **Halt immediately.** Do not rebase or force-push base branch. Alert operator to diverged base state. |
| **Offline Remote** | `git fetch` exits with code 128 / network timeout | Network failure or invalid remote credentials | Emit warning. Fall back to local canonical base branch if available; otherwise halt. |
| **Branch Collision** | `git show-ref` or `git ls-remote` returns existing ref | Branch name already in use by another session or ticket | Append deterministic UNIX timestamp suffix (`-<timestamp>`), re-validate ref format, and proceed. |
| **Permission Denied** | `fatal: could not read Username` or 403 HTTP | Invalid authentication token or missing SSH key | Fail fast with explicit auth diagnostic message. Do not attempt interactive prompt fallback. |

---

## Output Contract & State Manifest

Upon successful completion, emit the following JSON manifest to `.agent/lifecycle-state.json` and standard output:

```json
{
  "status": "READY",
  "stage": "git-branch-lifecycle",
  "branch_name": "feat/proj-102-fix-memory-leak-in-websocket-listener",
  "base_branch": "main",
  "base_commit_sha": "e2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1",
  "head_commit_sha": "e2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1",
  "clean_state_verified": true,
  "remote_synced": true,
  "collision_resolved": false,
  "worktree_path": "/workspace/repository",
  "timestamp_utc": "2026-10-10T23:26:43Z"
}
```

### Manifest Schema Fields
* `status` (string): Execution status (`READY` or `FAILED`).
* `stage` (string): Constant identifier `git-branch-lifecycle`.
* `branch_name` (string): The active, checked-out target branch.
* `base_branch` (string): The canonical baseline branch used as source.
* `base_commit_sha` (string): Full 40-character SHA of the base commit.
* `head_commit_sha` (string): Full 40-character SHA of the current HEAD.
* `clean_state_verified` (boolean): `true` if working tree was audited clean.
* `remote_synced` (boolean): `true` if remote fetch and fast-forward completed.
* `collision_resolved` (boolean): `true` if a collision required suffixing.
* `worktree_path` (string): Absolute filesystem path of the repository root.
* `timestamp_utc` (string): ISO-8601 UTC timestamp of execution.

---

## Negative Constraints

* Never perform destructive Git actions (`git clean -fdx`, `git reset --hard`) without explicit operator override.
* Never use `git stash` to hide untracked or uncommitted changes during automated execution.
* Never commit or push directly to protected base branches (`main`, `master`, `trunk`, `develop`).
* Never run interactive commands that require terminal input or interactive credentials (`GIT_TERMINAL_PROMPT=0` is strictly enforced).
* Never assume `main` is the default branch without dynamic remote discovery.