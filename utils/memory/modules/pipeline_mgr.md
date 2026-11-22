---
module: pipeline_mgr
status: verified
sources:
  - cora7z/app/sw/src/pipeline/pipeline_mgr.c sha256=14c90e73c5df3a8ab1928ff4abde3795492d8e4d62721ae51e76af1a985a8629
  - cora7z/app/sw/src/pipeline/pipeline_mgr.h sha256=eac7b809b007e88375aa97623a1587566a97a5cd5b51a59b2f888cc235cd3ba6
gates_passed: [c-lint, vitis-build, elf-link]
---

# Hybrid Pipeline Manager & Offload Driver Digest

## 1. Overview
- **Function**: Bare-metal Cortex-A9 orchestrator for 4-scenario telemetry pipeline (Compress-then-Encrypt).
- **Architecture**: Decoupled Dual-Port BRAM memory buffers (2 KB Input, 2 KB Output per accelerator) over `M_AXI_GP0`.
- **Instrumentation**: Dual-domain timing via ARM Cortex-A9 PMU cycle counter (`PMCCNTR` @ `650 MHz` `XPAR_CPU_CORE_CLOCK_FREQ_HZ` with calibrated overhead subtraction via `pipeline_set_pmu_overhead()`) and PL 32-bit hardware cycle counters (`100 MHz`).

## 2. Memory Map & Peripheral Bindings
- **AXI4-Lite CSRs (`M_AXI_GP0`)**:
  - `LZSS_CSR_BASEADDR`: `0x43C00000` (`CONTROL`, `STATUS`, `INPUT_LEN`, `OUTPUT_LEN`, `CYCLES`)
  - `AES_CSR_BASEADDR`: `0x43C10000` (`CONTROL`, `STATUS`, `INPUT_LEN`, `OUTPUT_LEN`, `CYCLES`, `KEY0..3`, `IV0..2`, `CTR_INIT`)
- **Dual-Port BRAM Apertures (`axi_bram_ctrl` Port A)**:
  - `LZSS_BRAM_IN_BASEADDR`: `0x40000000` (8 KB block, 2048 B active capacity)
  - `LZSS_BRAM_OUT_BASEADDR`: `0x40002000` (8 KB block, 2048 B active capacity)
  - `AES_BRAM_IN_BASEADDR`: `0x40010000` (8 KB block, 2048 B active capacity)
  - `AES_BRAM_OUT_BASEADDR`: `0x40012000` (8 KB block, 2048 B active capacity)

## 3. Four Execution Scenarios
- **Scenario 1 (SW/SW)**: C11 Heatshrink LZSS + NIST AES-128-CTR in Cortex-A9 RAM.
- **Scenario 2 (HW/SW)**: Hardware LZSS BRAM coprocessor + Software AES-128-CTR.
- **Scenario 3 (SW/HW)**: Software Heatshrink LZSS + Hardware AES-128-CTR BRAM coprocessor.
- **Scenario 4 (HW/HW)**: Hardware LZSS + Hardware AES-128-CTR full coprocessor offload.

## 4. Verification & Validation
- Verified bit-exact parity across all 4 scenarios on Cora Z7 hardware target.
- Robust timeout handling (100,000 cycles), bus fault prevention via `is_pl_programmed()`.
- Zero dynamic allocation (`malloc`/`free`), MISRA-aligned deterministic staging buffers.
