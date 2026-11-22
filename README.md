# Heterogeneous SoC Compression & Cryptography Platform (Cora Z7 + ESP32)
## UFMG — DELT: Topics in Computer Engineering (Silicon Systems)

[![Target: Zynq-7000](https://img.shields.io/badge/Target-Xilinx_Zynq--7000_(XC7Z010)-red.svg)](#)
[![Toolchain: Vivado & Vitis 2026.1](https://img.shields.io/badge/Toolchain-Vivado_%26_Vitis_2026.1-blue.svg)](#)
[![HDL: VHDL-2008](https://img.shields.io/badge/HDL-VHDL--2008-purple.svg)](#)
[![Firmware: C11 Bare-Metal](https://img.shields.io/badge/Firmware-C11_Bare--Metal_(Cortex--A9)-green.svg)](#)
[![Injector: ESP-IDF v6.1](https://img.shields.io/badge/Injector-ESP--IDF_v6.1_(ESP32)-orange.svg)](#)
[![Institution: UFMG DELT](https://img.shields.io/badge/UFMG-Engenharia_Eletr%C3%B4nica_(DELT)-darkred.svg)](https://www.ufmg.br/)
[![Status: HIL Verified (ADR-020)](https://img.shields.io/badge/Status-HIL_Verified_(ADR--020)-brightgreen.svg)]()
[![Hardware: Integrated & Tested](https://img.shields.io/badge/Hardware-Integrated_%26_Tested-blue.svg)]()

> [!NOTE]
> **Engineering Status — HIL Verified (`N = 20` / Entropy Profile @ 1024 B):**  
> End-to-end Hardware-in-the-Loop (HIL) execution between the ESP32 SPI master injector (`2 MHz` VSPI, `GPIO 32` trigger, `seed=42`) and Digilent Cora Z7-10 (`650 MHz` ARM Cortex-A9 PS / `100 MHz` Artix-7 PL) is validated across zero-drop `30/30` telemetry bursts with bit-exact parity (`Case 3 == Case 1`, `Case 4 == Case 2`, and reverse loopback).
>
> * **Synthetic Telemetry Pipeline (`esp32/scripts/telemetry_profiles.py`):** Emits fixed `1024 B` payloads (`64 × 16 B` records) across `Quiescent`, `Dynamic`, and `Chaotic` Entropy Profiles ([`spi_frame.h`](esp32/main/spi_frame.h), `1035 B` wire frame with CRC-16 CCITT).
> * **Hardware Architecture:** Synthesizable VHDL-2008 `lzss_accel` (`256/16`) and `aes_accel` (`AES-128-CTR`) coprocessors interfaced via True Dual-Port BRAMs (ADR-012) and AXI4-Lite CSRs.

---

## 📌 System Specifications and Physical Parameters

The parameters below define the physical hardware testbed on the Digilent Cora Z7-10:

| Parameter / Magnitude | Symbol | Value | Unit | Implementation Details |
| :--- | :---: | :---: | :---: | :--- |
| **CPU Clock (PS)** | $f_{\text{cpu}}$ | **650** | MHz | ARM Cortex-A9 MPCore (Core 0, BSP `APU_FREQ`) |
| **Accelerator Clock (PL)** | $f_{\text{accel}}$ | **100** | MHz | Clock domain `FCLK_CLK1` (Artix-7 fabric) |
| **AXI Bus Clock** | $f_{\text{axi}}$ | **50** | MHz | Clock domain `FCLK_CLK0` (`M_AXI_GP0`) |
| **DDR3 Memory Capacity** | $M_{\text{ddr}}$ | **512** | MB | 16-bit wide bus @ 533 MHz (1066 Mbps DDR3) |
| **True Dual-Port BRAM** | $M_{\text{bram}}$ | **4 $\times$ 8 (32)** | KB | 4 independent Block RAM buffers (Port A PS, Port B HW) |
| **External SPI Clock** | $f_{\text{spi}}$ | **Up to 25** | MHz | SPI Mode 0 (CPOL=0, CPHA=0, MSB-First) |
| **Payload Size** | $L_{\text{pay}}$ | **1024** | Bytes | Fixed ADR-020 payload (64 × 16 B records, CRC-16, `0x5A` EOF) |
| **LZSS Window Geometry** | $W$ / $L$ | **256 / 16** | Bytes | Sliding circular window ($2^8$) and lookahead buffer ($2^4$) |
| **Cryptographic Primitive** | --- | **AES-128-CTR** | Bits/Mode | NIST SP 800-38A (10 iterative rounds, 11 cycles/block) |
| **FPGA Logic Budget** | --- | **17,600 LUT / 35,200 FF** | Cells | AMD Xilinx Zynq XC7Z010-1CLG400C |
| **ARM PMU Measurement Overhead** | $C_{\text{pmu}}$ | **28** | Cycles | Direct CP15 inline register access (`PMCCNTR`), subtracted in SW |

---

## 🗂️ Module Map and Documentation Index

| Subsystem / Module | Source Files | Linked Specification | Architectural Role | Deliverable & Verification Status |
|---|---|:---:|---|---|
| **1. Telemetry Generator (Host)** | [`esp32/scripts/`](esp32/scripts/) | [Architecture §6.3](docs/SYSTEM_ARCHITECTURE.md#63-synthetic-telemetry-generation--esp-idf-ingestion-setup-esp32) | 1024 B synthetic telemetry (`Quiescent`, `Dynamic`, `Chaotic`) | `unittest` 7/7 PASS; `seed=42` |
| **2. SPI Injector (ESP32)** | [`spi_injector_master.c`](esp32/main/spi_injector_master.c) | [SPI_INJECTOR.md](docs/esp32/SPI_INJECTOR.md) | Physical SPI Master bridge for 30-frame `Embedded Dataset` | Mode 0 @ `2 MHz` + `GPIO 32` trigger HIL-verified |
| **3. SPI Receiver (PS/PL)** | [`axi_spi_receiver.c`](cora7z/app/sw/src/comms/axi_spi_receiver.c) | [AXI_SPI_RECEIVER.md](docs/sw/AXI_SPI_RECEIVER.md) | 256 B FIFO drainage and 32-bit word alignment | `0` CRC/frame/len errors across `30/30` bursts |
| **4. Compression Accel (PL)** | [`lzss_accel.vhdl`](cora7z/app/hw/src/compression/lzss_accel.vhdl) | [LZSS_ACCEL.md](docs/hw/LZSS_ACCEL.md) | Sliding window hardware compressor (256 B / 16 B) | VUnit `7/7` + HIL verified; Risk R9 confirmed |
| **5. Compression Baseline (PS)** | [`lzss_sw.c`](cora7z/app/sw/src/compression/lzss_sw.c) | [LZSS_SW.md](docs/sw/LZSS_SW.md) | Heatshrink-compatible C11 reference for Cortex-A9 | L1/L2 cache execution, bit-exact parity with HW model |
| **6. Crypto Accel (PL)** | [`aes_accel.vhdl`](cora7z/app/hw/src/crypto/aes_accel.vhdl) | [AES_ACCEL.md](docs/hw/AES_ACCEL.md) | Iterative 10-round AES-128-CTR hardware engine | VUnit `5/5` + HIL verified (`1.17x–1.24x` speedup) |
| **7. Crypto Baseline (PS)** | [`aes_ctr_sw.c`](cora7z/app/sw/src/crypto/aes_ctr_sw.c) | [AES_CTR_SW.md](docs/sw/AES_CTR_SW.md) | NIST SP 800-38A reference model in C11 | Golden vector validated; baseline CPU profiling target |
| **8. Pipeline Manager** | [`pipeline_mgr.c`](cora7z/app/sw/src/pipeline/pipeline_mgr.c) | [PIPELINE_MGR.md](docs/sw/PIPELINE_MGR.md) | Orchestration of 4 scenarios and DEVCFG bus safety | `PCFG_DONE` interlock + calibrated PMU (`650 MHz`) |
| **9. Architectural Diagrams** | [`cora7z_top.png`](docs/diagrams/cora7z_top.png) | [Diagrams README](docs/diagrams/README.md) | High-resolution 3200 $\times$ 1800 block diagram | Memory map, bus interconnects, pin allocation |

---

## 1. Data Ingestion Subsystem: Python Generator & AXI Quad SPI

### Technical Details
Data ingestion combines a host-side **Python synthetic telemetry generator** with an **ESP32-WROOM** bridge operating at 240 MHz (ESP-IDF v6.1). Its hardware SPI Master operates in **Mode 0** (CPOL=0, CPHA=0, MSB-First) for synchronous transfers up to 25 MHz.

On the Cora Z7, the physical lines connect to the Xilinx LogiCORE **`axi_quad_spi_0`** IP in slave mode (base address `0x41E00000`), configured with a 256-byte FIFO and routed through Header J7:
* `SCLK` $\to$ Pin `H15` (Header J7.3)
* `MOSI` $\to$ Pin `T12` (Header J7.4)
* `MISO` $\to$ Pin `W15` (Header J7.1)
* `SS_N` $\to$ Pin `F16` (Header J7.5)

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| Preamble 0xA5 | Pkt Type 0x01 |       Sequence ID (15:0)      | [0..3]
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   Payload Length (15:0)       |   Reserved Padding (0x0000)   | [4..7]
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                  Payload Byte 0 (32-bit aligned)              | [8..]
|                              ...                              |
|                  Payload Byte N-1                             | [8+N-1]
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       CRC-16-CCITT (15:0)     | EOF Delim 0x5A|                 [8+N .. 8+N+2]
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### Architectural Role
* **Synthetic Stream Validation:** Ingests structured telemetry streams modeling multi-channel sensor arrays to exercise compression and encryption stages under repeatable statistical conditions.
* **32-Bit Word Alignment:** The 2-byte `reserved_align` field ensures that `payload[0]` starts at byte offset 8, allowing native 32-bit word reads by the Cortex-A9 CPU and DMA controller.
* **Handshake Sequence:**
  1. The Cora Z7 issues an active-low trigger pulse on **PMOD JA1** (`Y18`) connected to ESP32 **GPIO 32** (or the ESP32 transmits autonomously via FreeRTOS timer pacing).
  2. The ESP32 formats the binary frame with CRC-16 CCITT and initiates the SPI transaction.
  3. The PS driver [`axi_spi_receiver.c`](cora7z/app/sw/src/comms/axi_spi_receiver.c) drains the FIFO into DDR3 and validates frame integrity.

---

## 2. Memory Architecture & Interconnect: BRAM Decoupling (ADR-012)

### Technical Details
To eliminate deadlock hazards associated with variable-length compressed streams in traditional AXI DMA configurations, the platform implements four dedicated **True Dual-Port Block RAMs** (8 KB each):
* **`bmg_lzss_in`** (`0x40000000`) and **`bmg_lzss_out`** (`0x40002000`).
* **`bmg_aes_in`** (`0x40010000`) and **`bmg_aes_out`** (`0x40012000`).

**Port A** connects to AXI BRAM controllers mapped into the CPU memory space (`M_AXI_GP0` @ 50 MHz). **Port B** connects directly to the hardware accelerator datapaths (`clk`, `addr[12:0]`, `din[31:0]`, `dout[31:0]`, `we[3:0]` @ 100 MHz).

```mermaid
sequenceDiagram
    participant CPU as ARM Cortex-A9 (PS)
    participant BRAM_IN as Input BRAM (Port A/B)
    participant ACCEL as HW Accelerator (PL)
    participant BRAM_OUT as Output BRAM (Port A/B)

    CPU->>BRAM_IN: 1. MMIO Write of Raw Payload (Port A @ 50 MHz)
    CPU->>ACCEL: 2. Write REG_PAYLOAD_LEN & assert START in REG_CTRL
    Note over ACCEL: 3. Autonomous Execution: Read Port B, Compute, Write Port B (100 MHz)
    ACCEL->>BRAM_OUT: Write Tokens / Ciphertext (Port B)
    ACCEL-->>CPU: 4. Assert STATUS_DONE & lock CYCLE_COUNT
    CPU->>BRAM_OUT: 5. MMIO Read of Processed Data (Port A @ 50 MHz)
```

### Architectural Benefit
In streaming AXI DMA architectures, if compressed output size is smaller than expected by a DMA descriptor, the S2MM channel can stall awaiting missing bytes, hanging the AXI bus. BRAM decoupling eliminates this failure mode: the accelerator locks the exact output byte count in `REG_PAYLOAD_LEN`, allowing the CPU to read the precise number of bytes generated.

---

## 3. Compression Subsystem: `lzss_accel` & `lzss_sw`

The compression modules implement a Heatshrink-compatible sliding window dictionary algorithm:
* **Sliding Window:** 256-byte circular buffer ($W = 8$).
* **Lookahead Comparison Buffer:** 16 bytes ($L = 4$) with linear window search.
* **Token Packing:** Bit-level token encoding where a `'0'` flag bit precedes an 8-bit literal byte, and a `'1'` flag bit precedes a 2-byte offset-length tuple (`dist-1`, `len-3`) for repeated sequences of 3 to 16 bytes (`c_min_match = 3`, `c_max_lookahead = 16`).
* **Hardware Architecture:** Designed without dynamic heap memory allocation, operating over BRAM Port B at 100 MHz.

---

## 4. Cryptographic Subsystem: `aes_accel` & `aes_ctr_sw`

The encryption module implements AES-128 in Counter (CTR) mode compliant with **NIST FIPS-197** and **NIST SP 800-38A**:
* **Hardware Datapath:** Iterative architecture processing 1 round per clock cycle (SubBytes ROM S-Box, ShiftRows, MixColumns over $GF(2^8)$, and AddRoundKey).
* **On-the-Fly Key Expansion:** Computes round keys dynamically during the 10 iterative rounds.
* **Keystream Generation:** Counter block $T_j = \text{IV} \parallel \text{Counter}_j$ is encrypted to produce a 128-bit keystream block XORed with plaintext in **11 clock cycles per 16-byte block**.
* **Keystream Reuse Prevention:** The monotonic sequence ID (`seq_id`) is bound into the upper 64 bits of the IV, ensuring distinct keystreams across successive packets.

---

## 5. Processing System: PS Supervisor & Bare-Metal Firmware

The bare-metal C11 firmware in [`cora7z/app/sw/src/`](cora7z/app/sw/src/) orchestrates the system:
* **Bus Safety Interlock (`is_pl_programmed`):** Checks Bit 2 of the DEVCFG status register (`0xF800700C`, `PCFG_DONE`). If the FPGA is unprogrammed, accesses to `M_AXI_GP0` are inhibited, preventing fatal Cortex-A9 bus lockups.
* **Cycle-Accurate Profiling (ARM PMU):** Directly accesses CP15 register `PMCCNTR` at `650 MHz` (`XPAR_CPU_CORE_CLOCK_FREQ_HZ`) with a calibrated overhead of `28` cycles subtracted cleanly.
* **Zero Dynamic Allocation:** Uses static memory allocation exclusively, adhering to MISRA-C principles.

---

## 6. Benchmark Evaluation Methodology & HIL Results

The experimental framework evaluates four execution scenarios at a fixed **1024-byte payload** across three synthetic **Entropy Profiles** (`Quiescent`, `Dynamic`, and `Chaotic`) per [ADR-020](docs/adr/0020-fixed-1024b-benchmark-payload.md). All figures below are hardware-measured on the Digilent Cora Z7-10 (`650 MHz` Cortex-A9 PS / `100 MHz` PL) across two zero-drop `30/30` ESP32 SPI bursts (`N = 20` balanced samples per Entropy Profile, `28`-cycle PMU overhead subtracted):

| Scenario | Pipeline Description | Payload | Entropy Profile | Latency (ms) | PMU Cycles (Mean ± Std) | PL Cycles (Mean) | Space Savings (CR) | Throughput | Speedup |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Scenario 1: PS Only** | SW LZSS + SW AES-CTR | 1024 B | Quiescent | 3.796 | 2,467,688 ± 57,741 | 0 | 55.7% | 0.26 MB/s | 1.00x (Ref) |
| **Scenario 1: PS Only** | SW LZSS + SW AES-CTR | 1024 B | Dynamic | 10.188 | 6,621,969 ± 20,324 | 0 | 2.5% | 0.10 MB/s | 1.00x (Ref) |
| **Scenario 1: PS Only** | SW LZSS + SW AES-CTR | 1024 B | Chaotic | 12.907 | 8,389,708 ± 15,135 | 0 | -12.6% | 0.08 MB/s | 1.00x (Ref) |
| **Scenario 2: Offload Comp** | PL LZSS + SW AES-CTR | 1024 B | Quiescent | 5.990 | 3,893,369 ± 89,334 | 200,972 | 55.7% | 0.16 MB/s | 0.63x |
| **Scenario 2: Offload Comp** | PL LZSS + SW AES-CTR | 1024 B | Dynamic | 16.112 | 10,473,009 ± 36,864 | 573,622 | 2.5% | 0.06 MB/s | 0.63x |
| **Scenario 2: Offload Comp** | PL LZSS + SW AES-CTR | 1024 B | Chaotic | 20.563 | 13,366,113 ± 21,824 | 744,661 | -12.6% | 0.05 MB/s | 0.63x |
| **Scenario 3: Offload Crypto** | SW LZSS + PL AES-CTR | 1024 B | Quiescent | **3.068** | **1,994,017 ± 53,850** | 668 | 55.7% | **0.32 MB/s** | **1.24x** |
| **Scenario 3: Offload Crypto** | SW LZSS + PL AES-CTR | 1024 B | Dynamic | **8.579** | **5,576,620 ± 22,043** | 1,452 | 2.5% | **0.11 MB/s** | **1.19x** |
| **Scenario 3: Offload Crypto** | SW LZSS + PL AES-CTR | 1024 B | Chaotic | **11.039** | **7,175,201 ± 10,382** | 1,679 | -12.6% | **0.09 MB/s** | **1.17x** |
| **Scenario 4: All Hardware** | PL LZSS + PL AES-CTR | 1024 B | Quiescent | 5.260 | 3,419,303 ± 85,605 | 201,639 | 55.7% | 0.19 MB/s | 0.72x |
| **Scenario 4: All Hardware** | PL LZSS + PL AES-CTR | 1024 B | Dynamic | 14.503 | 9,427,015 ± 37,116 | 575,075 | 2.5% | 0.07 MB/s | 0.70x |
| **Scenario 4: All Hardware** | PL LZSS + PL AES-CTR | 1024 B | Chaotic | 18.694 | 12,150,877 ± 17,163 | 746,340 | -12.6% | 0.05 MB/s | 0.69x |

### Evaluation Protocol & Key Findings
* **Latency ($T_{\text{lat}}$) & Cycles ($C_{\text{PMU}}$):** Sampled via `PMCCNTR` at `650 MHz` (calibrated: `28` CPU cycles overhead, subtracted).
* **Hardware Cycles ($C_{\text{PL}}$):** Sampled from accelerator status registers at `100 MHz`.
* **Compression Ratio (Space Savings %):** Computed as `(1 - comp_len / raw_len) * 100%` (`+55.7%` Quiescent, `+2.5%` Dynamic, `-12.6%` Chaotic expansion to `1154 B`).
* **Architectural Risk R9 Confirmed (PS vs. PL Compression):** Sequential BRAM sliding-window lookahead search in PL (`201k–745k` cycles at `100 MHz` + AXI BRAM copy) is ~`1.58x` slower than Cortex-A9 L1/L2 cache SW LZSS at `650 MHz`. Conversely, **Scenario 3 (`SW LZSS + PL AES-CTR`)** achieves **1.17x–1.24x** end-to-end speedup across all three entropy profiles (`668–1,679` PL cycles @ `100 MHz`).

### Target FPGA Silicon Resource Budgets (AMD Xilinx XC7Z010)

| Hardware Resource | Device Total Budget | Target Design Budget (85%) | Post-Implementation Utilization | Timing Status |
| :--- | :---: | :---: | :---: | :---: |
| **LUTs (Combinational Logic)** | 17,600 | $\le$ 14,960 | 8,810 (50.06%) | `WNS = +0.551 ns` / `WHS = +0.008 ns` |
| **Flip-Flops (Registers)** | 35,200 | $\le$ 29,920 | 12,048 (34.23%) | `0` Latches |
| **Block RAM (RAMB36 Equivalents)** | 60 | $\le$ 51 | 9 (15.00%) | `0` Failing Endpoints |
| **DSP48E1 Slices** | 80 | $\le$ 68 | 0 (0.00%) | — |

---

## 7. Build, Simulation & Execution Runbook

### 1. Environment Setup
Prerequisites:
* Ubuntu Linux 22.04 / 24.04 LTS
* AMD Xilinx Vivado and Vitis 2026.1
* GHDL 4.1+ and Python with VUnit (`pip install vunit_hdl`)
* Espressif ESP-IDF v6.1+

Source the unified environment script:
```bash
source .agents/env.sh
```

### 2. RTL Simulation (VUnit + GHDL)
```bash
make -C cora7z/app/hw venv
make -C cora7z/app/hw test
```

### 3. Hardware Platform Build (Vivado Batch Mode)
```bash
bash cora7z/app/hw/scripts/run_vivado.sh cora7z/app/hw/scripts/build_bitstream.tcl
```
*Generates:* `cora7z/app/hw/vivado/cora7z_top.xsa` containing the integrated bitstream.

### 4. Bare-Metal Application Compilation (Vitis Python CLI)
```bash
vitis -s cora7z/app/sw/scripts/build_sw.py
```
*Generates:* `cora7z/app/sw/vitis/cora7z_firmware/build/cora7z_firmware.elf`.

### 5. Flash ESP32 Synthetic Data Injector
Connect ESP32 via USB (e.g. `/dev/ttyACM0`):
```bash
cd esp32
idf.py build
idf.py -p /dev/ttyACM0 flash monitor
```

### 6. Program and Launch Cora Z7
Connect the Cora Z7 via USB JTAG/UART:
```bash
# Terminal 1: Monitor UART output
picocom -b 115200 /dev/ttyUSB1

# Terminal 2: Download bitstream, FSBL, and application ELF
vitis -s cora7z/app/sw/scripts/launch_app.py
```

---

## 8. Repository Layout

```text
ufmg/soc/proj/
├── cora7z/
│   └── app/
│       ├── hw/                 # VHDL-2008 RTL, constraints, synthesis scripts
│       │   ├── src/
│       │   │   ├── compression/ # lzss_accel.vhdl
│       │   │   └── crypto/      # aes_accel.vhdl
│       │   ├── test/           # tb_lzss_accel.vhdl, tb_aes_accel.vhdl (VUnit)
│       │   ├── scripts/        # configure_block_design.tcl, build_bitstream.tcl, run_vivado.sh
│       │   └── utils/          # cora_z7_io.xdc, cora_z7_pins.json
│       └── sw/                 # C11 Bare-metal firmware (ARM Cortex-A9)
│           ├── src/
│           │   ├── compression/ # lzss_sw.{c,h}
│           │   ├── crypto/      # aes_ctr.{c,h}, aes_ctr_sw.{c,h}
│           │   ├── comms/       # axi_spi_receiver.{c,h}, spi_frame.h
│           │   ├── pipeline/    # main.c, pipeline_mgr.{c,h}
│           │   └── utils/       # axi_io.h, test_sw_pipeline.{c,h}
│           └── scripts/        # build_sw.py, launch_app.py
├── esp32/                      # Autonomous SPI synthetic injector (ESP-IDF v6.1)
│   ├── main/                   # main.c, spi_injector_master.{c,h}, trigger_gpio.{c,h}, spi_frame.h
│   └── scripts/                # generate_telemetry.py, telemetry_profiles.py, test_generate_telemetry.py
├── docs/                       # Architectural, module, and hardware documentation
│   ├── hw/                     # INTERFACES.md, LZSS_ACCEL.md, AES_ACCEL.md, README.md
│   ├── sw/                     # LZSS_SW.md, AES_CTR_SW.md, PIPELINE_MGR.md, AXI_SPI_RECEIVER.md, README.md
│   ├── esp32/                  # SPI_INJECTOR.md, ESP32 datasheets & pinout
│   ├── adr/                    # Architecture Decision Records
│   ├── SYSTEM_ARCHITECTURE.md
│   ├── AES_CTR_ALGORITHM.md
│   └── diagrams/               # cora7z_top.png (3200x1800), generate_soc_diagram.py
├── utils/
│   └── plan/                   # Project tracking schedules and metrics
│       ├── Cronograma_e_Tarefas.csv
│       ├── Matriz_de_Testes_e_Métricas.csv
│       ├── Checklist_de_Entregaveis.csv
│       ├── Riscos_e_Bloqueios.csv
│       └── STATUS.md
└── README.md                   # Primary system documentation
```

---

## 9. Deliverables Compliance Summary

| Deliverable | Format | Status | Location |
|---|:---:|:---:|---|
| **VHDL Source Code** | `.vhdl` | Synthesized & Verified | [`cora7z/app/hw/src/`](cora7z/app/hw/src/) (`lzss_accel.vhdl`, `aes_accel.vhdl`) |
| **VUnit Testbenches** | `.vhdl` | 12/12 PASS (GHDL) | [`cora7z/app/hw/test/`](cora7z/app/hw/test/) (`tb_lzss_accel.vhdl`, `tb_aes_accel.vhdl`) |
| **C/C++ Firmware** | `.c`, `.h` | HIL Verified (`30/30` bursts) | [`cora7z/app/sw/src/`](cora7z/app/sw/src/) and [`esp32/main/`](esp32/main/) |
| **Block Diagram** | `.png`, `.jpg` | Complete | [`docs/diagrams/cora7z_top.png`](docs/diagrams/cora7z_top.png) (3200 $\times$ 1800) |
| **Final Report** | `.pdf` | In Formatting Review | Empirical HIL metrics consolidated in [`Matriz_de_Testes_e_Métricas.csv`](utils/plan/Matriz_de_Testes_e_Métricas.csv) |
| **GitHub Repository** | Git URL | Active | [git@github.com:luishrmc/soc-proj.git](https://github.com/luishrmc/soc-proj) |
