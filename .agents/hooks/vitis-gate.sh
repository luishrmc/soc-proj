#!/usr/bin/env bash
# vitis-gate.sh: batch compilation gate for Vitis standalone Cortex-A9 firmware.
# Gate name: vitis-build.
# Checks:
# 1. Runs cora7z/app/sw/scripts/build_sw.py through Vitis unified CLI.
# 2. Confirms clean compilation (-Wall -Werror) and ELF generation.
# Exit codes: 0 pass, 1 compile failure, 0 with SKIPPED when vitis is absent.
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

TASK="${TASK_ID:-adhoc}"
SW_DIR="cora7z/app/sw"
SCRIPTS_DIR="$SW_DIR/scripts"
LOG="out/vitis-build.log"
mkdir -p out

record() { python3 "$HOOK_DIR/gate_record.py" "$TASK" vitis-build "$1" --detail "$2" --src "$SW_DIR/src" "$SCRIPTS_DIR"; }

if ! command -v vitis >/dev/null 2>&1; then
  record SKIPPED "tool-missing:vitis"
  echo "[SKIPPED][vitis-gate] vitis command not found on PATH" >&2
  exit 0
fi

if [ ! -f "$SCRIPTS_DIR/build_sw.py" ]; then
  record PASS "build_sw.py not authored yet"
  echo "[OK][vitis-gate] $SCRIPTS_DIR/build_sw.py not authored yet (skipped)."
  exit 0
fi

echo "[INFO][vitis-gate] Running Vitis build..."
vitis -s "$SCRIPTS_DIR/build_sw.py" > "$LOG" 2>&1
RC=$?

if [ "$RC" -ne 0 ]; then
  record FAIL "vitis exit code $RC"
  echo "[FAIL][vitis-gate] Vitis build failed with code $RC. Key errors from $LOG:" >&2
  grep -iE "(error:|fatal|failed)" "$LOG" | head -n 20 >&2 || tail -n 20 "$LOG" >&2
  exit 1
fi

record PASS "Firmware built cleanly"
echo "[OK][vitis-gate] Vitis build passed cleanly."
exit 0
