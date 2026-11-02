---
module: pipeline_mgr
status: verified
sources:
  - cora7z/app/sw/src/pipeline_mgr.c sha256=e86285545f0be533b84cc41b4ac1015469dfd4ebe4389b5c138c46749bd894af
  - cora7z/app/sw/src/pipeline_mgr.h sha256=18e7b38360cb9048ddeb3a0d284ebe29684444cdb0ab164c326ed4dae832a691
gates_passed: [c-lint, vitis-build, elf-link]
---

# Hybrid Pipeline Manager & Offload Driver Digest

## 1. Overview
- **Function**: Bare-metal Cortex-A9 orchestrator for 4-scenario telemetry pipeline (Compress-then-Encrypt).
- **Architecture**: Decoupled Dual-Port BRAM memory buffers (2 KB Input, 2 KB Output per accelerator) over `M_AXI_GP0`.
- **Instrumentation**: Dual-domain timing via ARM Cortex-A9 PMU cycle counter (`PMCCNTR`) and PL 32-bit hardware cycle counters.

## 2. Memory Map & Peripheral Bindings
- `LZSS_ACCEL_BASE_ADDR`: `0x40000000`
  - Control/Status CSRs: `0x40000000` - `0x40000010` (START, STATUS, IN_LEN, OUT_LEN, CYCLES)
  - Input BRAM: `0x40000800` (2048 bytes)
  - Output BRAM: `0x40001000` (2048 bytes)
- `AES_ACCEL_BASE_ADDR`: `0x40010000`
  - Control/Status CSRs: `0x40010000` - `0x40010010`
  - Input BRAM: `0x40010800` (2048 bytes)
  - Output BRAM: `0x40011000` (2048 bytes)

## 3. Four Execution Scenarios
- **Scenario 1 (SW/SW)**: C11 Heatshrink LZSS + NIST AES-128-CTR in Cortex-A9 RAM.
- **Scenario 2 (HW/SW)**: Hardware LZSS BRAM coprocessor + Software AES-128-CTR.
- **Scenario 3 (SW/HW)**: Software Heatshrink LZSS + Hardware AES-128-CTR BRAM coprocessor.
- **Scenario 4 (HW/HW)**: Hardware LZSS + Hardware AES-128-CTR full coprocessor offload.

## 4. Verification & Validation
- Verified bit-exact parity across all 4 scenarios on Cora Z7 hardware target.
- Robust timeout handling (100,000 cycles), bus fault prevention via `is_pl_programmed()`.
- Zero dynamic allocation (`malloc`/`free`), MISRA-aligned deterministic staging buffers.
