#!/usr/bin/env bash
set -euo pipefail

export GIT_TERMINAL_PROMPT=0
export GIT_PAGER=cat

CUSTOM_SUBJECT="${1:-}"

CHANGES_COUNT=$(git status --porcelain=v1 2>/dev/null | wc -l | tr -d ' ')
if [ "$CHANGES_COUNT" -eq 0 ]; then
  echo "FATAL: Working tree is clean. No modifications available to stage." >&2
  exit 1
fi

MODIFIED_FILES=()
DELETED_FILES=()
UNTRACKED_FILES=()
IGNORED_ARTIFACTS=()

while IFS= read -r line; do
  [ -z "$line" ] && continue
  INDEX_CHAR="${line:0:1}"
  WORKTREE_CHAR="${line:1:1}"
  FILE_PATH="${line:3}"

  if [[ "$line" =~ ^R ]]; then
    FILE_PATH=$(echo "$line" | awk -F ' -> ' '{print $2}' | sed -e 's/^"//' -e 's/"$//')
  fi

  case "$FILE_PATH" in
    *.env*|*.pem|*.key|*id_rsa*|*token*|*credential*|*.pfx|*.p12|*.log|*.tmp|*.swp|*.bak|*.pyc|__pycache__/*|.DS_Store|thumbs.db|coverage/*|.agent/*)
      IGNORED_ARTIFACTS+=("$FILE_PATH")
      continue
      ;;
  esac

  if git check-ignore -q -- "$FILE_PATH" 2>/dev/null; then
    IGNORED_ARTIFACTS+=("$FILE_PATH")
    continue
  fi

  if [ "$INDEX_CHAR" = "D" ] || [ "$WORKTREE_CHAR" = "D" ]; then
    DELETED_FILES+=("$FILE_PATH")
  elif [ "$INDEX_CHAR" = "?" ] && [ "$WORKTREE_CHAR" = "?" ]; then
    UNTRACKED_FILES+=("$FILE_PATH")
  else
    MODIFIED_FILES+=("$FILE_PATH")
  fi
done < <(git status --porcelain=v1 2>/dev/null)

STAGED_FILES=()
for FILE in "${MODIFIED_FILES[@]}" "${UNTRACKED_FILES[@]}"; do
  if [ -f "$FILE" ] || [ -L "$FILE" ]; then
    git add --quiet -- "$FILE" || {
      echo "FATAL: Failed to stage file: $FILE" >&2
      exit 2
    }
    STAGED_FILES+=("$FILE")
  fi
done

for FILE in "${DELETED_FILES[@]}"; do
  git rm --quiet --cached --ignore-unmatch -- "$FILE" >/dev/null 2>&1 || git rm --quiet -f -- "$FILE" 2>/dev/null || true
  STAGED_FILES+=("$FILE")
done

STAGED_COUNT=$(git diff --staged --name-only 2>/dev/null | wc -l | tr -d ' ')
if [ "$STAGED_COUNT" -eq 0 ]; then
  echo "FATAL: Zero files staged after safety filtering." >&2
  exit 3
fi

COMMIT_TYPE="chore"
HAS_SRC=0; HAS_TEST=0; HAS_DOCS=0; HAS_BUILD=0; HAS_CI=0
for FILE in "${STAGED_FILES[@]}"; do
  case "$FILE" in
    *test*|*spec*|tests/*|__tests__/*) HAS_TEST=1 ;;
    *.md|docs/*|doc/*|LICENSE*|README*) HAS_DOCS=1 ;;
    .github/*|.gitlab-ci.yml|Jenkinsfile|Dockerfile|docker-compose*) HAS_CI=1 ;;
    package.json|package-lock.json|Cargo.toml|Cargo.lock|go.mod|go.sum|pyproject.toml|requirements*.txt) HAS_BUILD=1 ;;
    src/*|lib/*|pkg/*|app/*|skills/*|*.ts|*.js|*.py|*.go|*.rs|*.sh) HAS_SRC=1 ;;
  esac
done

BRANCH_NAME=$(git branch --show-current 2>/dev/null || echo "HEAD")
if [ -f ".agent/lifecycle-state.json" ]; then
  TASK_BRANCH=$(grep -o '"branch_name": "[^"]*' .agent/lifecycle-state.json | cut -d'"' -f4 || true)
  [ -n "$TASK_BRANCH" ] && BRANCH_NAME="$TASK_BRANCH"
fi
TASK_PREFIX=$(echo "$BRANCH_NAME" | cut -d'/' -f1)
case "$TASK_PREFIX" in
  feat|fix|refactor|test|docs|perf|build|ci|chore) COMMIT_TYPE="$TASK_PREFIX" ;;
  *)
    if [ "$HAS_SRC" -eq 1 ]; then COMMIT_TYPE="feat"
    elif [ "$HAS_TEST" -eq 1 ]; then COMMIT_TYPE="test"
    elif [ "$HAS_DOCS" -eq 1 ]; then COMMIT_TYPE="docs"
    elif [ "$HAS_CI" -eq 1 ]; then COMMIT_TYPE="ci"
    elif [ "$HAS_BUILD" -eq 1 ]; then COMMIT_TYPE="build"
    fi
    ;;
esac

SCOPES=()
for FILE in "${STAGED_FILES[@]}"; do
  DIR=$(echo "$FILE" | sed -E 's|^(src/|lib/|pkg/|app/|skills/)?([^/]+)/.*|\2|')
  if [ -n "$DIR" ] && [ "$DIR" != "$FILE" ]; then
    SCOPES+=("$DIR")
  fi
done
COMMIT_SCOPE=""
if [ "${#SCOPES[@]}" -gt 0 ]; then
  COMMIT_SCOPE=$(printf "%s\n" "${SCOPES[@]}" | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
fi

if [ -n "$CUSTOM_SUBJECT" ]; then
  SUBJECT_ACTION="$CUSTOM_SUBJECT"
elif [[ "$BRANCH_NAME" == */* ]]; then
  SLUG_RAW=$(echo "$BRANCH_NAME" | sed -E 's|^[a-z]+/||' | sed -E 's|^[a-z]+-[0-9]+-||')
  SUBJECT_ACTION=$(echo "$SLUG_RAW" | tr '-' ' ')
