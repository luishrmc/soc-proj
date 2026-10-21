# Decision log (ADR, append-only)

Format: `ADR-NNN | date | task | decision | reason`. Never edit past entries. To change a decision, append a new one that supersedes it.

## ADR-001 | 2026-10-17 | setup | VHDL files use the `.vhdl` extension, testbenches are `tb_<name>.vhdl`
Reason: the user chose the reference setup's extension. The course deliverable table says `.vhd` as a format label, and `.vhdl` is the same language, so the deliverable check accepts both.

## ADR-002 | 2026-10-17 | setup | Simulation runs through `make -C cora7z/app/hw test` (VUnit + GHDL, venv at repo root)
Reason: mirrors `exercises/slides/corez7` (Makefile drives compilation and simulation). `requirements.txt` pins the dependency so any machine reproduces it with `make venv`.

## ADR-003 | 2026-10-17 | setup | Workspace layout: board project under `cora7z/app/{hw,sw}`, ESP32 injector under `esp32/`, PDFs under `docs/`
Reason: the user reorganized the tree before implementation. The ESP32 program is out of scope for now.

## ADR-004 | 2026-10-17 | setup | Vivado runs script-first (Tcl regenerates the project). Only scripts, XDC and sources are versioned
Reason: reproducibility on other computers and readable diffs. Generated Vivado/Vitis trees are ignored by `.gitignore`.

## ADR-005 | 2026-10-17 | setup | The `.xsa` file is the interface between the Vivado side and the Vitis side
Reason: each tool has its own agent (vivado-integrator-agent, firmware-agent). The XSA hash is recorded in `INTERFACES.md`.

## ADR-006 | 2026-10-17 | setup | All code, comments and agent-facing documents are in English. Plan CSV values stay in Portuguese
Reason: user requirement. The CSVs are part of the course deliverable.

## ADR-007 | 2026-10-17 | setup | Toolchain root is `$HOME/Xilinx/2026.1`, loaded by `.agents/env.sh`, never through the global PATH
Reason: Vivado/Vitis/ARM GCC are installed but not on PATH.

## ADR-008 | 2026-10-18 | 1.3 | Standardized AXI4-Lite memory map and registers in INTERFACES.md
Reason: Task 1.3 formalizes the SoC architecture. Peripherals (`dma_controller`, `rle_engine`, `lz4_engine`, `aes_ctr_engine`, `chacha20_engine`, `spi_ingest_engine`) are assigned collision-free 4 KB / 64 KB ranges verified by `address-map-check.py`. Standard CSRs and crypto-specific registers are locked.

## ADR-009 | 2026-10-18 | 1.3 | Extended manifest.json write globs to include docs/** for orchestrator and doc-agent
Reason: System architecture specifications and diagrams reside under `docs/`. Manifest is updated to allow orchestrator and doc agents to maintain top-level documentation.

## ADR-010 | 2026-10-18 | process | Dual-mode Vivado GUI / CLI collaboration and per-task planning in plan/<task_id>/task.md
Reason: Per reference corez7 setup, Vivado Block Design GUI is heavily utilized for SoC integration. To maximize synergy, the AI creates plan/<task_id>/task.md for each task, specifying CLI work (RTL authoring, VUnit verification, linting) alongside Vivado GUI work (BD module referencing, net wiring, Tcl console snippets) and detailing reusable interface contracts (common SPI ingress frontend and modular acceleration cores).

## ADR-011 | 2026-10-18 | process | Mandatory automated synthesis-through-bitstream verification loop
Reason: Explicit user directive. To guarantee that every hardware development iteration produces a functioning, synthesizable, and routable bitstream within the Zynq-7010 device resource budget (17,600 LUTs, 35,200 FFs, 60 BRAMs) without CPU bus stalls on M_AXI_GP0, every task modifying PL logic must execute automated Tcl scripts via `run_vivado.sh` to update Block Design cell references, run synthesis (`synth_1`), implementation (`impl_1`), generate `write_bitstream`, export the `.xsa` with `-include_bit`, and synchronize the Vitis software workspace.

## ADR-012 | 2026-10-18 | architecture | Unify SPI ingestion on Block Design axi_quad_spi and enforce visual memory IP integration in BD over RTL inference
Reason: Explicit user directive. Creating a custom discrete spi_receiver in RTL duplicates the existing axi_quad_spi_0 (0x41E00000) LogiCORE IP in the Block Design, causing pin conflicts on the Cora Z7 shield header J1 (G20, T10, V15, F16). Therefore, axi_quad_spi_0 in the Block Design is the sole authoritative SPI ingress interface. Furthermore, large memory buffers, sliding windows, and FIFOs must NOT be inferred as large internal arrays in VHDL (which causes combinatorial LUT multiplexer explosion); instead, memory and FIFO elements must be instantiated as explicit standard Xilinx IP blocks (blk_mem_gen, axis_data_fifo) directly in the Vivado Block Design and visually wired to RTL cores via standard BRAM or AXI4-Stream interfaces.

