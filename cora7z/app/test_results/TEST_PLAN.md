# Comprehensive Experimental Test Plan: Compression & Encryption on Zynq-7010 (Digilent Cora Z7-10)

This document establishes the experimental methodology, evaluation metrics, statistical controls, and verification criteria for characterizing hardware acceleration of compression (RLE, LZ4) and encryption (AES-CTR, ChaCha20) across three computing paradigms on the Xilinx Zynq-7010 SoC.

---

## 1. Executive Summary & Architectural Pipeline

The system ingests sensor telemetry streamed from an external ESP32 microcontroller over a high-speed SPI bus (up to 25 MHz) and evaluates the end-to-end transformation pipeline:

```
[ ESP32 SPI Master ] 
         │ (25 MHz SPI Bus: SCLK, MOSI, MISO, CS_n)
         ▼
[ Ingestion & Buffering ] ──> [ Lossless Compression ] ──> [ Stream Encryption ] ──> [ Output / Dispatch ]
  (SPI Slave Receiver)            (RLE or LZ4)               (AES-CTR or ChaCha20)       (Buffered Ciphertext)
```

The transformation pipeline adheres strictly to the **Compress-then-Encrypt** methodology, which is evaluated across three distinct architectures:
1. **Scenario 1: PS Pure (Software Baseline)**: ARM Cortex-A9 @ 667 MHz, bare-metal C11 execution.
2. **Scenario 2: PL Pure (Hardware Pipeline)**: Autonomous VHDL-2008 dataflow pipeline in Artix-7 fabric.
3. **Scenario 3: Hybrid Co-Design (PS Control + PL Acceleration)**: Cortex-A9 managing DMA descriptors/buffers with PL hardware accelerators connected over AXI4.

---

## 2. Experimental Dimensions & Test Matrix

The evaluation covers the complete parameter space defined in `utils/plan/Matriz_de_Testes_e_Métricas.csv`:

### 2.1 Benchmark Dimensions

| Parameter | Options / Levels |
|---|---|
| **Architecture** | 1. PS Pure (ARM Cortex-A9) <br> 2. PL Pure (Artix-7 FPGA) <br> 3. Hybrid Co-Design (AXI4-Lite + DMA) |
| **Compression Algorithm** | 1. Run-Length Encoding (RLE) <br> 2. Windowed LZ4 / LZSS |
| **Encryption Algorithm** | 1. AES-128 in Counter Mode (AES-CTR) <br> 2. ChaCha20 Stream Cipher (20 rounds, RFC 8439) |
| **Block Size** | 1. Small: 64 Bytes <br> 2. Medium: 1 Kilobyte <br> 3. Large: 64 Kilobytes |
| **Data Entropy Profile** | 1. **High Redundancy**: Repeated sequential byte runs (Best-case compression) <br> 2. **Pseudo-Random**: PRNG output with uniform distribution (Worst-case compression) <br> 3. **Structured Telemetry**: Time-series sensor records with gradual variations |

---

## 3. Quantitative Evaluation Metrics

```
+─────────────────────────────────────────────────────────────────────────────────────────+
|                                    METRICS TAXONOMY                                     |
+─────────────────────────────────────────────────────────────────────────────────────────+
| 1. TIMING & LATENCY     │ Execution Latency (t_lat), ARM PMU Cycles, Hardware Cycles    |
| 2. THROUGHPUT & SPEEDUP │ Raw Processing Rate (MB/s), Speedup relative to Software (S)  |
| 3. HARDWARE RESOURCES   │ Slice LUTs, Flip-Flops, Block RAMs (36Kb), DSP48E1 Slices     |
| 4. SYSTEM EFFICIENCY    │ Cycles/Byte (CPB), Throughput/LUT, Compression Ratio (CR)     |
| 5. BREAK-EVEN ANALYSIS  │ DMA Transfer Overhead vs. Acceleration Threshold (Crossover)  |
+─────────────────────────────────────────────────────────────────────────────────────────+
```

### 3.1 Timing & Latency Metrics

* **End-to-End Latency ($T_{\text{lat}}$)**:
  Total elapsed time in milliseconds (ms) from the arrival of the first SPI byte until the final ciphertext byte is buffered.
* **ARM Cortex-A9 Cycle Count ($C_{\text{PMU}}$)**:
  Measured using the ARM Performance Monitoring Unit (PMCCNTR / CP15 register):
  $$C_{\text{actual}} = C_{\text{raw}} - C_{\text{overhead}}$$
  *(Marked `N/A` for pure PL runs).*
* **Hardware Execution Cycles ($C_{\text{PL}}$)**:
  Measured via dedicated 32-bit hardware cycle counters clocked at $F_{\text{PL}}$ (50 MHz / 100 MHz) inside the FPGA logic:
  $$T_{\text{PL\_compute}} = \frac{C_{\text{PL}}}{F_{\text{PL}}}$$

### 3.2 Throughput & Acceleration Metrics

