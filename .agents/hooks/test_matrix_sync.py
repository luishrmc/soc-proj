#!/usr/bin/env python3
"""test_matrix_sync.py: ADR-020 benchmark parser and test matrix consolidator.

Extracts empirical performance metrics (PMU cycles, PL hardware cycles,
latency, Space Savings % compression ratio, throughput, FPGA utilization)
from target UART serial traces or log files across the 12 ADR-020 cells:
  4 Scenarios x 3 Entropy Profiles (Quiescent, Dynamic, Chaotic) @ 1024 B.

Updates:
  1. utils/plan/Matriz_de_Testes_e_Métricas.csv
  2. cora7z/app/test_results/benchmark_matrix_consolidated.csv

Usage:
  python3 .agents/hooks/test_matrix_sync.py [--input <log_file>] [--serial <device>] [--apply] [--dry-run]
"""
import argparse
from collections import defaultdict
import csv
import math
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATRIX_CSV = ROOT / "utils" / "plan" / "Matriz_de_Testes_e_Métricas.csv"
RESULTS_DIR = ROOT / "cora7z" / "app" / "test_results"
CPU_FREQ_HZ = 650000000.0  # Cortex-A9 APU clock frequency per ps7_init/xparameters.h: 650 MHz

# FPGA resource budgets derived from Vivado post-implementation utilization.rpt
RESOURCES_MAP = {
    "Cenário 1: SW Puro": "N/A",
    "Cenário 2: Offload Compressão": "Pending",
    "Cenário 3: Offload Cifragem": "Pending",
    "Cenário 4: Aceleração HW Total": "8810 LUTs / 12048 FFs / 9 BRAMs",
}

VALID_PROFILES = {"Quiescent", "Dynamic", "Chaotic"}

# Regex patterns for ADR-020 startup sweep logs
RE_VERIFY_HEADER = re.compile(
    r"\[VERIFY\] 4-Scenario Bit-Exact Parity & Loopback Verified!\s*"
    r"\(Profile:\s*(\w+)\s*\|\s*Raw:\s*(\d+)\s*B\s*\|\s*SW Comp:\s*(\d+)\s*B\s*\|\s*HW Comp:\s*(\d+)\s*B\)"
)
RE_CASE1 = re.compile(r"Case 1 \(SW/SW\):\s*(\d+)\s*CPU cyc")
RE_CASE2 = re.compile(r"Case 2 \(HW/SW\):\s*(\d+)\s*CPU cyc \(LZSS PL:\s*(\d+)\s*cyc\)")
RE_CASE3 = re.compile(r"Case 3 \(SW/HW\):\s*(\d+)\s*CPU cyc \(AES\s+PL:\s*(\d+)\s*cyc\)")
RE_CASE4 = re.compile(r"Case 4 \(HW/HW\):\s*(\d+)\s*CPU cyc \(LZSS PL:\s*(\d+)\s*cyc,\s*AES PL:\s*(\d+)\s*cyc\)")

# Regex pattern for live SPI HIL compact single-line telemetry trace
RE_HIL_BENCH = re.compile(
    r"\[HIL_BENCH\]\s*Seq:(\d+)\s+Prof:(\w+)\s+Raw:(\d+)B\s*\|\s*"
    r"C1:(\d+)/0cyc\((\d+)B\)\s+"
    r"C2:(\d+)/(\d+)cyc\((\d+)B\)\s+"
    r"C3:(\d+)/(\d+)cyc\((\d+)B\)\s+"
    r"C4:(\d+)/(\d+)\+(\d+)cyc\((\d+)B\)"
)


def _calc_metrics(raw_len: int, comp_len: int, pmu: int, pl_hw: int) -> dict:
    """Compute canonical ADR-020 latency, throughput, and Space Savings % CR."""
    lat_ms = (pmu / CPU_FREQ_HZ) * 1000.0
    tp_mbs = (raw_len / (lat_ms / 1000.0)) / (1024.0 * 1024.0) if lat_ms > 0.0 else 0.0
    cr_pct = (1.0 - (float(comp_len) / float(raw_len))) * 100.0 if raw_len > 0 else 0.0
    return {
        "pmu": float(pmu),
        "pl_hw": float(pl_hw),
        "lat_ms": lat_ms,
        "cr_pct": cr_pct,
        "tp_mbs": tp_mbs,
    }


