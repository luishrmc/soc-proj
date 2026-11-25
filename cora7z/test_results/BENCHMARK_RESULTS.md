# Benchmark Test Methodology, Empirical Results & Engineering Findings (ADR-020)

**Target Platform:** Digilent Cora Z7-10 (`XC7Z010-1CLG400C`: ARM Cortex-A9 PS @ `650 MHz`, Artix-7 PL @ `100 MHz`)  
**Data Injector:** ESP32-WROOM (`240 MHz`, ESP-IDF v6.1, VSPI Master Mode 0 @ `2 MHz`)  
**Dataset & Framing:** ADR-020 fixed `1024 B` Telemetry Payload (`64 × 16 B` records, `1035 B` wire frame, `--seed 42`)  
**Captured Trace:** [`latest_uart.log`](latest_uart.log) (`2 × 30/30` zero-drop bursts, `N = 20` per profile, `Seq 6840..6899`)  
**Consolidated Matrix:** [`benchmark_matrix_consolidated.csv`](benchmark_matrix_consolidated.csv) & [`Matriz_de_Testes_e_Métricas.csv`](../../../utils/plan/Matriz_de_Testes_e_Métricas.csv)

---

## 1. Executive Summary (Key Presentation Takeaways)

1. **Optimal Operating Point — Scenario 3 (Hybrid: `SW LZSS + PL AES-128-CTR`):** Offloading only AES-128-CTR to the Artix-7 PL (`668–1,679` cycles @ `100 MHz`, i.e., `6.68–16.79 us`) consistently outperforms pure-software execution across all entropy regimes, delivering **`1.24x` (`Quiescent`)**, **`1.19x` (`Dynamic`)**, and **`1.17x` (`Chaotic`)** end-to-end speedups (`14.5%–19.2%` CPU cycle reduction).
2. **Architectural Risk R9 Empirically Confirmed (`PL LZSS` vs. `PS LZSS`):** Executing sliding-window LZSS sequentially over Dual-Port BRAM at `100 MHz` (`201k–745k` PL cycles) plus `50 MHz` `M_AXI_GP0` BRAM transfer/polling overhead is **`~1.58x` slower** than Cortex-A9 L1-cached SW execution at `650 MHz` (`Scenario 2: 0.63x`, `Scenario 4: 0.69x–0.72x`).
3. **Data Entropy Strongly Governs Both Compression & Pipeline Cost:** Across identical `1024 B` payloads, LZSS produces **`+55.74%` space savings** on `Quiescent` (`453.2 B`), **`+2.54%`** on `Dynamic` (`998.0 B`), and **`-12.64%` expansion** on `Chaotic` (`1153.4 B`, bounded safely inside the `2048 B` BRAM aperture).
4. **Zero-Drop Real-Time HIL Validation:** Decoupling SPI RX ingestion (`< 50 us` ACK staging + 30-frame RAM burst buffering + `250 us` `PMOD JA1` trigger pulse) eliminated the `40%` intra-burst frame drops caused by synchronous multi-scenario profiling, achieving **`60/60` frames (`0` CRC errors, `0` frame errors, `0` length errors, `100%` bit-exact Case 1–4 parity & loopback)**.

---

## 2. Test Methodology & Experimental Setup

### 2.1 Physical Testbed & Interconnect Topology

| Signal / Rail | ESP32 Pin | Cora Z7 Pin / Header | Clock / Electrical Domain | Role |
| :--- | :--- | :--- | :--- | :--- |
| **VSPI SCLK** | `GPIO 18` | `H15` (`J7.3`) | `2 MHz` SPI Mode 0 (`3.3 V`) | Master-driven serial clock (`CPOL=0, CPHA=0`) |
| **VSPI MOSI** | `GPIO 23` | `T12` (`J7.4`) | `2 MHz` (`3.3 V`) | Telemetry frames (`1035 B`) ESP32 -> Zynq `axi_quad_spi_0` |
| **VSPI MISO** | `GPIO 19` | `W15` (`J7.1`) | `2 MHz` (`3.3 V`) | Staged `0x81` ACK packets (`15 B`) Zynq -> ESP32 |
| **VSPI CS0** | `GPIO 5` | `F16` (`J7.5`) | `2 MHz` Active-Low | Hardware chip select |
| **Burst Trigger** | `GPIO 32` | `Y18` (`PMOD JA1`) | EMIO GPIO Bank 2.0 (`3.3 V`) | `250 us` active-low pulse (`GPIO_INTR_NEGEDGE`, `50 ms` lockout) |

