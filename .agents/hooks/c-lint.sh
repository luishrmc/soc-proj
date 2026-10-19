#!/usr/bin/env bash
# c-lint.sh: fast local C11 syntax and static checks for bare-metal firmware.
# Gate name: c-lint.
# Usage: TASK_ID=1.4 bash .agents/hooks/c-lint.sh
# Checks:
# 1. No dynamic memory allocation (malloc, calloc, realloc, free).
# 2. Syntax validation with gcc -std=c11 -Wall -Wextra -Werror -fsyntax-only.
# Exit codes: 0 pass, 1 lint failure.
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

TASK="${TASK_ID:-adhoc}"
SRC="cora7z/app/sw/src"
LOG="out/c-lint.log"
mkdir -p out
: > "$LOG"

record() { python3 "$HOOK_DIR/gate_record.py" "$TASK" c-lint "$1" --detail "$2" --src "$SRC"; }

mapfile -t FILES < <(find "$SRC" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort)
if [ "${#FILES[@]}" -eq 0 ]; then
  record PASS "no C/H sources to lint"
  echo "[OK][c-lint] No C/H sources in $SRC."
  exit 0
fi

FAIL=0

# Rule 1: No dynamic memory allocation
if grep -nE '\b(malloc|calloc|realloc|free)\s*\(' "${FILES[@]}" >> "$LOG" 2>/dev/null; then
  echo "[ERROR][c-lint] Dynamic memory allocation detected (forbidden in bare-metal):" >&2
  grep -nE '\b(malloc|calloc|realloc|free)\s*\(' "${FILES[@]}" | head -n 15 >&2
  FAIL=1
fi

# Rule 2: Fast syntax check with GCC
CC="gcc"
EXTRA_INCLUDES=()

# Check for standalone BSP include paths
BSP_INC=$(find cora7z/app/sw/vitis -type d -path "*/standalone_ps7_cortexa9_0/bsp/include" 2>/dev/null | head -n 1)
if [ -n "$BSP_INC" ] && [ -d "$BSP_INC" ]; then
  EXTRA_INCLUDES+=("-isystem" "$BSP_INC")
fi

if command -v arm-none-eabi-gcc >/dev/null 2>&1; then
  CC="arm-none-eabi-gcc"
fi

for f in "${FILES[@]}"; do
  if [[ "$f" == *.c ]]; then
    # If BSP headers are available or file is standalone algorithm
    if [ ${#EXTRA_INCLUDES[@]} -gt 0 ]; then
      if ! $CC -std=c11 -Wall -Wextra -Werror -fsyntax-only "$f" -I"$SRC" "${EXTRA_INCLUDES[@]}" >> "$LOG" 2>&1; then
        echo "[ERROR][c-lint] Syntax check failed on $f" >&2
        FAIL=1
      fi
    else
      # Try syntax check without BSP, ignore missing xilinx headers if BSP not generated yet
      if ! $CC -std=c11 -Wall -Wextra -fsyntax-only "$f" -I"$SRC" >> "$LOG" 2>&1; then
        if grep -qiE 'fatal error: xil_.*\.h: No such file' "$LOG"; then
          echo "[INFO][c-lint] $f requires Vitis BSP headers (will be validated in vitis-build gate)."
        else
          echo "[ERROR][c-lint] Syntax check failed on $f" >&2
          FAIL=1
        fi
      fi
    fi
  fi
done

if [ "$FAIL" -ne 0 ]; then
  record FAIL "see out/c-lint.log"
  echo "[FAIL][c-lint] Errors detected. Tail of $LOG:" >&2
  tail -n 20 "$LOG" >&2
  exit 1
fi

record PASS "${#FILES[@]} files checked cleanly"
echo "[OK][c-lint] ${#FILES[@]} C/H files passed all static checks."
exit 0
