#!/usr/bin/env bash
# vhdl-sim-gate.sh: run the VUnit suite through the Makefile. Gate name: vhdl-sim.
# Usage: TASK_ID=2.1 vhdl-sim-gate.sh [TB-substring]
# Passes only if VUnit reports "All passed!" with at least one test discovered.
# Exit codes: 0 pass, 32 test failure, 33 no tests found, 124 timeout.
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

TASK="${TASK_ID:-adhoc}"
TB="${1:-}"
LOG="out/vhdl-sim.log"
HW="cora7z/app/hw"
mkdir -p out

record() { python3 "$HOOK_DIR/gate_record.py" "$TASK" vhdl-sim "$1" --detail "$2" --src "$HW/src" "$HW/test"; }

if ! command -v ghdl >/dev/null 2>&1; then
  record SKIPPED "tool-missing:ghdl"
  echo "[SKIPPED][vhdl-sim] ghdl not found" >&2
  exit 0
fi

timeout "${SIM_TIMEOUT:-300}" make -C "$HW" test ${TB:+TB="$TB"} > "$LOG" 2>&1
RC=$?

if [ "$RC" -eq 124 ]; then
  record FAIL "timeout"
  echo "[FAIL][vhdl-sim] Timeout" >&2
  exit 124
fi

# VUnit colors its output even when redirected: strip ANSI escapes before parsing
sed -i 's/\x1b\[[0-9;]*m//g' "$LOG"
TOTAL=$(grep -Eo 'pass [0-9]+ of [0-9]+' "$LOG" | tail -1 | awk '{print $4}')
if [ "$RC" -ne 0 ]; then
  record FAIL "make exit $RC"
  echo "[FAIL][vhdl-sim] Tests failed. Tail of $LOG:" >&2
  tail -n 30 "$LOG" >&2
  exit 32
fi
if ! grep -q 'All passed!' "$LOG"; then
  record FAIL "VUnit did not report All passed"
  echo "[FAIL][vhdl-sim] VUnit did not report 'All passed!'. Tail of $LOG:" >&2
  tail -n 30 "$LOG" >&2
  exit 32
fi
if [ -z "${TOTAL:-}" ] || [ "$TOTAL" -eq 0 ]; then
  record FAIL "no tests discovered"
  echo "[FAIL][vhdl-sim] No tests discovered (a testbench is mandatory)." >&2
  exit 33
fi

record PASS "$TOTAL tests passed"
echo "[OK][vhdl-sim] $TOTAL tests passed."
exit 0