- **PS Domain (`XPAR_CPU_CORE_CLOCK_FREQ_HZ`):** ARM Cortex-A9 Core 0 @ **`650 MHz`**, bare-metal C11 (`-Wall -Wextra -Werror`, zero heap allocation, DDR3 `512 MB`).
- **AXI Interconnect (`FCLK_CLK0`):** `M_AXI_GP0` @ **`50 MHz`** bridging PS to `axi_quad_spi_0` (`0x41E00000`, `256 B` FIFO), `axi_bram_ctrl` Port A windows, and accelerator CSRs (`0x43C00000`, `0x43C10000`).
- **PL Accelerator Domain (`FCLK_CLK1`):** `lzss_accel_0` and `aes_accel_0` running @ **`100 MHz`**, decoupled via four `8 KB` True Dual-Port BRAMs (`bmg_*`, `2048 B` active payload capacity per aperture, ADR-012) to eliminate variable-length AXI DMA S2MM stalls.

### 2.2 Standardized ADR-020 Synthetic Workload (`seed=42`)

Each SPI burst transmits **30 sequential `TelemetryFrame`s** (`10` per Entropy Profile, `30 ms` inter-frame gap, `~35.2 ms` period):
- **Frame Format (`1035 B`):** `[0] Preamble 0xA5` | `[1] Type 0x02` | `[2..3] BE16 seq_id` | `[4..5] BE16 payload_len (1024)` | `[6..7] reserved_align (0x0000)` | `[8..1031] Payload (1024 B)` | `[1032..1033] BE16 CRC-16-CCITT (0x1021)` | `[1034] EOF 0x5A`.
- **Payload Structure:** `64 × 16 B` little-endian `TelemetryRecord`s (`timestamp_ms`, `temp_c_x100`, `vib_x/y/z`, `vcc_mv`, `status_flags`):
  1. **`Quiescent`** (`seq % 30 = 0..9`): Steady-state baseline (`±1` LSB jitter, constant flags) — tests high dictionary redundancy.
  2. **`Dynamic`** (`seq % 30 = 10..19`): Multi-frequency sinusoidal vibration + thermal ramps + voltage droop — tests moderate redundancy.
  3. **`Chaotic`** (`seq % 30 = 20..29`): Wide-range uniform transients across all sensor fields — stresses worst-case incompressible LZSS expansion.

### 2.3 Four Execution Scenarios & Verification Invariants

| Scenario | Compression Stage | Cipher Stage | Verification Requirement |
| :--- | :--- | :--- | :--- |
| **Scenario 1: SW Puro (`C1`)** | SW LZSS (`window=256, max_match=258`) | SW AES-128-CTR (`aes_ctr.c`) | NIST F.5.1 + reverse loopback (`pipeline_reverse_frame == raw_in`) |
| **Scenario 2: Offload Compressão (`C2`)** | PL `lzss_accel` (`window=256, lookahead=16`) | SW AES-128-CTR | Output valid Heatshrink stream + `C2` equals `C4` ciphertext after AES |
| **Scenario 3: Offload Cifragem (`C3`)** | SW LZSS | PL `aes_accel` (`0x43C10000`) | Bit-exact ciphertext equality with baseline (`Case 3 == Case 1`) |
| **Scenario 4: Aceleração HW Total (`C4`)** | PL `lzss_accel` (`0x43C00000`) | PL `aes_accel` (`0x43C10000`) | Bit-exact `Case 4 == Case 2` + full reverse decrypt/decompress == `raw_in` |

