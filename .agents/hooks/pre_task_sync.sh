#!/usr/bin/env bash
# pre_task_sync.sh: Lifecycle hook to audit, initialize, and synchronize task start.
# Usage: ./pre_task_sync.sh [TASK_ID]
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

TASK_ID="${1:-}"

# 1. Audit repository environment & boundary snapshot
echo "[INFO][pre_task_sync] Running pre-task audit..."
bash "$HOOK_DIR/pre-task-audit.sh"

# 2. Check memory freshness before starting
echo "[INFO][pre_task_sync] Verifying technical memory integrity..."
python3 "$HOOK_DIR/memory-check.py"

# 3. Determine target task ID if not explicitly specified
if [ -z "$TASK_ID" ]; then
    NEXT_LINE=$(python3 "$HOOK_DIR/plan-sync.py" next | head -n1 || true)
    if [ -z "$NEXT_LINE" ]; then
        echo "[WARN][pre_task_sync] No pending eligible tasks found in plan."
        exit 0
    fi
    TASK_ID=$(echo "$NEXT_LINE" | awk '{print $1}')
    echo "[INFO][pre_task_sync] Auto-selected next eligible task: $TASK_ID"
fi

# 4. Check current status in Cronograma_e_Tarefas.csv
STATUS=$(python3 -c "
import csv, sys
from pathlib import Path
root = Path('$REPO_ROOT')
csv_path = root / 'utils' / 'plan' / 'Cronograma_e_Tarefas.csv'
with open(csv_path, 'r', encoding='utf-8') as f:
    for row in csv.DictReader(f):
        if row.get('ID da Tarefa') == '$TASK_ID':
            print(row.get('Status', ''))
            sys.exit(0)
sys.exit(1)
" 2>/dev/null || echo "UNKNOWN")

echo "[INFO][pre_task_sync] Task $TASK_ID current status: '$STATUS'"

# 5. Transition to 'Em andamento' if currently 'Pendente'
if [ "$STATUS" = "Pendente" ]; then
    echo "[INFO][pre_task_sync] Transitioning task $TASK_ID to 'Em andamento'..."
    python3 "$HOOK_DIR/plan-sync.py" set "$TASK_ID" "Em andamento"
elif [ "$STATUS" = "Em andamento" ]; then
    echo "[INFO][pre_task_sync] Task $TASK_ID is already 'Em andamento'."
elif [ "$STATUS" = "Concluída" ]; then
    echo "[WARN][pre_task_sync] Task $TASK_ID is already 'Concluída'."
fi

# 6. Initialize loop guard for this task
echo "[INFO][pre_task_sync] Initializing loop guard counter for task $TASK_ID..."
python3 "$HOOK_DIR/loop-guard.py" start "$TASK_ID"

echo "[OK][pre_task_sync] Task $TASK_ID successfully synchronized and ready for execution."