def _aggregate_samples(samples_by_key: dict) -> dict:
    """Average collected samples per (scenario, profile) cell with sample count/std."""
    aggregated = {}
    for key, samples in samples_by_key.items():
        n = len(samples)
        if n == 0:
            continue
        mean_pmu = sum(s["pmu"] for s in samples) / n
        mean_pl = sum(s["pl_hw"] for s in samples) / n
        mean_lat = sum(s["lat_ms"] for s in samples) / n
        mean_cr = sum(s["cr_pct"] for s in samples) / n
        mean_tp = sum(s["tp_mbs"] for s in samples) / n
        std_pmu = (
            math.sqrt(sum((s["pmu"] - mean_pmu) ** 2 for s in samples) / (n - 1))
            if n > 1
            else 0.0
        )
        aggregated[key] = {
            "n": n,
            "pmu": int(round(mean_pmu)),
            "pmu_std": std_pmu,
            "pl_hw": int(round(mean_pl)),
            "lat_ms": mean_lat,
            "cr_pct": mean_cr,
            "tp_mbs": mean_tp,
        }
    return aggregated


def parse_log_text(text: str, include_verify: bool = False) -> dict:
    """Parse live [HIL_BENCH] and fallback [VERIFY] traces keyed by (scenario, profile).

    By default, when [HIL_BENCH] traces are present, cold-cache startup [VERIFY]
    traces are excluded so matrix statistics represent pure live SPI HIL bursts.
    """
    hil_samples = defaultdict(list)
    verify_samples = defaultdict(list)
    lines = text.splitlines()

    cur_profile = None
    cur_raw = 0
    cur_sw_comp = 0
    cur_hw_comp = 0

    for line in lines:
        m_hil = RE_HIL_BENCH.search(line)
        if m_hil:
            prof = m_hil.group(2)
            raw_len = int(m_hil.group(3))
            if prof in VALID_PROFILES and raw_len == 1024:
                c1_pmu, c1_comp = int(m_hil.group(4)), int(m_hil.group(5))
                c2_pmu, c2_pl, c2_comp = int(m_hil.group(6)), int(m_hil.group(7)), int(m_hil.group(8))
                c3_pmu, c3_pl, c3_comp = int(m_hil.group(9)), int(m_hil.group(10)), int(m_hil.group(11))
                c4_pmu, c4_lz, c4_ae, c4_comp = (
                    int(m_hil.group(12)),
                    int(m_hil.group(13)),
                    int(m_hil.group(14)),
                    int(m_hil.group(15)),
                )
                hil_samples[("Cenário 1: SW Puro", prof)].append(_calc_metrics(raw_len, c1_comp, c1_pmu, 0))
                hil_samples[("Cenário 2: Offload Compressão", prof)].append(_calc_metrics(raw_len, c2_comp, c2_pmu, c2_pl))
                hil_samples[("Cenário 3: Offload Cifragem", prof)].append(_calc_metrics(raw_len, c3_comp, c3_pmu, c3_pl))
                hil_samples[("Cenário 4: Aceleração HW Total", prof)].append(_calc_metrics(raw_len, c4_comp, c4_pmu, c4_lz + c4_ae))
            continue

        m_hdr = RE_VERIFY_HEADER.search(line)
        if m_hdr:
            prof = m_hdr.group(1)
            raw_len = int(m_hdr.group(2))
            if prof in VALID_PROFILES and raw_len == 1024:
                cur_profile = prof
                cur_raw = raw_len
                cur_sw_comp = int(m_hdr.group(3))
                cur_hw_comp = int(m_hdr.group(4))
            else:
                cur_profile = None
            continue

        if cur_profile:
            m1 = RE_CASE1.search(line)
            if m1:
                verify_samples[("Cenário 1: SW Puro", cur_profile)].append(
                    _calc_metrics(cur_raw, cur_sw_comp, int(m1.group(1)), 0)
                )
                continue

            m2 = RE_CASE2.search(line)
            if m2:
                verify_samples[("Cenário 2: Offload Compressão", cur_profile)].append(
                    _calc_metrics(cur_raw, cur_hw_comp, int(m2.group(1)), int(m2.group(2)))
                )
                continue

            m3 = RE_CASE3.search(line)
            if m3:
                verify_samples[("Cenário 3: Offload Cifragem", cur_profile)].append(
                    _calc_metrics(cur_raw, cur_sw_comp, int(m3.group(1)), int(m3.group(2)))
                )
                continue

            m4 = RE_CASE4.search(line)
            if m4:
                pl_tot = int(m4.group(2)) + int(m4.group(3))
                verify_samples[("Cenário 4: Aceleração HW Total", cur_profile)].append(
                    _calc_metrics(cur_raw, cur_hw_comp, int(m4.group(1)), pl_tot)
                )
                cur_profile = None
                continue

    if hil_samples and not include_verify:
        return _aggregate_samples(hil_samples)

    combined = defaultdict(list)
    for k, vals in hil_samples.items():
        combined[k].extend(vals)
    for k, vals in verify_samples.items():
        combined[k].extend(vals)
    return _aggregate_samples(combined)