*Dynamic Per-Frame Keystream Uniqueness:* Each frame derives `IV = [0xf0..0xf9 (10 B) || BE16(seq_id) (2 B) || 0x00000001 (4 B)]` paired with the NIST 128-bit test key (`2b7e1516...09cf4f3c`).

### 2.4 Instrumentation & Zero-Drop Burst Protocol

- **PMU Calibration (`main.c`):** `PMCCNTR` read overhead is calibrated at boot (**`28` CPU cycles**) and subtracted cleanly from both `comp_cycles` and `crypt_cycles` inside `calc_calibrated_cycles()` (`pipeline_mgr.c`).
- **Metric Equations (`N = 20` balanced samples per profile, excluding cold-cache startup `[VERIFY]` lines):**
  - $\text{Latency (ms)} = \frac{\overline{C_{\text{PMU}}}}{650{,}000}$
  - $\text{Compression Ratio (Space Savings \%)} = \left(1 - \frac{L_{\text{comp}}}{1024}\right) \times 100\%$
  - $\text{Throughput (MiB/s)} = \frac{1024 / 1048576}{\text{Latency (ms)} / 1000}$ (note: $1\text{ MiB/s} = 1.048576\text{ MB/s}$)
  - $\text{Speedup vs. C1} = \frac{\overline{C_{\text{PMU, C1}}}}{\overline{C_{\text{PMU, Ck}}}}$
- **Zero-Drop Burst Capture Protocol:** Synchronous per-frame 4-scenario evaluation + UART prints take `~23–73 ms/frame`, originally dropping Frame 0 (during a `30 ms` trigger sleep) and creating `stride=2` (`Dynamic`) / `stride=3` (`Chaotic`) losses against the `35.2 ms` ESP32 frame period. Switching to a **`250 us` JA1 pulse** and **offline 30-frame static burst buffering (`s_burst_buf[30]`)** with immediate ACK staging eliminated all packet drops and removed the prior sampling bias (`0.00 B` bias vs. `g_telemetry_dataset`).

---

## 3. Empirical Results (`N = 20` Balanced per Entropy Profile)

### 3.1 Compression Fidelity & Output Bounds (`1024 B` Input)

| Entropy Profile | Raw Payload | Min / Max Compressed | Mean ± Std (Bytes) | Space Savings CR (%) | Max Match (`30` frames) | `mod 4` Tails Tested | BRAM Headroom (`2048 B`) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Quiescent** | 1024 B | `440 – 469 B` | `453.20 ± 8.58 B` | **`+55.74%`** (`+54.2%`..`+57.0%`) | `15 B` (`<= 16 B`) | `{0, 1, 2, 3}` | `1,579 B` |
| **Dynamic** | 1024 B | `994 – 1005 B` | `998.00 ± 3.24 B` | **`+2.54%`** (`+1.9%`..`+2.9%`) | `5 B` (`<= 16 B`) | `{0, 1, 2, 3}` | `1,043 B` |
| **Chaotic** | 1024 B | `1152 – 1154 B` | `1153.40 ± 0.68 B` | **`-12.64%`** (`-12.7%`..`-12.5%`) | `3 B` (`<= 16 B`) | `{0, 1, 2}` | `894 B` |

> Every frame in the 30-frame dataset had max match length `<= 15 B <= c_max_lookahead (16 B)`, making SW (`LZSS_MAX_MATCH=258`) and PL (`c_max_lookahead=16`) bit-for-bit identical across all `60/60` HIL runs.

### 3.2 Complete 12-Cell Execution Performance Matrix (`650 MHz` PS / `100 MHz` PL)

