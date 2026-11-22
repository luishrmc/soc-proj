# System Verification & HIL Benchmark Test Plan (ADR-012 / ADR-017 / ADR-020)

This document defines the unified static verification, simulation, and Hardware-in-the-Loop (HIL) benchmark procedures for evaluating Compress-then-Encrypt (`LZSS` + `AES-128-CTR`) architectures on the Digilent Cora Z7-10 (`XC7Z010-1CLG400C`) with the ESP32 SPI synthetic telemetry injector.

---

## 1. Test Objectives & Canonical Definitions

1. **Functional Equivalence & Fidelity:**
   - **SW LZSS** (`lzss_sw`, `window=256`, `max_match=258`) and **PL LZSS** (`lzss_accel`, `window=256`, `lookahead=16`) emit compliant Heatshrink/LZSS bitstreams (16-bit Big-Endian uncompressed length header + 8-token flag chunks), reconstructing original raw bytes bit-for-bit via `lzss_decompress`.
   - **SW AES-128-CTR** (`aes_ctr_sw`) and **PL AES-128-CTR** (`aes_accel`) produce bit-exact ciphertexts across NIST SP 800-38A Section F.5.1 vectors, multi-block `1024 B` payloads, and non-word-aligned lengths (including worst-case Chaotic `1154 B` expansion).
2. **ADR-020 Standardized Payload & Entropy Profiles:**
   - **Fixed Payload Size:** **1024 bytes** (`64` packed 16-byte `Telemetry Record`s per frame; `1035 B` total SPI wire `TelemetryFrame` with `pkt_type = 0x02`).
   - **Three Canonical Entropy Profiles (`--seed 42`):**
     - `Quiescent`: Near-steady telemetry with small jitter (high LZSS compressibility; ref PL compressed size `447 B`).
     - `Dynamic`: Sinusoidal motion/thermal variation with moderate noise (moderate compressibility; ref PL compressed size `1000 B`).
     - `Chaotic`: Uniformly distributed random transients (incompressible worst-case LZSS expansion; ref PL compressed size `1154 B <= 2048 B` BRAM capacity).
3. **Canonical Metrics:**
   - **Compression Ratio (Space Savings %):** $\text{CR} = \left(1 - \frac{L_{\text{comp}}}{L_{\text{raw}}}\right) \times 100\%$. Positive values denote shrinkage (`Quiescent`, `Dynamic`); negative values denote framing expansion on high-entropy payloads (`Chaotic`, e.g., `-12.7%`).
   - **Latency ($T_{\text{lat}}$):** Measured via ARM Cortex-A9 PMU `PMCCNTR` at `650 MHz` (`XPAR_CPU_CORE_CLOCK_FREQ_HZ`, calibrated 28-cycle overhead subtracted) reported with sample mean and standard deviation across $N \ge 10$ frames per `(Scenario, Profile)`.
   - **PL Hardware Cycles ($C_{\text{PL}}$):** Sampled from `0x43C00010` (`lzss_accel` @ `100 MHz`) and `0x43C10010` (`aes_accel` @ `100 MHz`).
   - **Throughput:** $\frac{\text{Payload Size (1024 B)}}{T_{\text{lat}}}$.

---

## 2. Four Execution Scenarios (12-Row Benchmark Matrix)

| Scenario | Pipeline Configuration | FPGA Utilization (`XC7Z010`) |
| :--- | :--- | :--- |
| **Scenario 1: SW Puro** | SW LZSS + SW AES-CTR | N/A |
| **Scenario 2: Offload Compressão** | PL LZSS + SW AES-CTR | Pending standalone synthesis isolate |
| **Scenario 3: Offload Cifragem** | SW LZSS + PL AES-CTR | Pending standalone synthesis isolate |
| **Scenario 4: Aceleração HW Total** | PL LZSS + PL AES-CTR | `8,810 LUTs / 12,048 FFs / 9 BRAMs` |

Each scenario is measured across all 3 Entropy Profiles (`Quiescent`, `Dynamic`, `Chaotic`) at `1024 B`, forming the 12-row matrix tracked in [Matriz_de_Testes_e_Métricas.csv](../../../utils/plan/Matriz_de_Testes_e_Métricas.csv).

---

## 3. Pre-HIL Static Verification Suites

### A. Python Telemetry Generator Tests
```bash
python3 -m unittest discover -s esp32/scripts -p "test_*.py" -v
```
Verifies 16-byte record packing, 1024 B frame synthesis, determinism across seeds, strict entropy/compressibility ordering (`Quiescent < Dynamic < Chaotic`), and C header/source generation (`gcc -c`).

### B. VHDL-2008 RTL Simulation (VUnit + GHDL)
```bash
source .agents/env.sh && make -C cora7z/app/hw test
```
Executes 12 self-checking test cases across `tb_lzss_accel` and `tb_aes_accel`:
- CSR read/write and synchronous soft reset checks.
- **ADR-020 `1024 B` Profile Vectors** (`test_adr020_quiescent_1024b` -> `447 B`, `test_adr020_dynamic_1024b` -> `1000 B`, `test_adr020_chaotic_1024b` -> `1154 B`) verified byte-for-byte against Python golden references.
- **AES-128-CTR Multi-Block & Tail Checks** (`test_nist_sp800_38a_vector`, `test_adr020_1024b_blocks`, `test_adr020_1154b_unaligned_tail` verifying halfword `bram_out_we = "0011"` preservation).

### C. Host C11 Verification & Behavioral Hardware Mock Suite
```bash
make -C cora7z/app/sw/test run   # or gcc -std=c11 -Wall -Wextra -Werror ...
```
Validates `test_sw_pipeline_run_all()`, `test_sw_pipeline_benchmark_sweep()`, all **30** `seed=42` `Embedded Dataset` frames across all 4 scenarios (via behavioral MMIO mocks), and `1035 B` `TelemetryFrame` + `15 B` `ACK` wire-level `axi_spi_receiver` parsing.

---

## 4. Physical HIL Execution Procedure (ESP32 <-> Cora Z7-10)

1. **Hardware Wiring (`3.3 V` LVCMOS):**
   - `VSPI SCLK` (ESP32 `GPIO 18`) <-> Cora `H15` (`J7.3`)
   - `VSPI MOSI` (ESP32 `GPIO 23`) <-> Cora `T12` (`J7.4`)
   - `VSPI MISO` (ESP32 `GPIO 19`) <-> Cora `W15` (`J7.1`)
   - `VSPI CS0`  (ESP32 `GPIO 5`)  <-> Cora `F16` (`J7.5`)
   - `TRIGGER`   (ESP32 `GPIO 32`) <-  Cora `Y18` (`PMOD JA1`, 30 ms active-low pulse)
2. **Burst Execution & Consolidation:**
   - Cora Z7 executes `test_sw_pipeline_run_all()`, `test_sw_pipeline_benchmark_sweep()`, emits the active-low trigger on `PMOD JA1`, and receives the 30-frame ESP32 burst (`10 Quiescent`, `10 Dynamic`, `10 Chaotic`, 30 ms inter-frame gap).
   - For each valid SPI frame, Cora Z7 stages `0x81` ACK immediately, evaluates all 4 scenarios (`Case 1..4`) with loopback verification, and prints a compact `[HIL_BENCH]` trace (~11 ms UART budget).
   - Consolidate captured UART logs into CSV matrices:
     ```bash
     python3 .agents/hooks/test_matrix_sync.py --input <uart_log> --apply
     python3 .agents/hooks/bench-sanity.py
     ```
