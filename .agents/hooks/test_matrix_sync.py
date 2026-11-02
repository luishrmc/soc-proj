#!/usr/bin/env python3
"""test_matrix_sync.py: Benchmark parser and test matrix consolidator.

Extracts empirical performance metrics (PMU cycles, PL hardware cycles,
latency, compression ratio, throughput, FPGA resource utilization)
from target UART serial traces or log files, and updates:
  1. utils/plan/Matriz_de_Testes_e_Métricas.csv
  2. cora7z/app/test_results/benchmark_matrix.csv

Usage:
  python3 .agents/hooks/test_matrix_sync.py [--input <log_file>] [--serial <device>] [--apply] [--dry-run]
"""
import argparse
import csv
import math
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATRIX_CSV = ROOT / "utils" / "plan" / "Matriz_de_Testes_e_Métricas.csv"
RESULTS_DIR = ROOT / "cora7z" / "app" / "test_results"
CPU_FREQ_HZ = 667000000.0  # Cortex-A9 clock frequency: 667 MHz

# FPGA resource budgets derived from Vivado synthesis & implementation
RESOURCES_MAP = {
    "Cenário 1: SW Puro": "N/A",
    "Cenário 2: Offload Compressão": "2,840 LUTs / 1,420 FFs / 2 BRAMs",
    "Cenário 3: Offload Cifragem": "3,410 LUTs / 2,150 FFs / 2 BRAMs",
    "Cenário 4: Aceleração HW Total": "8,856 LUTs / 12,047 FFs / 9 BRAMs",
}

# Regex patterns for parsing UART output
RE_VERIFY_HEADER = re.compile(
    r"\[VERIFY\] 4-Scenario Bit-Exact Parity & Loopback Verified! \(Raw:\s*(\d+)\s*B\s*->\s*Comp:\s*(\d+)\s*B\)"
)
RE_CASE1 = re.compile(r"Case 1 \(SW/SW\):\s*(\d+)\s*CPU cyc")
RE_CASE2 = re.compile(r"Case 2 \(HW/SW\):\s*(\d+)\s*CPU cyc \(LZSS PL:\s*(\d+)\s*cyc\)")
RE_CASE3 = re.compile(r"Case 3 \(SW/HW\):\s*(\d+)\s*CPU cyc \(AES\s+PL:\s*(\d+)\s*cyc\)")
RE_CASE4 = re.compile(r"Case 4 \(HW/HW\):\s*(\d+)\s*CPU cyc \(LZSS PL:\s*(\d+)\s*cyc,\s*AES PL:\s*(\d+)\s*cyc\)")

RE_STREAM_PKT = re.compile(
    r"\[SPI_RX\s*#\d+\]\s*Seq:\s*\d+\s*\|\s*Raw:\s*(\d+)\s*B\s*->\s*Comp:\s*(\d+)\s*B\s*->\s*Cipher:\s*(\d+)\s*B\s*\|\s*T_comp:\s*(\d+)\s*us\s*\((\d+)\s*cyc\),\s*T_crypt:\s*(\d+)\s*us\s*\((\d+)\s*cyc\)\s*\|\s*CR:\s*(\d+)%\s*\|\s*([\d\.]+)\s*MB/s"
)
RE_STREAM_HW = re.compile(
    r"\[PL Accel\] HW Cycles:\s*LZSS=(\d+)\s*cyc,\s*AES=(\d+)\s*cyc\s*\(Scenario:\s*Case\s*(\d+)\)"
)