| Scenario | Entropy Profile | N | PMU Cycles (Mean ± Std) | PMU Min – Max | Latency (ms) | PL Cycles (Mean) | CR (%) | Throughput (MiB/s / MB/s) | Speedup vs. C1 |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **C1: SW/SW** | Quiescent | 20 | `2,467,688 ± 57,741` | `2,378,362 – 2,561,513` | `3.796` | `0` | `+55.7%` | `0.257 / 0.270` | `1.000x` |
| **C1: SW/SW** | Dynamic | 20 | `6,621,969 ± 20,324` | `6,591,574 – 6,663,222` | `10.188` | `0` | `+2.5%` | `0.096 / 0.101` | `1.000x` |
| **C1: SW/SW** | Chaotic | 20 | `8,389,708 ± 15,135` | `8,350,672 – 8,411,598` | `12.907` | `0` | `-12.6%` | `0.076 / 0.079` | `1.000x` |
| **C2: HW/SW** | Quiescent | 20 | `3,893,369 ± 89,334` | `3,752,828 – 4,043,591` | `5.990` | `200,972` | `+55.7%` | `0.163 / 0.171` | `0.634x` |
| **C2: HW/SW** | Dynamic | 20 | `10,473,009 ± 36,864` | `10,422,416 – 10,555,781` | `16.112` | `573,622` | `+2.5%` | `0.061 / 0.064` | `0.632x` |
| **C2: HW/SW** | Chaotic | 20 | `13,366,113 ± 21,824` | `13,311,528 – 13,393,508` | `20.563` | `744,661` | `-12.6%` | `0.047 / 0.050` | `0.628x` |
| **C3: SW/HW** | Quiescent | 20 | **`1,994,017 ± 53,850`** | `1,916,923 – 2,099,405` | **`3.068`** | `668` | `+55.7%` | **`0.318 / 0.334`** | **`1.238x`** |
| **C3: SW/HW** | Dynamic | 20 | **`5,576,620 ± 22,043`** | `5,546,615 – 5,621,633` | **`8.579`** | `1,452` | `+2.5%` | **`0.114 / 0.119`** | **`1.188x`** |
| **C3: SW/HW** | Chaotic | 20 | **`7,175,201 ± 10,382`** | `7,155,744 – 7,190,803` | **`11.039`** | `1,679` | `-12.6%` | **`0.088 / 0.093`** | **`1.169x`** |
| **C4: HW/HW** | Quiescent | 20 | `3,419,303 ± 85,605` | `3,292,497 – 3,583,937` | `5.260` | `201,639` | `+55.7%` | `0.186 / 0.195` | `0.722x` |
| **C4: HW/HW** | Dynamic | 20 | `9,427,015 ± 37,116` | `9,377,983 – 9,505,186` | `14.503` | `575,075` | `+2.5%` | `0.067 / 0.071` | `0.702x` |
| **C4: HW/HW** | Chaotic | 20 | `12,150,877 ± 17,163` | `12,117,371 – 12,172,667` | `18.694` | `746,340` | `-12.6%` | `0.052 / 0.055` | `0.691x` |

### 3.3 PL Hardware Cycle Models & Stage Breakdown (`TEST 4/5`)

- **PL AES-128-CTR (`aes_accel`):** Deterministic exact closed-form execution latency matching hardware to the single cycle:
  $$C_{\text{PL, AES}}(N) = 10 + 11 \cdot \left\lceil \frac{N}{16} \right\rceil + 3 \cdot \left\lceil \frac{N}{4} \right\rceil$$
  Observed means: **`667.6` cyc (`6.68 us`)** on Quiescent, **`1,452.4` cyc (`14.52 us`)** on Dynamic, **`1,678.6` cyc (`16.79 us`)** on Chaotic (`1154 B` -> `1,680` cyc).
- **PL LZSS (`lzss_accel`):** `200,971.7 ± 5,363.4` cyc (`2.010 ms`, `193,192–211,667`) on Quiescent; `573,622.4 ± 2,298.2` cyc (`5.736 ms`, `570,538–578,440`) on Dynamic; `744,661.4 ± 1,081.8` cyc (`7.447 ms`, `742,593–746,048`) on Chaotic.
- **Stage Isolation (`TEST 4/5`, `Quiescent` frame 0 -> `447 B` in Scenario 4):** Compression stage took **`3,477,406` CPU cycles (`5.350 ms`)** while encryption stage took **`117,575` CPU cycles (`0.181 ms`)** (`211,667` vs. `654` PL cycles), confirming that compression dominates `> 96%` of total pipeline latency.

