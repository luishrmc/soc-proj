---
name: git-commit-stager
description: Inspects dirty working trees after code modifications, selectively stages modified and created files by explicit pathspec, and drafts a validated Conventional Commit message.
---

# Git Commit Stager

Stage 3 operational skill for autonomous agent development loops. Audits working tree modifications following code execution, selectively stages target paths by explicit pathspec while filtering artifacts, extracts structural change metrics, and drafts a validated Conventional Commits 1.0.0 message.

## Overview & Role in Pipeline

This skill serves as Stage 3 in the autonomous agent development pipeline:

`git-branch-lifecycle` -> `Code Modification Loop` -> `git-commit-stager` -> `git-safety-guard` -> `git-release-tagger`

### Input Dependencies
* Repository checked out on active task branch created by Stage 1 (`git-branch-lifecycle`).
* Dirty working tree resulting from Stage 2 (`Code Modification Loop`).
* Optional task context from `.agent/lifecycle-state.json`.

### Handoff Boundaries
* Selectively stages modified, created, renamed, or deleted files using explicit pathspecs.
* Filters out untracked artifacts, temporary files, and sensitive credentials.
* Drafts and formats a structured Conventional Commit message.
* Emits `.agent/commit-staging-manifest.json` for Stage 4 (`git-safety-guard`).
* **Strict Non-Execution Invariant:** This skill DOES NOT execute `git commit`. Commit creation authority belongs exclusively to Stage 4 after pre-flight safety and test validations pass.

---

## File Staging Protocol & Safety Rules

### 1. Absolute Negative Staging Constraints
The following commands are strictly prohibited in automated execution:
* `git add .`
* `git add -A`
* `git add --all`
* `git add *`
* Any unquoted wildcard glob expansion (such as `git add src/*`).

Every file added to the Git index must be passed as an explicit, quoted relative pathspec: `git add -- "$FILE_PATH"`.

### 2. Status Auditing and Parsing
Audit working tree modifications non-interactively using porcelain syntax:

```bash
# Verify working tree is dirty
CHANGES_COUNT=$(git status --porcelain=v1 2>/dev/null | wc -l | tr -d ' ')
if [ "$CHANGES_COUNT" -eq 0 ]; then
  echo "FATAL: Working tree is clean. No modifications detected from Code Modification Loop." >&2
  exit 1
fi
```

Parse changed files into discrete categories:

```bash
MODIFIED_FILES=()
DELETED_FILES=()
UNTRACKED_FILES=()
IGNORED_ARTIFACTS=()

while IFS= read -r line; do
  [ -z "$line" ] && continue
  INDEX_CHAR="${line:0:1}"
  WORKTREE_CHAR="${line:1:1}"
  FILE_PATH="${line:3}"

  # Handle renamed files: R  old -> new
  if [[ "$line" =~ ^R ]]; then
    FILE_PATH=$(echo "$line" | awk -F ' -> ' '{print $2}' | sed -e 's/^"//' -e 's/"$//')
  fi

  # Filter out secret patterns and sensitive files
  case "$FILE_PATH" in
    *.env*|*.pem|*.key|*id_rsa*|*token*|*credential*|*.pfx|*.p12)
      IGNORED_ARTIFACTS+=("$FILE_PATH")
      continue
      ;;
    *.log|*.tmp|*.swp|*.bak|*.pyc|__pycache__/*|.DS_Store|thumbs.db|coverage/*)
      IGNORED_ARTIFACTS+=("$FILE_PATH")
      continue
      ;;
  esac

  # Verify file is not matched by .gitignore
  if git check-ignore -q -- "$FILE_PATH" 2>/dev/null; then
    IGNORED_ARTIFACTS+=("$FILE_PATH")
    continue
  fi

  # Categorize by status code
  if [ "$INDEX_CHAR" = "D" ] || [ "$WORKTREE_CHAR" = "D" ]; then
    DELETED_FILES+=("$FILE_PATH")
  elif [ "$INDEX_CHAR" = "?" ] && [ "$WORKTREE_CHAR" = "?" ]; then
    UNTRACKED_FILES+=("$FILE_PATH")
  else
    MODIFIED_FILES+=("$FILE_PATH")
  fi
done < <(git status --porcelain=v1 2>/dev/null)
```

### 3. Explicit Path-by-Path Staging Execution
Stage permitted files using explicit pathspecs and standard flags:

