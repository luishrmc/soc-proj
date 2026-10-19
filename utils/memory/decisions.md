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

## ADR-007 | 2026-10-17 | setup | Toolchain root is `/home/luis/Xilinx/2026.1`, loaded by `.agents/env.sh`, never through the global PATH
Reason: Vivado/Vitis/ARM GCC are installed but not on PATH.

## ADR-008 | 2026-10-18 | 1.3 | Standardized AXI4-Lite memory map and registers in INTERFACES.md
Reason: Task 1.3 formalizes the SoC architecture. Peripherals (`dma_controller`, `rle_engine`, `lz4_engine`, `aes_ctr_engine`, `chacha20_engine`, `spi_ingest_engine`) are assigned collision-free 4 KB / 64 KB ranges verified by `address-map-check.py`. Standard CSRs and crypto-specific registers are locked.

## ADR-009 | 2026-10-18 | 1.3 | Extended manifest.json write globs to include docs/** for orchestrator and doc-agent
Reason: System architecture specifications and diagrams reside under `docs/`. Manifest is updated to allow orchestrator and doc agents to maintain top-level documentation.

## ADR-010 | 2026-10-18 | process | Dual-mode Vivado GUI / CLI collaboration and per-task planning in plan/<task_id>/task.md
Reason: Per reference corez7 setup, Vivado Block Design GUI is heavily utilized for SoC integration. To maximize synergy, the AI creates plan/<task_id>/task.md for each task, specifying CLI work (RTL authoring, VUnit verification, linting) alongside Vivado GUI work (BD module referencing, net wiring, Tcl console snippets) and detailing reusable interface contracts (common SPI ingress frontend and modular acceleration cores).

## ADR-011 | 2026-10-18 | process | Mandatory automated synthesis-through-bitstream verification loop
Reason: Explicit user directive. To guarantee that every hardware development iteration produces a functioning, synthesizable, and routable bitstream within the Zynq-7010 device resource budget (17,600 LUTs, 35,200 FFs, 60 BRAMs) without CPU bus stalls on M_AXI_GP0, every task modifying PL logic must execute automated Tcl scripts via `run_vivado.sh` to update Block Design cell references, run synthesis (`synth_1`), implementation (`impl_1`), generate `write_bitstream`, export the `.xsa` with `-include_bit`, and synchronize the Vitis software workspace.