### 3.4 FPGA Resource Utilization & Timing Closure (`XC7Z010-1CLG400C`)

From Vivado post-implementation [`utilization.rpt`](../hw/vivado/utilization.rpt), [`timing_summary.rpt`](../hw/vivado/timing_summary.rpt), and per-IP out-of-context synthesis runs:

| Scope / IP Block | Slice LUTs (% / 17,600) | Flip-Flops (% / 35,200) | BRAM Tiles (% / 60) | DSP48E1 (% / 80) | Timing (`WNS` / `WHS`) |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Full Routed System (`soc_final_bd_1_wrapper`)** | **8,810 (50.06%)** | **12,048 (34.23%)** | **9 (15.00%)** | **0 (0.00%)** | `clk_fpga_1 (100M): +0.551 ns / +0.008 ns`<br>`clk_fpga_0 (50M): +8.299 ns / +0.024 ns` |
| `aes_accel_0` (OOC synth) | 2,764 (15.70%) | 2,274 (6.46%) | 0 (0.00%) | 0 | `0` Latches |
| `lzss_accel_0` (OOC synth) | 667 (3.79%) | 457 (1.30%) | 0 (0.00%) | 0 | `0` Latches |
| `axi_quad_spi_0` (OOC synth) | 558 (3.17%) | 857 (2.43%) | 1 (1.67%) | 0 | `256 B` FIFO |
| `bmg_*` (`4 × 8 KB` Dual-Port BRAM) | `4 × 10 = 40` | `4 × 12 = 48` | `4 × 2 = 8` (13.33%) | 0 | `8 RAMB36E1 + 2 RAMB18E1` total in chip |
| `axi_bram_ctrl_*` (`4×`) + `axi_periph` (`xbar/cc/pc`) | Remainder (~4,781) | Remainder (~8,412) | 0 | 0 | `0` Failing Endpoints (`33,838` checked) |

---

## 4. Deep-Dive Findings & Trade-Off Analysis

1. **Why Hybrid `SW + PL AES` Beats Pure SW (`1.17x–1.24x`), Yet Stops Below Theoretical Max:**
   - Software AES-CTR requires ~`590k–1,330k` CPU cycles (`~0.91–2.05 ms`), whereas PL `aes_accel` computes the entire `1154 B` keystream XOR in only `1,680` cycles (`16.79 us`) -> saving `474k–1,215k` CPU cycles net (`14.5%–19.2%`).
   - Remaining CPU time in Stage 2 (`117,575` cycles = `0.181 ms` on `447 B`) is dominated by single-word MMIO transfers over the `50 MHz` `M_AXI_GP0` interconnect (`13` CPU clocks per `50 MHz` AXI cycle + `axi_clock_converter` latency) and CSR polling. Moving to `AXI4-Stream` + `AXI DMA` on `S_AXI_HP0` would cut that copy overhead sharply for larger payloads.
2. **Why PL LZSS Underperformed PS Software (Architectural Risk R9):**
   - `lzss_accel.vhdl` scans up to `256` dictionary positions sequentially through a single synchronous BRAM Port B read port (`3` PL clock cycles/byte comparison + `48`-cycle `lookahead_r` reload after every emitted token) at `100 MHz`.
   - Meanwhile, the Cortex-A9 runs at `650 MHz` (`6.5x` faster clock) directly out of its `32 KB` L1 data cache with zero MMIO wait states.
   - Furthermore, the measured `ΔCPU / ΔPL` ratio (~`15.5–15.7x` vs. nominal `6.5x`) shows heavy synchronous MMIO polling/copy cost over the `50 MHz -> 100 MHz` clock-crossing AXI bridge.
   - **Actionable RTL Redesign Path (Future Work):** Parallelizing comparison via a banked CAM or hash-chain table, maintaining `lookahead_r` as a shift register (eliminating the `48`-cycle reload), and streaming over `HP0` DMA would invert Risk R9.
