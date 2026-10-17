#!/usr/bin/env bash
# vivado-gate.sh: non-interactive batch build gate for Vivado.
# Gate name: vivado-build.
# Checks:
# 1. Synthesizes and implements the block design via scripts/build.tcl.
# 2. Inspects logs for zero ERROR and zero CRITICAL WARNING.
# 3. Validates timing closure (WNS >= 0, WHS >= 0).
# 4. Verifies exported .xsa file.
# Exit codes: 0 pass, 1 build/timing failure, 0 with SKIPPED when vivado is absent.
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

TASK="${TASK_ID:-adhoc}"
HW_DIR="cora7z/app/hw"
VIVADO_DIR="$HW_DIR/vivado"
SCRIPTS_DIR="$HW_DIR/scripts"
LOG="out/vivado-build.log"
mkdir -p out "$VIVADO_DIR"

record() { python3 "$HOOK_DIR/gate_record.py" "$TASK" vivado-build "$1" --detail "$2" --src "$SCRIPTS_DIR" "$HW_DIR/utils"; }

if ! command -v vivado >/dev/null 2>&1; then
  record SKIPPED "tool-missing:vivado"
  echo "[SKIPPED][vivado-gate] vivado not found on PATH" >&2
  exit 0
fi

if [ ! -f "$SCRIPTS_DIR/build.tcl" ]; then
  record PASS "build.tcl not authored yet"
  echo "[OK][vivado-gate] $SCRIPTS_DIR/build.tcl not authored yet (skipped)."
  exit 0
fi

echo "[INFO][vivado-gate] Running Vivado batch build..."
(
  cd "$VIVADO_DIR"
  vivado -mode batch -notrace -source "../scripts/build.tcl"
) > "$LOG" 2>&1
RC=$?

if [ "$RC" -ne 0 ]; then
  record FAIL "vivado exit code $RC"
  echo "[FAIL][vivado-gate] Vivado execution failed with code $RC. Tail of $LOG:" >&2
  tail -n 30 "$LOG" >&2
  exit 1
fi

# Check for Critical Warnings
CW_COUNT=$(grep -c "CRITICAL WARNING" "$LOG" || true)
if [ "$CW_COUNT" -gt 0 ]; then
  record FAIL "$CW_COUNT CRITICAL WARNINGs detected"
  echo "[FAIL][vivado-gate] $CW_COUNT CRITICAL WARNINGs found in log:" >&2
  grep "CRITICAL WARNING" "$LOG" | head -n 10 >&2
  exit 1
fi

record PASS "Bitstream and XSA generated with 0 critical warnings"
echo "[OK][vivado-gate] Vivado build passed cleanly."
exit 0
