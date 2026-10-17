# Acceleration of Compression and Encryption on Zynq-7010 (Digilent Cora Z7-10)

This repository contains the hardware (VHDL RTL on Artix-7 PL), firmware (bare-metal C/C++ on ARM Cortex-A9 PS), and verification infrastructure for evaluating hardware acceleration of data compression (RLE, LZ4) and encryption (AES-CTR, ChaCha20) on the Xilinx Zynq-7010 SoC.

---

## 1. Project Overview

Edge telemetry systems frequently ingest high-rate sensor streams that require compression and encryption before wireless transmission. Executing both routines sequentially in software introduces latency and saturates the CPU.

This project implements, characterizes, and compares three operating scenarios on the Digilent Cora Z7-10:
1. **Scenario 1: PS Pure (Software Only)**
   The ARM Cortex-A9 receives SPI telemetry, buffers raw blocks in DDR3, compresses via software routines, encrypts the payload, and outputs ciphertext.
2. **Scenario 2: PL Pure (Hardware Pipeline)**
   A dedicated VHDL pipeline in the Artix-7 fabric ingests SPI data at up to 25 MHz, streams bytes through hardware compression (RLE/LZ4), pipes blocks into the hardware cryptographic engine (AES-CTR/ChaCha20), and buffers output without CPU involvement.
3. **Scenario 3: Hybrid Co-Design (PS Control + PL Acceleration)**
   The ARM Cortex-A9 manages transfer descriptors and memory buffers, dispatching raw blocks to FPGA hardware accelerators over an AXI4 interconnect.

### Algorithms Evaluated
- **Compression**: Run-Length Encoding (RLE) and simplified LZ4/LZSS with sliding window.
- **Encryption**: AES-128 in Counter Mode (AES-CTR) and ChaCha20 stream cipher (ARX).
- **Test Payloads**: Injected via SPI from an ESP32 micro-controller across 3 entropy profiles (High Redundancy, Pseudo-Random, Telemetry) in block sizes from 64 Bytes to 64 Kilobytes.

---

## 2. Repository Layout

```
.
├── .agents/                    # Autonomous agent framework (skills, hooks, manifest)
├── cora7z/
│   └── app/
│       ├── hw/                 # Hardware RTL, testbenches, Vivado scripts
│       │   ├── src/            # Synthesizable VHDL-2008 sources & INTERFACES.md
│       │   ├── test/           # VUnit self-checking testbenches (tb_*.vhdl)
│       │   ├── scripts/        # Non-interactive Vivado Tcl automation scripts
│       │   ├── utils/          # Cora Z7-10 XDC physical pin constraints
│       │   ├── waves/          # GTKWave visualization configurations
│       │   ├── Makefile        # Simulation harness (make test, make view)
│       │   └── run.py          # VUnit entry point
│       ├── sw/                 # Software & firmware (Vitis 2026.1 unified flow)
│       │   ├── src/            # Bare-metal C sources (RLE, LZ4, AES, ChaCha, PMU)
│       │   └── scripts/        # Python automation scripts for Vitis CLI
│       └── test_results/       # Experimental measurement summaries & plots
├── docs/                       # Datasheets, schematics, diagrams, final report
│   ├── cora7z/                 # Cora Z7 Reference Manual, UG585, Schematic
│   ├── diagrams/               # System architecture block diagrams (.png/.jpg)
│   └── report/                 # Course final technical report (.pdf)
├── esp32/                      # ESP32 synthetic data injector firmware
├── utils/
│   ├── memory/                 # Technical memory between task iterations
│   │   ├── INDEX.md            # Entry point for active modules and handoffs
│   │   ├── modules/            # Per-core digests and source SHA-256 hashes
│   │   ├── handoff/            # Inter-iteration task status
│   │   ├── decisions.md        # Architecture Decision Records (ADR)
│   │   └── lessons.md          # Tool quirks and solutions
│   ├── plan/                   # Course deliverable project management
│   │   ├── Cronograma_e_Tarefas.csv # Schedule and task status
│   │   ├── Matriz_de_Testes_e_Métricas.csv # 12-row benchmark test matrix
│   │   ├── Checklist_de_Entregaveis.csv # Deliverable compliance checklist
│   │   ├── Riscos_e_Bloqueios.csv # Risk management log
│   │   └── STATUS.md           # Generated status report
│   └── TEMA.md                 # Detailed project requirements and specification
├── GEMINI.md                   # Workspace operating rules and invariants
├── Makefile                    # Top-level entry points
└── requirements.txt            # Python dependencies (vunit-hdl)
```

---

## 3. Toolchain & Setup Requirements

The project uses Ubuntu Linux with:
- **Xilinx Vivado & Vitis 2026.1**: Installed at `/home/luis/Xilinx/2026.1` (loaded via `.agents/env.sh`).
- **GHDL 7.0.0-dev**: Open-source VHDL simulator for unit tests.
- **Python 3**: With `vunit-hdl` installed in a local `.venv`.
- **GTKWave**: Waveform viewer.

### Quick Start: Simulation Flow

1. Set up the Python virtual environment:
   ```bash
   make -C cora7z/app/hw venv
   ```

2. Run the unit test suite:
   ```bash
   make -C cora7z/app/hw test
   ```

3. Run filtered simulation (e.g. for `smoke_counter`):
   ```bash
   make -C cora7z/app/hw test TB=smoke_counter
   ```

4. Open simulation waveforms in GTKWave:
   ```bash
   make -C cora7z/app/hw view TB=smoke_counter
   ```

---

## 4. Hardware Verification & Build Flow

To run the static linting and simulation verification gates:
```bash
source .agents/env.sh
TASK_ID=2.1 bash .agents/hooks/vhdl-lint.sh
TASK_ID=2.1 bash .agents/hooks/vhdl-sim-gate.sh
```

To run Vivado implementation and hardware export in batch mode:
```bash
TASK_ID=3.5 bash .agents/hooks/vivado-gate.sh
```

---

## 5. Course Deliverables Compliance

This repository conforms to the requirements defined in `utils/Projeto Final.pdf` and tracked in `utils/plan/Checklist_de_Entregaveis.csv`:
- Synthesizable VHDL-2008 sources (`.vhdl`) with VUnit testbenches.
- Bare-metal C/C++ firmware with ARM PMU cycle instrumentation.
- System block diagrams and technical documentation.
- Measured experimental metrics across all 12 combinations of the evaluation matrix.
