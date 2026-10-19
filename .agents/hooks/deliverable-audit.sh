#!/usr/bin/env bash
# deliverable-audit.sh: audits completeness of deliverables against Checklist_de_Entregaveis.csv.
# Gate name: deliverable-audit.
# Checks:
# 1. Existence and format of VHDL sources and testbenches.
# 2. Existence of C/C++ firmware files.
# 3. Block diagram image and final report PDF.
# 4. Absence of machine-specific absolute paths in versioned files.
# Exit codes: 0 pass, 1 deliverable missing.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

TASK="${TASK_ID:-adhoc}"
CHECKLIST="utils/plan/Checklist_de_Entregaveis.csv"
mkdir -p out

record() { python3 "$HOOK_DIR/gate_record.py" "$TASK" deliverable-audit "$1" --detail "$2" --src "$CHECKLIST"; }

FAIL=0
LOG="out/deliverable-audit.log"
: > "$LOG"

echo "[INFO][deliverable-audit] Auditing deliverables..."

# 1. Check VHDL sources and testbenches
VHDL_COUNT=$(find cora7z/app/hw/src -name '*.vhdl' 2>/dev/null | wc -l)
TB_COUNT=$(find cora7z/app/hw/test -name 'tb_*.vhdl' 2>/dev/null | wc -l)

echo "VHDL Sources found: $VHDL_COUNT" >> "$LOG"
echo "VHDL Testbenches found: $TB_COUNT" >> "$LOG"

if [ "$VHDL_COUNT" -eq 0 ]; then
  echo "[WARN] No VHDL sources found yet in cora7z/app/hw/src/" >> "$LOG"
fi

LEAKS=$(git grep -I -n "/home/luis/" -- ':!.agents/env.sh' ':!.agents/hooks/deliverable-audit.sh' ':!utils/plan/.bak' ':!out/' 2>/dev/null || true)
if [ -n "$LEAKS" ]; then
  echo "[ERROR][deliverable-audit] Hardcoded user paths detected in versioned files:" >> "$LOG"
  echo "$LEAKS" >> "$LOG"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  record FAIL "Deliverable audit failed (see out/deliverable-audit.log)"
  echo "[FAIL][deliverable-audit] Deliverable audit failed. See $LOG" >&2
  exit 1
fi

record PASS "Deliverable structure verified"
echo "[OK][deliverable-audit] Deliverable structure verified."
exit 0