```bash
STAGED_FILES=()

# Stage modified and newly created files
for FILE in "${MODIFIED_FILES[@]}" "${UNTRACKED_FILES[@]}"; do
  if [ -f "$FILE" ]; then
    git add --quiet -- "$FILE" || {
      echo "FATAL: Failed to stage file: $FILE" >&2
      exit 2
    }
    STAGED_FILES+=("$FILE")
  fi
done

# Stage deleted files
for FILE in "${DELETED_FILES[@]}"; do
  git rm --quiet --cached --ignore-unmatch -- "$FILE" >/dev/null 2>&1 || git rm --quiet -f -- "$FILE" 2>/dev/null || true
  STAGED_FILES+=("$FILE")
done

# Verify at least one file was staged
STAGED_COUNT=$(git diff --staged --name-only 2>/dev/null | wc -l | tr -d ' ')
if [ "$STAGED_COUNT" -eq 0 ]; then
  echo "FATAL: No files were staged after filtering out ignored artifacts." >&2
  exit 3
fi
```

---

## Conventional Commit Drafting Engine

### 1. Semantic Type Extraction Heuristics
Derive the commit type from the set of staged file paths and task metadata:

```bash
COMMIT_TYPE="chore"
HAS_SRC=0
HAS_TEST=0
HAS_DOCS=0
HAS_BUILD=0
HAS_CI=0

for FILE in "${STAGED_FILES[@]}"; do
  case "$FILE" in
    *test*|*spec*|tests/*|__tests__/*)
      HAS_TEST=1
      ;;
    *.md|docs/*|doc/*|LICENSE*|README*)
      HAS_DOCS=1
      ;;
    .github/*|.gitlab-ci.yml|Jenkinsfile|Dockerfile|docker-compose*)
      HAS_CI=1
      ;;
    package.json|package-lock.json|Cargo.toml|Cargo.lock|go.mod|go.sum|pom.xml|requirements*.txt)
      HAS_BUILD=1
      ;;
    src/*|lib/*|pkg/*|app/*|*.ts|*.js|*.py|*.go|*.rs|*.java|*.c|*.cpp)
      HAS_SRC=1
      ;;
  esac
done

# Map file distribution and task context to type
TASK_DESC=""
if [ -f ".agent/lifecycle-state.json" ]; then
  TASK_BRANCH=$(grep -o '"branch_name": "[^"]*' .agent/lifecycle-state.json | cut -d'"' -f4)
  TASK_PREFIX=$(echo "$TASK_BRANCH" | cut -d'/' -f1)
  case "$TASK_PREFIX" in
    feat|fix|refactor|test|docs|perf|build|ci|chore)
      COMMIT_TYPE="$TASK_PREFIX"
      ;;
  esac
fi

# Fallback type inference based on modified file patterns
if [ -z "$COMMIT_TYPE" ] || [ "$COMMIT_TYPE" = "chore" ]; then
  if [ "$HAS_SRC" -eq 1 ]; then
    COMMIT_TYPE="feat"
  elif [ "$HAS_TEST" -eq 1 ] && [ "$HAS_SRC" -eq 0 ]; then
    COMMIT_TYPE="test"
  elif [ "$HAS_DOCS" -eq 1 ] && [ "$HAS_SRC" -eq 0 ]; then
    COMMIT_TYPE="docs"
  elif [ "$HAS_CI" -eq 1 ]; then
    COMMIT_TYPE="ci"
  elif [ "$HAS_BUILD" -eq 1 ]; then
    COMMIT_TYPE="build"
  fi
fi
```

### 2. Module Scope Derivation Heuristics
Extract concise module scope based on directory path consensus:

```bash
COMMIT_SCOPE=""

# Collect top-level functional directories under root or standard source roots
SCOPES=()
for FILE in "${STAGED_FILES[@]}"; do
  DIR=$(echo "$FILE" | sed -E 's|^(src/|lib/|pkg/|app/)?([^/]+)/.*|\2|')
  if [ -n "$DIR" ] && [ "$DIR" != "$FILE" ]; then
    SCOPES+=("$DIR")
  fi
done

# Determine most frequent scope
if [ "${#SCOPES[@]}" -gt 0 ]; then
  UNIQUE_SCOPES=($(printf "%s\n" "${SCOPES[@]}" | sort -u))
  if [ "${#UNIQUE_SCOPES[@]}" -eq 1 ]; then
    # All changes localized to a single module
    COMMIT_SCOPE="${UNIQUE_SCOPES[0]}"
  elif [ "${#UNIQUE_SCOPES[@]}" -le 3 ]; then
    # Shared changes across two modules
    COMMIT_SCOPE=$(printf "%s\n" "${SCOPES[@]}" | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}')
  fi
fi

# Sanitize scope: lowercase alphanumeric, hyphens only
COMMIT_SCOPE=$(echo "$COMMIT_SCOPE" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
```

