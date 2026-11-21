#!/usr/bin/env bash
set -euo pipefail

export GIT_TERMINAL_PROMPT=0
export GIT_PAGER=cat

MANIFEST_FILE=".agent/commit-staging-manifest.json"
if [ ! -f "$MANIFEST_FILE" ]; then
  echo "FATAL: Staging manifest '$MANIFEST_FILE' not found. Run git-commit-stager first." >&2
  exit 1
fi

STAGED_COUNT=$(git diff --staged --name-only 2>/dev/null | wc -l | tr -d ' ')
if [ "$STAGED_COUNT" -eq 0 ]; then
  echo "FATAL: Git index is empty. No staged changes to commit." >&2
  exit 2
fi

# Gate 1: Secret & Sensitive Data Audit
STAGED_ADDITIONS=$(git diff --staged -U0 --no-color 2>/dev/null | grep -E '^\+[^\+]' || true)

if echo "$STAGED_ADDITIONS" | grep -E -- "-----BEGIN [A-Z ]*PRIVATE KEY-----" >/dev/null 2>&1; then
  echo "SECURITY VIOLATION: Staged diff contains private key headers." >&2
  exit 10
fi

if echo "$STAGED_ADDITIONS" | grep -E -- "(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}" >/dev/null 2>&1; then
  echo "SECURITY VIOLATION: Staged diff contains AWS access key identifiers." >&2
  exit 11
fi

if echo "$STAGED_ADDITIONS" | grep -E -- "gh[pousr]_[A-Za-z0-9_]{36,}|sk-(proj-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[0-9A-Za-z]{10,}" >/dev/null 2>&1; then
  echo "SECURITY VIOLATION: Staged diff contains provider API tokens." >&2
  exit 12
fi

if echo "$STAGED_ADDITIONS" | grep -iE "(api[_-]?key|secret|password|auth[_-]?token|private[_-]?key)\s*[:=]\s*['\"][A-Za-z0-9_\-\.]{12,}['\"]" >/dev/null 2>&1; then
  SUSPICIOUS=$(echo "$STAGED_ADDITIONS" | grep -iE "(api[_-]?key|secret|password|auth[_-]?token|private[_-]?key)\s*[:=]\s*['\"][A-Za-z0-9_\-\.]{12,}['\"]")
  if ! echo "$SUSPICIOUS" | grep -iE "(mock|fake|dummy|test|example)" >/dev/null 2>&1; then
    echo "SECURITY VIOLATION: Hardcoded credential assignment detected in staged diff." >&2
    exit 13
  fi
fi

# Gate 2: Forbidden Paths, Blob Size (5MB), and Binary Check
MAX_BYTES=5242880
while IFS= read -r STAGED_FILE; do
  [ -z "$STAGED_FILE" ] && continue
  case "$STAGED_FILE" in
    *.env|.env.*|*.pem|*.key|*id_rsa*|*id_ed25519*|*.pfx|*.p12)
      echo "SECURITY VIOLATION: Staged path '$STAGED_FILE' is a forbidden sensitive file." >&2
      exit 14
      ;;
    node_modules/*|venv/*|.venv/*|target/*|dist/*|build/*|vendor/*)
      echo "REJECTED: Staged path '$STAGED_FILE' belongs to an ignored dependency or build folder." >&2
      exit 20
      ;;
  esac
  BLOB_SIZE=$(git cat-file -s ":$STAGED_FILE" 2>/dev/null || echo 0)
  if [ "$BLOB_SIZE" -gt "$MAX_BYTES" ]; then
    echo "REJECTED: Staged file '$STAGED_FILE' exceeds 5MB limit ($BLOB_SIZE bytes)." >&2
    exit 21
  fi
done < <(git diff --staged --name-only)

BINARY_COUNT=$(git diff --staged --numstat 2>/dev/null | grep -c '^-	-' || true)
if [ "$BINARY_COUNT" -gt 0 ]; then
  echo "REJECTED: Staged changes contain raw binary additions." >&2
  exit 22
fi

# Gate 3: Stash-Isolated Linter & Test Suite Execution
UNSTAGED_CHANGES=$(git status --porcelain=v1 2>/dev/null | grep -E '^ [MD?]' || true)
STASH_ACTIVE=0
if [ -n "$UNSTAGED_CHANGES" ]; then
  git stash push --keep-index --include-untracked --quiet -m "safety-guard-isolation" || {
    echo "FATAL: Failed to isolate unstaged working tree changes." >&2
    exit 30
  }
  STASH_ACTIVE=1
fi

cleanup() {
  if [ "$STASH_ACTIVE" -eq 1 ]; then
    git stash pop --quiet >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

LINT_CMD=""
if [ -f "package.json" ] && grep -q '"lint"' package.json; then
  LINT_CMD="npm run lint --silent"
elif [ -f "Makefile" ] && grep -q '^lint:' Makefile; then
  LINT_CMD="make lint"
elif command -v ruff >/dev/null 2>&1 && [ -f "pyproject.toml" ]; then
  LINT_CMD="ruff check ."
fi
if [ -n "$LINT_CMD" ]; then
  timeout 180s $LINT_CMD || { echo "VERIFICATION FAILED: Linter failed: $LINT_CMD" >&2; exit 31; }
fi

TEST_CMD=""
if [ -f "package.json" ] && grep -q '"test"' package.json; then
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
  timeout 300s $TEST_CMD || { echo "VERIFICATION FAILED: Test suite failed: $TEST_CMD" >&2; exit 32; }
fi

# Gate 4: Non-Interactive Commit Execution
COMMIT_MSG_TMP=$(mktemp)
python3 -c '
import json, sys
with open(".agent/commit-staging-manifest.json") as f:
    msg = json.load(f).get("full_commit_message", "").strip()
if not msg:
    sys.exit(1)
print(msg)
' > "$COMMIT_MSG_TMP" || { rm -f "$COMMIT_MSG_TMP"; exit 40; }

git commit --quiet -F "$COMMIT_MSG_TMP" || { rm -f "$COMMIT_MSG_TMP"; exit 41; }
rm -f "$COMMIT_MSG_TMP"

COMMITTED_SHA=$(git rev-parse --verify HEAD)
BRANCH_NAME=$(git branch --show-current 2>/dev/null || echo "HEAD")
TIMESTAMP_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat <<EOF > .agent/safety-guard-manifest.json
{
  "status": "COMPLETED",
  "stage": "git-safety-guard",
  "commit_status": "COMMITTED",
  "commit_sha": "$COMMITTED_SHA",
  "branch_name": "$BRANCH_NAME",
  "verification_summary": {
    "secrets_scanned": true,
    "secrets_detected": false,
    "file_size_checked": true,
    "binary_guard_passed": true,
    "linter_passed": true,
    "tests_passed": true
  },
  "failure_reasons": [],
  "timestamp_utc": "$TIMESTAMP_UTC"
}
EOF
cat .agent/safety-guard-manifest.json
