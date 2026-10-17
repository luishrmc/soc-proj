---
name: benchmark-matrix
description: Execution, consolidation, throughput computation, and statistical validation for the 12-row test matrix across PS, PL, and Hybrid architectures.
---

# Benchmark Matrix Skill

Manages the execution of the experimental evaluation matrix defined in `utils/plan/Matriz_de_Testes_e_Métricas.csv`, populating measurement results into `cora7z/app/test_results/`.

## 1. When to Use
- Running test runs across the 3 scenarios:
  1. **PS Puro**: Pure C software on Cortex-A9.
  2. **PL Pura**: Pure VHDL pipeline with SPI receiver directly feeding accelerators.
  3. **Híbrido**: PS controls memory buffers and transfers blocks to PL accelerators via AXI.
- Recording metrics across block sizes (64 B, 1 KB, 64 KB) and data patterns (High redundancy, Pseudo-random, Telemetry).
- Generating throughput and latency comparison plots.

## 2. Metrics & Conversion Formulas

- **ARM PMU Cycles**: Integer cycles from `pmu_read_cycles()` (calibrated). Marked `N/A` for pure PL runs.
- **Latency ($T_{lat}$)**: End-to-end duration from start of block ingestion to final encrypted output byte (in milliseconds).
- **Throughput ($TH$)**:
  $$TH \text{ (MB/s)} = \frac{\text{Block Size (Bytes)}}{T_{lat} \text{ (ms)} \times 1000}$$
- **FPGA Resources**: Extracted directly from Vivado post-implementation utilization report (`report_utilization -file out/utilization.rpt`):
  Format: `LUTs: <N> | FFs: <N> | BRAMs: <N>` (Marked `N/A` for pure PS runs).

## 3. Data Integrity & Reporting
- Raw trial dumps are stored in `cora7z/app/test_results/raw/` (ignored by Git).
- Aggregated means and standard deviations are saved in `cora7z/app/test_results/summary.csv`.
- The test bench agent reports the verified values to `orchestrator-agent`, which records them into `utils/plan/Matriz_de_Testes_e_Métricas.csv`.

## 4. Negative Constraints
- Never fill a table cell with estimated, extrapolated, or mock data.
- If a hardware run fails or board is disconnected, leave the cell empty and log the failure mode.