3. **Worst-Case Expansion (`Chaotic`: `+130 B` -> `1154 B`) & System Sizing:**
   - Without compression bypass, incompressible sensor bursts incur `12.64%` bandwidth expansion (`128` flag bytes + `2 B` header) plus `~12.9–20.6 ms` total latency (`12.9 ms` even in C1 vs `0.21 ms` AES-only in C3). An adaptive compressibility gate (bypassing LZSS when entropy is high) would improve worst-case Chaotic latency and bandwidth.

---

## 5. Supporting Static & Simulation Verification Ledger

All automated verification suites ran cleanly on the final committed state (`main`):
- **VUnit + GHDL RTL Simulations (`make -C cora7z/app/hw test`):** **`12 / 12` PASS** (`tb_lzss_accel` `7/7` including `1024 B` `Quiescent/Dynamic/Chaotic` golden checks; `tb_aes_accel` `5/5` including NIST SP 800-38A, `1024 B` 64-block, and `1154 B` `bram_out_we="0011"` tail protection).
- **Host C11 Hardware-Mock Suite (`make -C cora7z/app/sw/test clean run`):** **PASS** (`-std=c11 -Wall -Wextra -Werror`, all 30 Embedded Dataset frames, wire-level `1035 B` `TelemetryFrame` + `15 B` ACK + `-4` oversized length guard).
- **ESP32 Python Generator Tests (`esp32/scripts` `unittest`):** **`7 / 7` PASS**.
- **Toolchain & Governance Gates:** `c-lint.sh` (`17` files), `vhdl-lint.sh` (`2` files), `vitis-gate.sh`, `bench-sanity.py` (`12` rows), `plan-sync.py check`, `deliverable-audit.sh`, and `memory-check.py` — **ALL PASS**.

---

## 6. Recommended Slide Deck Structure

1. **Title & Motivation:** Heterogeneous SoC Compress-then-Encrypt on Zynq-7010 (`PS @ 650 MHz` vs `PL @ 100 MHz`) for IoT/Industrial Telemetry.
2. **Hardware Architecture & BRAM Decoupling (ADR-012):** Block diagram (`cora7z_top.png`), `axi_quad_spi_0` ingress, `4 × 8 KB` True Dual-Port BRAMs avoiding DMA stalls, `8,810 LUTs / 12,048 FFs / 9 BRAMs` @ `+0.551 ns` slack.
3. **Test Methodology & ADR-020 Workload:** ESP32 SPI master (`2 MHz`, `250 us` `JA1` trigger), `1024 B` fixed frame across `Quiescent / Dynamic / Chaotic`, 4 execution scenarios, `650 MHz` PMU (`28`-cycle calibrated).
4. **Real-Time HIL Reliability Fix:** Root cause of initial `40%` burst loss (`30 ms` trigger wait + synchronous `d=2/3` stride drops) -> decoupled 30-frame RAM burst buffering (`60/60` zero-drop capture, `0` CRC/frame errors).
5. **Compression Across Entropy Regimes:** `Quiescent (+55.7%)` vs `Dynamic (+2.5%)` vs `Chaotic (-12.6% / 1154 B)` and bit-exact SW/PL parity (`max match <= 15 B`).
6. **End-to-End Performance Matrix (`C1..C4`):** Chart of Latency & Speedup (`Scenario 3 = 1.24x / 1.19x / 1.17x` winner; `Scenario 2/4 = 0.63x / 0.69–0.72x`).
7. **Deep-Dive Trade-Off Analysis (Why AES Wins & Why LZSS Hit Risk R9):** Iterative `11`-cyc/block AES vs `3`-cyc/byte sequential BRAM scan + `M_AXI_GP0` copy overhead.
8. **Conclusions & Engineering Lessons:** Hybrid PS-Compression + PL-Crypto optimality, entropy-aware bypass, parallel hash/CAM + DMA future roadmap.