else
  SUBJECT_ACTION="update $(basename "${STAGED_FILES[0]}")"
fi
SUBJECT_ACTION=$(echo "$SUBJECT_ACTION" | tr '[:upper:]' '[:lower:]' | sed -e 's/\.$//')

if [ -n "$COMMIT_SCOPE" ]; then
  HEADER="${COMMIT_TYPE}(${COMMIT_SCOPE}): ${SUBJECT_ACTION}"
else
  HEADER="${COMMIT_TYPE}: ${SUBJECT_ACTION}"
fi
if [ "${#HEADER}" -gt 72 ]; then
  HEADER="${HEADER:0:69}..."
fi

mkdir -p .agent
python3 - "$BRANCH_NAME" "$COMMIT_TYPE" "$COMMIT_SCOPE" "$HEADER" "${STAGED_FILES[@]}" -- "${IGNORED_ARTIFACTS[@]}" <<'PY'
import json, subprocess, sys
from datetime import datetime, timezone

args = sys.argv[1:]
sep = args.index("--")
branch, ctype, cscope, header = args[0], args[1], args[2] or None, args[3]
staged = args[4:sep]
unstaged = args[sep+1:]

body = "\n".join(f"- Modify {f}" for f in staged)
full_msg = f"{header}\n\n{body}"
diff_stat = subprocess.check_output(["git", "diff", "--staged", "--shortstat"], text=True).strip()
numstat = subprocess.check_output(["git", "diff", "--staged", "--numstat"], text=True).strip().splitlines()
added = sum(int(line.split()[0]) for line in numstat if line.split()[0].isdigit())
deleted = sum(int(line.split()[1]) for line in numstat if line.split()[1].isdigit())

manifest = {
    "status": "STAGED",
    "stage": "git-commit-stager",
    "branch_name": branch,
    "staged_files": staged,
    "unstaged_files": unstaged,
    "commit_type": ctype,
    "commit_scope": cscope,
    "is_breaking": False,
    "commit_subject": header,
    "commit_body": body,
    "full_commit_message": full_msg,
    "diff_stat": diff_stat,
    "lines_added": added,
    "lines_deleted": deleted,
    "execution_authority": "DELEGATED_TO_GIT_SAFETY_GUARD",
    "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(".agent/commit-staging-manifest.json", "w") as f:
    json.dump(manifest, f, indent=2)
print(json.dumps(manifest, indent=2))
PY
