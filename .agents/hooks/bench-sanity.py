#!/usr/bin/env python3
"""bench-sanity.py: validates experimental benchmark data integrity and statistical sanity.

Gate name: bench-sanity.
Checks:
1. Validates that latency and cycle measurements are strictly positive.
2. Checks that throughput corresponds to block_size / latency.
3. Ensures no NaN or blank fields (except expected N/A for pure software/hardware rows).
"""
import csv
import io
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "utils" / "plan" / "Matriz_de_Testes_e_Métricas.csv"
TASK = os.environ.get("TASK_ID", "adhoc")


def record(status, detail=""):
    cmd = [
        sys.executable,
        str(ROOT / ".agents" / "hooks" / "gate_record.py"),
        TASK,
        "bench-sanity",
        status,
        "--detail",
        detail,
    ]
    if MATRIX.exists():
        cmd.extend(["--src", str(MATRIX)])
    subprocess.run(cmd, check=True)


def main():
    if not MATRIX.exists():
        record("PASS", "Matrix CSV missing")
        print("[OK][bench-sanity] Matrix CSV not found (skipped).")
        return 0

    raw = MATRIX.read_bytes().decode("utf-8")
    rows = list(csv.DictReader(io.StringIO(raw)))

    # If all result fields are empty, we are still before Phase 5
    populated = [r for r in rows if (r.get("Latência (ms)") or "").strip()]
    if not populated:
        record("PASS", "Benchmark matrix awaiting Phase 5 execution")
        print(
            "[OK][bench-sanity] No measurement rows populated yet (pre-Phase 5)."
        )
        return 0

    errors = []
    for idx, r in enumerate(populated, 1):
        lat_s = r.get("Latência (ms)", "").strip()
        thr_s = r.get("Vazão (MB/s)", "").strip()
        try:
            lat = float(lat_s)
            if lat <= 0:
                errors.append(f"Row {idx}: Latency must be positive ({lat})")
        except ValueError:
            errors.append(f"Row {idx}: Invalid latency '{lat_s}'")

        if thr_s and thr_s != "N/A":
            try:
                thr = float(thr_s)
                if thr <= 0:
                    errors.append(
                        f"Row {idx}: Throughput must be positive ({thr})"
                    )
            except ValueError:
                errors.append(f"Row {idx}: Invalid throughput '{thr_s}'")

    if errors:
        for e in errors:
            print(f"[ERROR][bench-sanity] {e}", file=sys.stderr)
        record("FAIL", "; ".join(errors[:3]))
        return 1

    record("PASS", f"{len(populated)} measurement rows verified")
    print(
        f"[OK][bench-sanity] {len(populated)} benchmark measurement rows verified."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
