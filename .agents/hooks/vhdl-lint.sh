#!/usr/bin/env bash
# vhdl-lint.sh: static VHDL checks. Gate name: vhdl-lint.
# Usage: TASK_ID=2.1 vhdl-lint.sh
# 1. ghdl import + make with -Wall for every entity in src/ (warnings are failures)
# 2. grep rules: std_logic_arith, 'wait for' outside tests, unintended latch hints
# Exit codes: 0 pass, 31 lint failure, 0 with SKIPPED when GHDL is missing (recorded).
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

TASK="${TASK_ID:-adhoc}"
SRC="cora7z/app/hw/src"
WORK="out/ghdl"
LOG="out/vhdl-lint.log"
rm -rf "$WORK"   # fresh library each run: stale .cf files cause false warnings
mkdir -p "$WORK" out
: > "$LOG"

record() { python3 "$HOOK_DIR/gate_record.py" "$TASK" vhdl-lint "$1" --detail "$2" --src "$SRC"; }

if ! command -v ghdl >/dev/null 2>&1; then
  record SKIPPED "tool-missing:ghdl"
  echo "[SKIPPED][vhdl-lint] ghdl not found" >&2
  exit 0
fi

mapfile -t FILES < <(find "$SRC" -name '*.vhdl' | sort)
if [ "${#FILES[@]}" -eq 0 ]; then
  record PASS "no VHDL sources"
  echo "[OK][vhdl-lint] No sources to lint."
  exit 0
fi

FAIL=0

# --- grep rules
if grep -nEi 'std_logic_(arith|unsigned|signed)' "${FILES[@]}" >> "$LOG" 2>/dev/null; then
  echo "[ERROR][vhdl-lint] Non-standard arithmetic packages used (use numeric_std)." >&2
  FAIL=1
fi
if grep -nE '^\s*wait\s+for' "${FILES[@]}" >> "$LOG" 2>/dev/null; then
  echo "[ERROR][vhdl-lint] 'wait for' is not synthesizable and is only allowed in tests." >&2
  FAIL=1
fi

# --- ghdl analysis and elaboration of each entity
# Run inside the work dir so GHDL drops its executables there (no -o on -m)
ABS_FILES=()
for f in "${FILES[@]}"; do ABS_FILES+=("$REPO_ROOT/$f"); done
(cd "$WORK" && ghdl -i --std=08 --workdir=. "${ABS_FILES[@]}") >> "$LOG" 2>&1 || FAIL=1
ENTITIES=$(grep -hEio '^\s*entity\s+[a-z0-9_]+\s+is' "${FILES[@]}" | awk '{print tolower($2)}' | sort -u)
for e in $ENTITIES; do
  if ! (cd "$WORK" && ghdl -m --std=08 -Wall --workdir=. "$e") >> "$LOG" 2>&1; then
    echo "[ERROR][vhdl-lint] ghdl failed on entity $e" >&2
    FAIL=1
  fi
done
if grep -qiE 'warning' "$LOG"; then
  echo "[ERROR][vhdl-lint] GHDL warnings present (treated as failures):" >&2
  grep -iE 'warning' "$LOG" >&2
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  record FAIL "see out/vhdl-lint.log"
  echo "[FAIL][vhdl-lint] See $LOG" >&2
  exit 31
fi

record PASS "${#FILES[@]} files, entities: $(echo $ENTITIES | tr '\n' ' ')"
echo "[OK][vhdl-lint] ${#FILES[@]} files clean."
exit 0
