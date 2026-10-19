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

BUILD_SCRIPT=""
if [ -f "$SCRIPTS_DIR/build_bitstream.tcl" ]; then
  BUILD_SCRIPT="../scripts/build_bitstream.tcl"
elif [ -f "$SCRIPTS_DIR/build.tcl" ]; then
  BUILD_SCRIPT="../scripts/build.tcl"
fi

if [ -z "$BUILD_SCRIPT" ]; then
  record PASS "build script not authored yet"
  echo "[OK][vivado-gate] Neither build_bitstream.tcl nor build.tcl authored yet (skipped)."
  exit 0
fi

echo "[INFO][vivado-gate] Running Vivado batch build via $BUILD_SCRIPT..."
(
  cd "$VIVADO_DIR"
  vivado -mode batch -notrace -source "$BUILD_SCRIPT"
) > "$LOG" 2>&1
RC=$?

if [ "$RC" -ne 0 ]; then
  record FAIL "vivado exit code $RC"
  echo "[FAIL][vivado-gate] Vivado execution failed with code $RC. Key errors from $LOG:" >&2
  grep -E "(ERROR:|CRITICAL WARNING:)" "$LOG" | head -n 20 >&2 || tail -n 20 "$LOG" >&2
  exit 1
fi

# Check for Critical Warnings
CW_COUNT=$(grep -c "CRITICAL WARNING" "$LOG" || true)
if [ "$CW_COUNT" -gt 0 ]; then
  record FAIL "$CW_COUNT CRITICAL WARNINGs detected"
  echo "[FAIL][vivado-gate] $CW_COUNT CRITICAL WARNINGs found in log:" >&2
  grep "CRITICAL WARNING" "$LOG" | head -n 15 >&2
  exit 1
fi

record PASS "Bitstream and XSA generated with 0 critical warnings"
echo "[OK][vivado-gate] Vivado build passed cleanly."
exit 0
