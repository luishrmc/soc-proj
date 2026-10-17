#!/usr/bin/env bash
# pre-task-audit.sh: preconditions before a task loop starts.
# Checks: git repo present, no unstaged changes to protected files, tools reachable,
# a boundary snapshot is taken. Exit 1 blocks the loop.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[ERROR][pre-task-audit] Not a git repository. Run: git init" >&2
  exit 1
fi

bash "$HOOK_DIR/env-check.sh"

if ! git diff --quiet -- requirements.txt .agents/manifest.json cora7z/app/hw/utils 2>/dev/null; then
  echo "[ERROR][pre-task-audit] Protected files have uncommitted changes. Commit or revert them first." >&2
  exit 1
fi

mkdir -p out
python3 "$HOOK_DIR/boundary-guard.py" snapshot

echo "[OK][pre-task-audit] Loop authorized. Boundary snapshot recorded."
