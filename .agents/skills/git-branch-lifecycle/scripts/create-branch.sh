#!/usr/bin/env bash
set -euo pipefail

export GIT_TERMINAL_PROMPT=0
export GIT_PAGER=cat

RAW_TASK_INPUT="${1:-}"
if [ -z "$RAW_TASK_INPUT" ]; then
  echo "FATAL: Task description or ticket identifier argument is required." >&2
  exit 1
fi

# 1. Verify Git repository root
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "FATAL: Current working directory is not a Git repository." >&2
  exit 1
}

# 2. Verify working tree cleanliness
STATUS_OUTPUT=$(git status --porcelain=v1 2>/dev/null)
if [ -n "$STATUS_OUTPUT" ]; then
  echo "FATAL: Working tree is dirty. Halting to preserve uncommitted work." >&2
  echo "$STATUS_OUTPUT" >&2
  exit 2
fi

# 3. Verify no active rebase/merge/cherry-pick/revert
GIT_DIR=$(git rev-parse --git-dir)
if [ -d "$GIT_DIR/rebase-merge" ] || [ -d "$GIT_DIR/rebase-apply" ] || \
   [ -f "$GIT_DIR/MERGE_HEAD" ] || [ -f "$GIT_DIR/CHERRY_PICK_HEAD" ] || \
   [ -f "$GIT_DIR/REVERT_HEAD" ]; then
  echo "FATAL: Pending Git rebase, merge, cherry-pick, or revert operation detected." >&2
  exit 3
fi

# 4. Dynamic canonical base branch discovery
BASE_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)
if [ -z "$BASE_BRANCH" ]; then
  for CANDIDATE in main master trunk develop; do
    if git show-ref --quiet --verify "refs/remotes/origin/$CANDIDATE"; then
      BASE_BRANCH="$CANDIDATE"
      break
    fi
  done
fi
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

# 5. Base branch synchronization
git checkout --quiet "$BASE_BRANCH"
REMOTE_SYNCED=false
if git remote get-url origin >/dev/null 2>&1; then
  if git fetch --quiet --prune origin "$BASE_BRANCH" 2>/dev/null; then
    REMOTE_SYNCED=true
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
  fi
fi

# 6. Deterministic branch naming
TICKET_ID=$(echo "$RAW_TASK_INPUT" | grep -oE '^[A-Za-z]+-[0-9]+' | tr '[:upper:]' '[:lower:]' || true)
TASK_REMAINDER=$(echo "$RAW_TASK_INPUT" | sed -E 's/^[A-Za-z]+-[0-9]+[: ]*//')
FIRST_WORD=$(echo "$TASK_REMAINDER" | awk '{print tolower($1)}')

case "$FIRST_WORD" in
  add|create|implement|feat|feature) TYPE_PREFIX="feat" ;;
  fix|resolve|patch|bug)             TYPE_PREFIX="fix" ;;
  refactor|reorganize|clean)         TYPE_PREFIX="refactor" ;;
  test|tests|coverage)               TYPE_PREFIX="test" ;;
  doc|docs|document|documentation)   TYPE_PREFIX="docs" ;;
  *)                                 TYPE_PREFIX="chore" ;;
esac

SLUG=$(echo "$TASK_REMAINDER" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g' | cut -c 1-35 | sed -E 's/-+$//')
if [ -n "$TICKET_ID" ]; then
  TARGET_BRANCH="${TYPE_PREFIX}/${TICKET_ID}-${SLUG}"
else
  TARGET_BRANCH="${TYPE_PREFIX}/${SLUG}"
fi
if [ "$TARGET_BRANCH" = "${TYPE_PREFIX}/" ]; then
  TARGET_BRANCH="${TYPE_PREFIX}/automated-task-$(date +%s)"
fi

# 7. Collision detection and resolution
COLLISION_RESOLVED=false
if git show-ref --quiet --verify "refs/heads/$TARGET_BRANCH" || \
   git ls-remote --exit-code --heads origin "$TARGET_BRANCH" >/dev/null 2>&1; then
  TARGET_BRANCH="${TARGET_BRANCH}-$(date +%s)"
  COLLISION_RESOLVED=true
fi

git check-ref-format --branch "$TARGET_BRANCH" || {
  echo "FATAL: Branch name '$TARGET_BRANCH' violates Git reference rules." >&2
  exit 7
}

git checkout --quiet -b "$TARGET_BRANCH" "refs/heads/$BASE_BRANCH" || {
  echo "FATAL: Failed to create and checkout branch '$TARGET_BRANCH'." >&2
  exit 8
}

BASE_SHA=$(git rev-parse --verify "refs/heads/$BASE_BRANCH")
HEAD_SHA=$(git rev-parse --verify HEAD)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
TIMESTAMP_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p .agent
cat <<EOF > .agent/lifecycle-state.json
{
  "status": "READY",
  "stage": "git-branch-lifecycle",
  "branch_name": "$TARGET_BRANCH",
  "base_branch": "$BASE_BRANCH",
  "base_commit_sha": "$BASE_SHA",
  "head_commit_sha": "$HEAD_SHA",
  "clean_state_verified": true,
  "remote_synced": $REMOTE_SYNCED,
  "collision_resolved": $COLLISION_RESOLVED,
  "worktree_path": "$WORKTREE_PATH",
  "timestamp_utc": "$TIMESTAMP_UTC"
}
EOF

cat .agent/lifecycle-state.json