* **Effective Throughput ($TH$)**:
  $$\text{Throughput (MB/s)} = \frac{\text{Payload Size (Bytes)}}{T_{\text{lat}} \text{ (ms)} \times 1000}$$
* **Speedup Factor ($S$)**:
  $$S_{\text{PL}} = \frac{T_{\text{lat, PS}}}{T_{\text{lat, PL}}}, \quad S_{\text{Hybrid}} = \frac{T_{\text{lat, PS}}}{T_{\text{lat, Hybrid}}}$$

### 3.3 Hardware Resource Utilization (Artix-7 XC7Z010)

Extracted from post-implementation Vivado utilization reports (`report_utilization -file out/utilization.rpt`):
* **Slice LUTs**: Total logic cells consumed and percentage of Cora Z7-10 budget ($N_{\text{LUT}} / 17{,}600 \times 100\%$).
* **Registers (Flip-Flops)**: Total flip-flops ($N_{\text{FF}} / 35{,}200 \times 100\%$).
* **Block RAMs**: 36 Kb BRAM tiles ($N_{\text{BRAM}} / 60 \times 100\%$).
* **DSP Slices**: Multipliers ($N_{\text{DSP}} / 80 \times 100\%$).
* **Timing Closure**: Worst Negative Slack ($\text{WNS} \ge 0.000\text{ ns}$) and Maximum Operating Frequency ($F_{\text{max}}$).

### 3.4 Efficiency & Performance Ratios

* **Cycles Per Byte ($\text{CPB}$)**:
  $$\text{CPB} = \frac{C_{\text{PMU}}}{\text{Payload Size (Bytes)}}$$
* **Area Efficiency ($\eta_{\text{area}}$)**:
  $$\eta_{\text{area}} = \frac{\text{Throughput (MB/s)}}{N_{\text{LUT}}}$$
* **Compression Ratio ($CR$) & Space Saving ($SS$)**:
  $$CR = \frac{\text{Compressed Size (Bytes)}}{\text{Original Size (Bytes)}}, \quad SS (\%) = (1 - CR) \times 100\%$$
* **Hybrid Break-Even / Crossover Point ($B_{\text{cross}}$)**:
  Minimum block size where the computation speedup overcomes the AXI DMA setup and transfer overhead:
  $$T_{\text{DMA\_overhead}} + T_{\text{PL\_compute}} < T_{\text{PS\_compute}}$$

---

## 4. Measurement Protocol & Statistical Rigor

```
+─────────────────────────────────────────────────────────────────────────────+
|                             EXECUTION PIPELINE                              |
+─────────────────────────────────────────────────────────────────────────────+
| 1. HARNESS CALIBRATION │ Calibrate CP15 PMCCNTR back-to-back read cost      |
| 2. CACHE WARM-UP       │ Discard trial 0 to eliminate cold-cache bias       |
| 3. REPETITION          │ Run N >= 10 independent trials per matrix cell     |
| 4. STATISTICAL FILTER  │ Compute mean (mu) & std dev (sigma); check CV <= 5%|
| 5. GOLDEN VERIFICATION │ Assert output equality with RFC 8439 / NIST vectors|
+─────────────────────────────────────────────────────────────────────────────+
```

1. **Harness Overhead Calibration**:
   The measurement framework runs 100 consecutive reads of `pmu_read_cycles()` in a tight loop to isolate measurement harness latency ($C_{\text{overhead}}$), subtracting it from all recorded samples.
2. **Cache Conditioning**:
   For Scenarios 1 and 3, an unmeasured warm-up cycle is executed immediately prior to official data collection to eliminate cold-cache instruction and data miss anomalies.
3. **Statistical Sample Size ($N \ge 10$)**:
   Each test combination is executed for a minimum of 10 independent runs. The framework computes:
   $$\mu = \frac{1}{N} \sum_{i=1}^N x_i, \quad \sigma = \sqrt{\frac{1}{N-1} \sum_{i=1}^N (x_i - \mu)^2}$$
   If the Coefficient of Variation ($CV = \sigma / \mu$) exceeds $5\%$, the trial is flagged for bus contention or interrupt jitter investigation.
4. **Functional Correctness Validation**:
   Outputs must match canonical golden test vectors before metrics are accepted:
   * **AES-CTR**: NIST Special Publication 800-38A.
   * **ChaCha20**: RFC 8439 Section 2.4.2.
   * Functional failure immediately invalidates benchmark readings and triggers a gate rejection.

---

## 5. Artifacts and Reporting Flow

* **Raw Trial Dumps**: `cora7z/app/test_results/raw/*.csv` (timestamped per run, Git-ignored).
* **Consolidated Benchmark Summary**: `cora7z/app/test_results/benchmark_summary.csv` (versioned).
* **Course Deliverable Matrix**: Populated into `utils/plan/Matriz_de_Testes_e_Métricas.csv` under the authority of `orchestrator-agent`.
