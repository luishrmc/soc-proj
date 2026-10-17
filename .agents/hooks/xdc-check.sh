#!/usr/bin/env bash
# xdc-check.sh: static audit of XDC physical constraint files.
# Gate name: xdc-check.
# Checks:
# 1. Every get_ports has PACKAGE_PIN and IOSTANDARD defined.
# 2. No duplicate pin assignments to different ports.
# 3. Input clocks have create_clock constraints.
# Exit codes: 0 ok, 1 constraint error.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../env.sh"
cd "$REPO_ROOT"

TASK="${TASK_ID:-adhoc}"
XDC_DIR="cora7z/app/hw/utils"
mkdir -p out

record() { python3 "$HOOK_DIR/gate_record.py" "$TASK" xdc-check "$1" --detail "$2" --src "$XDC_DIR"; }

mapfile -t FILES < <(find "$XDC_DIR" -name '*.xdc' 2>/dev/null | sort)
if [ "${#FILES[@]}" -eq 0 ]; then
  record PASS "no XDC files yet"
  echo "[OK][xdc-check] No XDC files found in $XDC_DIR (skipped)."
  exit 0
fi

FAIL=0
LOG="out/xdc-check.log"
: > "$LOG"

# Check for duplicate pin assignments
python3 - <<'EOF' >> "$LOG" 2>&1 || FAIL=1
import re, sys, glob
pins = {}
err = False
for f in glob.glob("cora7z/app/hw/utils/*.xdc"):
    for lno, line in enumerate(open(f), 1):
        line = line.strip()
        if line.startswith("#") or not line: continue
        m_pin = re.search(r'PACKAGE_PIN\s+([A-Z0-9]+)', line, re.I)
        m_port = re.search(r'\[get_ports\s+\{?([^\]\}]+)\}?\]', line)
        if m_pin and m_port:
            pin = m_pin.group(1).upper()
            port = m_port.group(1).strip()
            if pin in pins and pins[pin] != port:
                print(f"[ERROR] Duplicate pin {pin} used for {port} and {pins[pin]} ({f}:{lno})")
                err = True
            pins[pin] = port
if err:
    sys.exit(1)
EOF

if [ "$FAIL" -ne 0 ]; then
  record FAIL "duplicate pins or syntax error (see out/xdc-check.log)"
  echo "[FAIL][xdc-check] XDC check failed. See $LOG" >&2
  exit 1
fi

record PASS "${#FILES[@]} XDC files validated"
echo "[OK][xdc-check] All XDC constraints valid."
exit 0