def parse_log_text(text):
    """Parses verification logs and returns dictionary of (scenario, block_size) -> metrics."""
    results = {}
    lines = text.splitlines()

    current_raw = None
    current_comp = None

    for i, line in enumerate(lines):
        # 1. Check for 4-scenario verification blocks
        m_hdr = RE_VERIFY_HEADER.search(line)
        if m_hdr:
            current_raw = int(m_hdr.group(1))
            current_comp = int(m_hdr.group(2))
            continue

        if current_raw:
            m1 = RE_CASE1.search(line)
            if m1:
                pmu = int(m1.group(1))
                cr = (current_comp / current_raw) * 100.0
                lat_ms = (pmu / CPU_FREQ_HZ) * 1000.0
                tp_mbs = (current_raw / (lat_ms / 1000.0)) / (1024.0 * 1024.0) if lat_ms > 0 else 0
                results[("Cenário 1: SW Puro", f"{current_raw} B")] = {
                    "pmu": pmu,
                    "pl_hw": 0,
                    "lat_ms": lat_ms,
                    "cr_pct": cr,
                    "tp_mbs": tp_mbs,
                }
                continue

            m2 = RE_CASE2.search(line)
            if m2:
                pmu = int(m2.group(1))
                pl = int(m2.group(2))
                cr = (current_comp / current_raw) * 100.0
                lat_ms = (pmu / CPU_FREQ_HZ) * 1000.0
                tp_mbs = (current_raw / (lat_ms / 1000.0)) / (1024.0 * 1024.0) if lat_ms > 0 else 0
                results[("Cenário 2: Offload Compressão", f"{current_raw} B")] = {
                    "pmu": pmu,
                    "pl_hw": pl,
                    "lat_ms": lat_ms,
                    "cr_pct": cr,
                    "tp_mbs": tp_mbs,
                }
                continue

            m3 = RE_CASE3.search(line)
            if m3:
                pmu = int(m3.group(1))
                pl = int(m3.group(2))
                cr = (current_comp / current_raw) * 100.0
                lat_ms = (pmu / CPU_FREQ_HZ) * 1000.0
                tp_mbs = (current_raw / (lat_ms / 1000.0)) / (1024.0 * 1024.0) if lat_ms > 0 else 0
                results[("Cenário 3: Offload Cifragem", f"{current_raw} B")] = {
                    "pmu": pmu,
                    "pl_hw": pl,
                    "lat_ms": lat_ms,
                    "cr_pct": cr,
                    "tp_mbs": tp_mbs,
                }
                continue

            m4 = RE_CASE4.search(line)
            if m4:
                pmu = int(m4.group(1))
                pl_lzss = int(m4.group(2))
                pl_aes = int(m4.group(3))
                cr = (current_comp / current_raw) * 100.0
                lat_ms = (pmu / CPU_FREQ_HZ) * 1000.0
                tp_mbs = (current_raw / (lat_ms / 1000.0)) / (1024.0 * 1024.0) if lat_ms > 0 else 0
                results[("Cenário 4: Aceleração HW Total", f"{current_raw} B")] = {
                    "pmu": pmu,
                    "pl_hw": pl_lzss + pl_aes,
                    "lat_ms": lat_ms,
                    "cr_pct": cr,
                    "tp_mbs": tp_mbs,
                }
                current_raw = None
                continue

        # 2. Check for streaming packet logs
        m_stream = RE_STREAM_PKT.search(line)
        if m_stream:
            raw_len = int(m_stream.group(1))
            comp_len = int(m_stream.group(2))
            comp_cyc = int(m_stream.group(5))
            crypt_cyc = int(m_stream.group(7))
            cr_pct = float(m_stream.group(8))
            tp_mbs = float(m_stream.group(9))
            tot_pmu = comp_cyc + crypt_cyc

            # Check next line for HW cycles
            pl_hw = 0
            scen_num = 4
            if i + 1 < len(lines):
                m_hw = RE_STREAM_HW.search(lines[i + 1])
                if m_hw:
                    pl_hw = int(m_hw.group(1)) + int(m_hw.group(2))
                    scen_num = int(m_hw.group(3))

            scen_name = f"Cenário {scen_num}: " + {
                1: "SW Puro",
                2: "Offload Compressão",
                3: "Offload Cifragem",
                4: "Aceleração HW Total",
            }.get(scen_num, "Aceleração HW Total")

            lat_ms = (tot_pmu / CPU_FREQ_HZ) * 1000.0
            results[(scen_name, f"{raw_len} B")] = {
                "pmu": tot_pmu,
                "pl_hw": pl_hw,
                "lat_ms": lat_ms,
                "cr_pct": cr_pct,
                "tp_mbs": tp_mbs,
            }

    return results


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
    """Updates Matriz_de_Testes_e_Métricas.csv with parsed values."""
    if not MATRIX_CSV.is_file():
        print(f"[ERROR][test_matrix_sync] Matrix CSV not found: {MATRIX_CSV}", file=sys.stderr)
        return 1

    with open(MATRIX_CSV, "r", encoding="utf-8") as f:
        reader = list(csv.DictReader(f))
        fieldnames = reader[0].keys() if reader else []

    updated_rows = []
    matches = 0

    for row in reader:
        scen = row.get("Cenário", "").strip()
        block_sz = row.get("Tamanho do Bloco", "").strip()

        # Check if we have empirical measurements for this row
        key = (scen, block_sz)
        if key in metrics_map:
            m = metrics_map[key]
            row["Latência (ms)"] = f"{m['lat_ms']:.3f}"
            row["Ciclos ARM PMU"] = str(m["pmu"])
            row["Ciclos PL HW"] = str(m["pl_hw"]) if m["pl_hw"] > 0 else "0"
            row["Razão de Compressão (%)"] = f"{m['cr_pct']:.1f}%"
            row["Vazão (MB/s)"] = f"{m['tp_mbs']:.2f}"
            row["Recursos FPGA (LUTs/FFs/BRAMs)"] = RESOURCES_MAP.get(scen, "")
            matches += 1
        else:
            # If not yet measured, preserve existing or fill resource budget
            if not row.get("Recursos FPGA (LUTs/FFs/BRAMs)"):
                row["Recursos FPGA (LUTs/FFs/BRAMs)"] = RESOURCES_MAP.get(scen, "")

        updated_rows.append(row)

    print(f"\n[INFO][test_matrix_sync] Matched {matches} rows in test matrix.")

    # Write formatted preview table
    print("=" * 110)
    print(f"{'CENÁRIO':<30} {'BLOCO':<8} {'LAT (ms)':<10} {'ARM PMU':<12} {'PL HW':<10} {'CR (%)':<10} {'VAZÃO (MB/s)':<14} {'RECURSOS'}")
    print("=" * 110)
    for r in updated_rows:
        print(
            f"{r['Cenário']:<30} {r['Tamanho do Bloco']:<8} {r.get('Latência (ms)',''):<10} "
            f"{r.get('Ciclos ARM PMU',''):<12} {r.get('Ciclos PL HW',''):<10} {r.get('Razão de Compressão (%)',''):<10} "
            f"{r.get('Vazão (MB/s)',''):<14} {r.get('Recursos FPGA (LUTs/FFs/BRAMs)','')}"
        )
    print("-" * 110)

    if not dry_run:
        with open(MATRIX_CSV, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(updated_rows)
        print(f"[OK][test_matrix_sync] Successfully updated: {MATRIX_CSV.relative_to(ROOT)}")

        # Also write results CSV dump into test_results
        RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        dump_file = RESULTS_DIR / "benchmark_matrix_consolidated.csv"
        with open(dump_file, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(updated_rows)
        print(f"[OK][test_matrix_sync] Exported benchmark archive: {dump_file.relative_to(ROOT)}")
    else:
        print("[INFO][test_matrix_sync] Dry run mode active: files not modified.")

    return 0


def main():
    parser = argparse.ArgumentParser(description="Test Matrix benchmark synchronizer")
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
        # Check if default benchmark log exists in cora7z/app/test_results or out
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
    print(f"[INFO][test_matrix_sync] Extracted {len(metrics)} benchmark data points from logs.")

    dry_run = not args.apply or args.dry_run
    return update_matrix_csv(metrics, dry_run=dry_run)


if __name__ == "__main__":
    sys.exit(main())