### 3. Subject and Body Generation Protocol
Construct header and body following Conventional Commits 1.0.0 and the 50/72 character rule:

```bash
# 1. Derive imperative subject from branch or primary staged changes
SUBJECT_ACTION=""
if [ -f ".agent/lifecycle-state.json" ]; then
  BRANCH_NAME=$(grep -o '"branch_name": "[^"]*' .agent/lifecycle-state.json | cut -d'"' -f4)
  # Extract slug without prefix and ticket ID
  SLUG_RAW=$(echo "$BRANCH_NAME" | sed -E 's|^[a-z]+/||' | sed -E 's|^[a-z]+-[0-9]+-||')
  SUBJECT_ACTION=$(echo "$SLUG_RAW" | tr '-' ' ')
fi

if [ -z "$SUBJECT_ACTION" ]; then
  SUBJECT_ACTION="update $(echo "${STAGED_FILES[0]}" | xargs basename)"
fi

# Format subject: lowercase, no period, imperative mood
SUBJECT_ACTION=$(echo "$SUBJECT_ACTION" | tr '[:upper:]' '[:lower:]' | sed -e 's/\.$//')

# Construct header
if [ -n "$COMMIT_SCOPE" ]; then
  HEADER="${COMMIT_TYPE}(${COMMIT_SCOPE}): ${SUBJECT_ACTION}"
else
  HEADER="${COMMIT_TYPE}: ${SUBJECT_ACTION}"
fi

# Enforce 72 character hard limit on header
if [ "${#HEADER}" -gt 72 ]; then
  MAX_LEN=$((72 - ${#COMMIT_TYPE} - ${#COMMIT_SCOPE} - 6))
  TRUNCATED_ACTION=$(echo "$SUBJECT_ACTION" | cut -c 1-"$MAX_LEN" | sed -E 's/ +[^ ]*$/.../')
  if [ -n "$COMMIT_SCOPE" ]; then
    HEADER="${COMMIT_TYPE}(${COMMIT_SCOPE}): ${TRUNCATED_ACTION}"
  else
    HEADER="${COMMIT_TYPE}: ${TRUNCATED_ACTION}"
  fi
fi

# 2. Extract Diff Statistics for Body Rationale
DIFF_STAT=$(git diff --staged --shortstat 2>/dev/null || echo "changes staged")
STAGED_DIFF_STAT_FULL=$(git diff --staged --stat --compact-summary 2>/dev/null)

# 3. Construct Bulleted Body wrapped at 72 characters
BODY_LINES=()
for FILE in "${STAGED_FILES[@]}"; do
  BODY_LINES+=("- Modify ${FILE}")
done

COMMIT_BODY=$(printf "%s\n" "${BODY_LINES[@]}")
```

### 4. Breaking Change Detection
Detect breaking API or schema changes:

```bash
IS_BREAKING=false
BREAKING_DESCRIPTION=""

# Scan staged diff for explicit breaking annotations or contract breaks
if git diff --staged -G"BREAKING[ -]CHANGE" >/dev/null 2>&1; then
  IS_BREAKING=true
  BREAKING_DESCRIPTION="Modifies existing public interface contracts."
fi

# Adjust header and footer if breaking
if [ "$IS_BREAKING" = true ]; then
  if [ -n "$COMMIT_SCOPE" ]; then
    HEADER="${COMMIT_TYPE}(${COMMIT_SCOPE})!: ${SUBJECT_ACTION}"
  else
    HEADER="${COMMIT_TYPE}!: ${SUBJECT_ACTION}"
  fi
  FULL_COMMIT_MESSAGE="${HEADER}

${COMMIT_BODY}

BREAKING CHANGE: ${BREAKING_DESCRIPTION}"
else
  FULL_COMMIT_MESSAGE="${HEADER}

${COMMIT_BODY}"
fi
```