## ADR-013 | 2026-10-19 | plan | Formalize advance completion of Phase 3 and Task 4.4 in project schedule
Reason: The automated Block Design integration and bitstream verification loops (ADR-011, ADR-012) executed during Phase 2 bringup already completed PS7 configuration (3.1), AXI IP encapsulation (3.2), bus interconnect and address mapping (3.3), XDC constraints (3.4), and clean bitstream / XSA export (3.5) with 46% LUT utilization and 0 DRC errors. Additionally, ARM PMU CP15 instrumentation and calibration routines (4.4) were authored and validated in the baseline firmware. Formally synchronizing Cronograma_e_Tarefas.csv, STATUS.md, Checklist_de_Entregaveis.csv, and resolving open risks R1, R2, R3 aligns the roadmap with reality and opens Tasks 4.1 and 4.2 for active development.

## ADR-014 | 2026-10-19 | architecture | Multi-Accelerator Stream Multiplexing and Timing Closure via Pipelined Engines
Reason: Resolving findings from the pre-Phase 5 audit: (1) Added `axis_accel_mux.vhdl` (@ `0x43C40000`) to dynamically route AXI DMA MM2S and S2MM streams to any of the 4 accelerator engines with automatic `busy_i` detection; (2) Expanded DMA buffer descriptor length width to 23 bits (`0x17`) enabling up to 8 MB contiguous transfers; (3) Refactored `lz4_engine.vhdl` into a sequential streaming packer, dropping LUT utilization from 18,591 to 11,906 (67.65% of Zynq-7010); (4) Pipelined AES-128 key expansion into 10 sequential cycles; (5) Decomposed ChaCha20 quarter-rounds into 2 half-rounds over 2 cycles (`chacha_qr_half1`/`chacha_qr_half2`), closing timing at 100 MHz with positive setup slack ($WNS = +0.207$ ns).

## ADR-015 | 2026-10-19 | architecture | LZ4 Literal Buffer Bounding, PL Stream Chaining, and Deliverable Portability
Reason: Meta-analysis of external audits identified 4 high-priority technical debts: (1) Fixed intermediate literal flush in `lz4_engine.vhdl` and underflow in `lz4_simple.c`, bounded `lit_buf_r` to 64 bytes with deterministic hardware overflow protection (`reg_status_r(2) <= '1'`), eliminating 8,192 flip-flops / 1024:1 mux logic, achieving clean timing closure ($WNS = +0.330$ ns, LUTs: 12,709 / 17,600 = 72.2%); (2) Implemented hardware stream chaining routes `0x5..0x8` in `axis_accel_mux.vhdl` (`Compressor -> Cipher`) and distinct PMU / cycle paths in `pipeline_mgr.c`; (3) Replaced hardcoded host user home paths with `$::env(HOME)` across all Vivado Tcl scripts and docs, achieving 100% compliance in `deliverable-audit.sh`.

## ADR-016 | 2026-10-20 | integration | AXI Quad SPI Slave Framing Fix (SPISEL) and PS EMIO Autonomous Hardware Trigger
Reason: Hardware audit of SPI communication failure between ESP32 injector and Cora Z7 identified two critical gaps: (1) In Vivado Block Design, using the Digilent `shield_spi` board interface tied `axi_quad_spi_0/spisel` permanently to `'1'`, preventing the LogiCORE core from ever recognizing itself as selected in slave mode. Converted `axi_quad_spi_0` to discrete ports (`spi_sck_i`, `spi_mosi_i`, `spi_miso_o`, `spi_ss_i`) and connected `spi_ss_i` (`F16`) to both `ss_i(0)` and `spisel` with internal `PULLUP`. (2) To eliminate manual button/wire pressing on ESP32 GPIO 32, enabled PS EMIO GPIO (`PCW_EN_EMIO_GPIO`) on Cortex-A9, sliced `GPIO_O[0]` to PMOD JA Pin 1 (`Y18`), and implemented autonomous 30 ms active-low trigger pulses in `main.c`. (3) Configured ESP32 SPI master in `SPI_DEVICE_HALFDUPLEX` with `.cs_ena_pretrans = 2` and `.cs_ena_posttrans = 2` with static DMA buffers, achieving 100% CRC-valid streaming across all 4 payload profiles.


