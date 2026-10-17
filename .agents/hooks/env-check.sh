#!/usr/bin/env bash
# env-check.sh: verify that every tool required by the current phase is reachable.
# Usage: env-check.sh [--strict]   (strict: exit 1 when any tool is missing)
# Exit codes: 0 all present (or non-strict), 1 missing tools in strict mode.
set -uo pipefail
source "$(dirname "$0")/../env.sh"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1
MISSING=0

check() {
  local label="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[OK][env-check] $label -> $(command -v "$cmd")"
  else
    echo "[MISSING][env-check] $label ($cmd)" >&2
    MISSING=$((MISSING + 1))
  fi
}

check "GHDL" ghdl
check "Python venv" python
check "Vivado" vivado
check "Vitis" vitis
check "ARM GCC" arm-none-eabi-gcc
check "Make" make

if python -c "import vunit" 2>/dev/null; then
  echo "[OK][env-check] VUnit $(python -c 'import vunit;print(vunit.__version__)')"
else
  echo "[MISSING][env-check] VUnit (run: make -C cora7z/app/hw venv)" >&2
  MISSING=$((MISSING + 1))
fi

if [ "$MISSING" -gt 0 ] && [ "$STRICT" -eq 1 ]; then
  exit 1
fi
exit 0