---

## Error Handling & Edge Cases

### 1. Clean Working Tree Post-Execution
* **Diagnostic Check:** `git status --porcelain=v1` returns zero lines.
* **Root Cause:** Code Modification Loop produced no file updates or crashed silently.
* **Remediation Action:** Halt execution with exit code 1. Do not proceed to staging or commit drafting. Report clean state to supervisor.

### 2. Large Diffs Exceeding Token Budgets
* **Diagnostic Check:** `git diff --staged | wc -c` exceeds 64 KB.
* **Root Cause:** Bulk refactoring, auto-formatting, package lockfile updates, or generated code.
* **Remediation Action:** Do not pass the raw patch to commit drafting. Fall back to `git diff --staged --stat` and summarize changes file-by-file based on path structure rather than line-by-line diff content.

### 3. Mixed Changes Across Unrelated Features
* **Diagnostic Check:** Staged paths span disjoint top-level modules without a unified scope.
* **Remediation Action:** Stage only files directly aligned with the active branch task identifier. Leave peripheral files unstaged, record their paths in `unstaged_files`, and emit a warning in the manifest.

### 4. Collateral Untracked Artifacts
* **Diagnostic Check:** Untracked files match temporary, binary, or secret file patterns.
* **Remediation Action:** Never stage matching paths. Append all excluded paths to `unstaged_files`. Append critical secret findings to `.agent/staging-warnings.log`.

---

## Output Contract & State Manifest

Upon completing selective staging and commit message drafting, write the state manifest to `.agent/commit-staging-manifest.json` and standard output:

```json
{
  "status": "STAGED",
  "stage": "git-commit-stager",
  "branch_name": "feat/proj-102-user-phone-validation",
  "staged_files": [
    "src/auth/validator.ts",
    "src/auth/types.ts",
    "tests/auth/validator.test.ts"
  ],
  "unstaged_files": [
    ".env.test.local",
    "debug.log"
  ],
  "commit_type": "feat",
  "commit_scope": "auth",
  "is_breaking": false,
  "commit_subject": "feat(auth): add user phone validation",
  "commit_body": "- Modify src/auth/validator.ts\n- Modify src/auth/types.ts\n- Modify tests/auth/validator.test.ts",
  "full_commit_message": "feat(auth): add user phone validation\n\n- Modify src/auth/validator.ts\n- Modify src/auth/types.ts\n- Modify tests/auth/validator.test.ts",
  "diff_stat": "3 files changed, 84 insertions(+), 6 deletions(-)",
  "lines_added": 84,
  "lines_deleted": 6,
  "execution_authority": "DELEGATED_TO_GIT_SAFETY_GUARD",
  "timestamp_utc": "2026-10-10T23:30:15Z"
}
```

### Manifest Schema Fields
* `status` (string): State marker (`STAGED` or `FAILED`).
* `stage` (string): Constant identifier `git-commit-stager`.
* `branch_name` (string): Active branch name.
* `staged_files` (array of strings): Explicit relative paths added to the Git index.
* `unstaged_files` (array of strings): Dirty or untracked paths intentionally excluded from staging.
* `commit_type` (string): Conventional Commits type (`feat`, `fix`, `chore`, etc.).
* `commit_scope` (string or null): Extracted module scope.
* `is_breaking` (boolean): `true` if breaking changes were detected.
* `commit_subject` (string): Single-line header formatted according to the 50/72 rule.
* `commit_body` (string): Explanatory summary of staged changes.
* `full_commit_message` (string): Complete commit message payload ready for Stage 4.
* `diff_stat` (string): Output from `git diff --staged --shortstat`.
* `lines_added` (integer): Total lines added across staged files.
* `lines_deleted` (integer): Total lines deleted across staged files.
* `execution_authority` (string): Fixed flag `DELEGATED_TO_GIT_SAFETY_GUARD`.
* `timestamp_utc` (string): ISO-8601 UTC timestamp of staging completion.

---

## Negative Constraints

* Never execute `git commit` or create Git commit objects directly within this skill.
* Never execute `git add .`, `git add -A`, or wildcard glob patterns.
* Never stage files identified as secrets, credentials, environment configurations, or build caches.
* Never invent fictitious commit scopes or types outside the Conventional Commits 1.0.0 taxonomy.
* Never proceed if the working tree is clean or if all modifications were excluded by safety filters.