def capture_serial(device="/dev/ttyUSB1", baud=115200, timeout_sec=10):
    """Captures serial output from connected Cora Z7."""
    try:
        import serial
    except ImportError:
        print("[ERROR][test_matrix_sync] 'pyserial' not installed. Run via system python: /usr/bin/python3", file=sys.stderr)
        return ""

    print(f"[INFO][test_matrix_sync] Connecting to serial port {device} @ {baud} baud (timeout {timeout_sec}s)...")
    try:
        ser = serial.Serial(device, baud, timeout=1.0)
    except Exception as e:
        print(f"[ERROR][test_matrix_sync] Failed to open {device}: {e}", file=sys.stderr)
        return ""

    buffer = []
    start_time = time.time()
    while time.time() - start_time < timeout_sec:
        line = ser.readline().decode("utf-8", errors="replace")
        if line:
            buffer.append(line)
            sys.stdout.write(line)
    ser.close()
    return "".join(buffer)


def update_matrix_csv(metrics_map, dry_run=False):
    """Updates Matriz_de_Testes_e_Métricas.csv and consolidated dump with parsed values."""
    if not MATRIX_CSV.is_file():
        print(f"[ERROR][test_matrix_sync] Matrix CSV not found: {MATRIX_CSV}", file=sys.stderr)
        return 1

    with open(MATRIX_CSV, "r", encoding="utf-8") as f:
        reader = list(csv.DictReader(f))
        fieldnames = list(reader[0].keys()) if reader else []

    updated_rows = []
    consolidated_rows = []
    matches = 0

    for row in reader:
        scen = row.get("Cenário", "").strip()
        profile = row.get("Perfil de Dados", "").strip()

        key = (scen, profile)
        cons_row = dict(row)
        if key in metrics_map:
            m = metrics_map[key]
            row["Latência (ms)"] = f"{m['lat_ms']:.3f}"
            row["Ciclos ARM PMU"] = str(m["pmu"])
            row["Ciclos PL HW"] = str(m["pl_hw"]) if m["pl_hw"] > 0 else "0"
            row["Razão de Compressão (%)"] = f"{m['cr_pct']:.1f}%"
            row["Vazão (MB/s)"] = f"{m['tp_mbs']:.2f}"
            row["Recursos FPGA (LUTs/FFs/BRAMs)"] = RESOURCES_MAP.get(scen, "Pending")

            cons_row = dict(row)
            cons_row["Amostras (N)"] = str(m["n"])
            cons_row["Desvio Padrão PMU (ciclos)"] = f"{m['pmu_std']:.1f}"
            matches += 1
        else:
            if not row.get("Recursos FPGA (LUTs/FFs/BRAMs)"):
                row["Recursos FPGA (LUTs/FFs/BRAMs)"] = RESOURCES_MAP.get(scen, "Pending")
            cons_row = dict(row)
            cons_row["Amostras (N)"] = "0"
            cons_row["Desvio Padrão PMU (ciclos)"] = "0.0"

        updated_rows.append(row)
        consolidated_rows.append(cons_row)

    print(f"\n[INFO][test_matrix_sync] Matched {matches} / {len(updated_rows)} ADR-020 rows.")

    print("=" * 136)
    print(f"{'CENÁRIO':<31} {'PERFIL':<11} {'N':<4} {'LAT (ms)':<9} {'ARM PMU (MEAN +/- STD)':<24} {'PL HW':<9} {'CR (%)':<9} {'VAZÃO':<8} {'RECURSOS'}")
    print("=" * 136)
    for r in consolidated_rows:
        pmu_str = f"{r.get('Ciclos ARM PMU','')} +/- {r.get('Desvio Padrão PMU (ciclos)','0')}"
        print(
            f"{r['Cenário']:<31} {r.get('Perfil de Dados',''):<11} {r.get('Amostras (N)','0'):<4} "
            f"{r.get('Latência (ms)',''):<9} {pmu_str:<24} "
            f"{r.get('Ciclos PL HW',''):<9} {r.get('Razão de Compressão (%)',''):<9} "
            f"{r.get('Vazão (MB/s)',''):<8} {r.get('Recursos FPGA (LUTs/FFs/BRAMs)','')}"
        )
    print("-" * 136)

    if not dry_run:
        with open(MATRIX_CSV, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(updated_rows)
        print(f"[OK][test_matrix_sync] Successfully updated: {MATRIX_CSV.relative_to(ROOT)}")

        RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        dump_file = RESULTS_DIR / "benchmark_matrix_consolidated.csv"
        cons_fields = list(fieldnames) + ["Amostras (N)", "Desvio Padrão PMU (ciclos)"]
        with open(dump_file, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=cons_fields)
            writer.writeheader()
            writer.writerows(consolidated_rows)
        print(f"[OK][test_matrix_sync] Exported benchmark archive: {dump_file.relative_to(ROOT)}")
    else:
        print("[INFO][test_matrix_sync] Dry run mode active: files not modified.")

    return 0


def main():
    parser = argparse.ArgumentParser(description="ADR-020 Test Matrix benchmark synchronizer")
    parser.add_argument("--input", "-i", metavar="LOG_FILE", help="Input UART serial log or test trace file")
    parser.add_argument("--serial", "-s", metavar="DEV", help="Read directly from serial port (e.g. /dev/ttyUSB1)")
    parser.add_argument("--apply", action="store_true", help="Apply updates to Matriz_de_Testes_e_Métricas.csv")
    parser.add_argument("--dry-run", action="store_true", help="Preview matrix updates without modifying files")

    args = parser.parse_args()

    log_content = ""
    if args.serial:
        log_content = capture_serial(args.serial)
    elif args.input:
        in_path = Path(args.input)
        if in_path.is_file():
            log_content = in_path.read_text(encoding="utf-8", errors="replace")
        elif args.input == "-":
            log_content = sys.stdin.read()
        else:
            print(f"[ERROR] Input file not found: {args.input}", file=sys.stderr)
            return 1
    else:
        candidates = [
            RESULTS_DIR / "latest_uart.log",
            ROOT / "out" / "latest_uart.log",
            ROOT / "out" / "firmware_uart.log",
        ]
        for c in candidates:
            if c.is_file():
                print(f"[INFO][test_matrix_sync] Auto-detected log trace: {c.relative_to(ROOT)}")
                log_content = c.read_text(encoding="utf-8", errors="replace")
                break

    metrics = parse_log_text(log_content) if log_content else {}
    print(f"[INFO][test_matrix_sync] Extracted {len(metrics)} ADR-020 matrix cells from logs.")

    dry_run = not args.apply or args.dry_run
    return update_matrix_csv(metrics, dry_run=dry_run)


if __name__ == "__main__":
    sys.exit(main())
