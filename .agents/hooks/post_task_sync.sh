#!/usr/bin/env bash
# post_task_sync.sh: Lifecycle hook to validate evidence, finalize task, refresh memory, and sync plan.
# Usage: ./post_task_sync.sh <TASK_ID> <EVIDENCE> [NOTES]
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

TASK_ID="${1:-}"
EVIDENCE="${2:-}"
NOTES="${3:-}"

# 1. Determine task ID if not supplied
if [ -z "$TASK_ID" ]; then
    IN_PROGRESS=$(python3 -c "
import csv, sys
from pathlib import Path
root = Path('$REPO_ROOT')
csv_path = root / 'utils' / 'plan' / 'Cronograma_e_Tarefas.csv'
with open(csv_path, 'r', encoding='utf-8') as f:
    for row in csv.DictReader(f):
        if row.get('Status') == 'Em andamento':
            print(row.get('ID da Tarefa'))
            sys.exit(0)
" 2>/dev/null || true)
    if [ -n "$IN_PROGRESS" ]; then
        TASK_ID="$IN_PROGRESS"
        echo "[INFO][post_task_sync] Detected active task: $TASK_ID"
    else
        echo "[ERROR][post_task_sync] No TASK_ID provided and no task is currently 'Em andamento'." >&2
        echo "Usage: $0 <TASK_ID> <EVIDENCE> [NOTES]" >&2
        exit 1
    fi
fi

# 2. Determine evidence if not provided
if [ -z "$EVIDENCE" ]; then
    if [ -f "out/gates/gate_${TASK_ID}.json" ] || [ -f "out/gates/${TASK_ID}.json" ]; then
        EVIDENCE="gate:${TASK_ID}"
        echo "[INFO][post_task_sync] Auto-detected gate evidence: $EVIDENCE"
    else
        echo "[ERROR][post_task_sync] Missing EVIDENCE. Please specify gate:<id> or file:<path>." >&2
        exit 1
    fi
fi

# 3. Transition task to 'Concluída' in plan
echo "[INFO][post_task_sync] Setting task $TASK_ID to 'Concluída' with evidence '$EVIDENCE'..."
if [ -n "$NOTES" ]; then
    python3 "$HOOK_DIR/plan-sync.py" set "$TASK_ID" "Concluída" --evidence "$EVIDENCE" --notes "$NOTES"
else
    python3 "$HOOK_DIR/plan-sync.py" set "$TASK_ID" "Concluída" --evidence "$EVIDENCE"
fi

# 4. Refresh technical memory digests across all modules
echo "[INFO][post_task_sync] Updating technical memory module digests..."
python3 "$HOOK_DIR/memory-check.py" --update all

# 5. Verify technical memory limits and hashes
echo "[INFO][post_task_sync] Checking technical memory integrity..."
python3 "$HOOK_DIR/memory-check.py"

# 6. Synchronize plan status markdown
echo "[INFO][post_task_sync] Synchronizing plan status and critical path..."
python3 "$HOOK_DIR/plan-sync.py" sync

# 7. Validate plan constraints
echo "[INFO][post_task_sync] Validating plan consistency..."
python3 "$HOOK_DIR/plan-sync.py" check

# 8. Report next steps
echo "[INFO][post_task_sync] Next eligible task(s):"
python3 "$HOOK_DIR/plan-sync.py" next || true

echo "[OK][post_task_sync] Task $TASK_ID successfully finalized and committed to plan."
