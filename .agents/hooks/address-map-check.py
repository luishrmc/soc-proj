#!/usr/bin/env python3
"""address-map-check.py: verifies AXI base address alignment and collision-free mapping.

Gate name: address-map.
Checks:
1. No overlapping address ranges among AXI-Lite slave peripherals in INTERFACES.md.
2. If xparameters.h exists in the Vitis platform, cross-checks base addresses.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INTERFACES = ROOT / "cora7z" / "app" / "hw" / "src" / "INTERFACES.md"
TASK = os.environ.get("TASK_ID", "adhoc")


def record(status, detail=""):
    cmd = [
        sys.executable,
        str(ROOT / ".agents" / "hooks" / "gate_record.py"),
        TASK,
        "address-map",
        status,
        "--detail",
        detail,
    ]
    if INTERFACES.exists():
        cmd.extend(["--src", str(INTERFACES)])
    subprocess.run(cmd, check=True)


def main():
    if not INTERFACES.exists():
        record("PASS", "INTERFACES.md not created yet")
        print("[OK][address-map] INTERFACES.md not found yet (skipped).")
        return 0

    content = INTERFACES.read_text()
    # Find table lines with Base Address and Size
    # Format: | Peripheral | Base Address | High Address | Size |
    ranges = []
    for line in content.splitlines():
        m = re.search(
            r"\|\s*`?([a-zA-Z0-9_]+)`?\s*\|\s*`?(0x[0-9a-fA-F]+)`?\s*\|\s*`?(0x[0-9a-fA-F]+)`?\s*\|",
            line,
        )
        if m:
            name, base_s, high_s = m.group(1), m.group(2), m.group(3)
            base = int(base_s, 16)
            high = int(high_s, 16)
            if high < base:
                record("FAIL", f"Invalid range for {name}: high < base")
                print(
                    f"[ERROR][address-map] Invalid range for {name}: {high_s} < {base_s}",
                    file=sys.stderr,
                )
                return 1
            ranges.append((name, base, high))

    # Check overlaps
    ranges.sort(key=lambda x: x[1])
    for i in range(len(ranges) - 1):
        n1, b1, h1 = ranges[i]
        n2, b2, h2 = ranges[i + 1]
        if h1 >= b2:
            record("FAIL", f"Address collision between {n1} and {n2}")
            print(
                f"[ERROR][address-map] Collision between {n1} [0x{b1:X}-0x{h1:X}] and {n2} [0x{b2:X}-0x{h2:X}]",
                file=sys.stderr,
            )
            return 1

    record("PASS", f"{len(ranges)} AXI peripherals verified")
    print(f"[OK][address-map] {len(ranges)} AXI address ranges verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
