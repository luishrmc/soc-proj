---
module: vitis_platform
status: verified
sources:
  - cora7z/app/sw/scripts/build_sw.py sha256=17bb10d4f883148b8116f34955c0ca3ee8ca7b3bca2a80421663c17d4cd01911
  - cora7z/app/sw/src/main.c sha256=10fa91c99b62342da4632ea8d0f755a6669da86c1c1b746fd3bcc4ece8e9f531
  - cora7z/app/hw/scripts/export_hw_platform.tcl sha256=184668f0aae65f0cfcdc55dd2a5fb8c04ce33b470a57b2199ffdf928f38a02a4
gates_passed: [vitis-build, elf-link]
---

# Vitis Hardware Platform & Baseline Firmware Digest

## 1. Platform Setup (`cora7z_platform`)
- Container: `cora7z/app/hw/vivado/cora7z_top.xsa` (exported with complete BD output products and wrapper).
- Processing Unit: ARM Cortex-A9 Core 0 (`ps7_cortexa9_0`) @ 667 MHz.
- Operating System: Bare-metal (`standalone`).
- BSP Components: `standalone`, `xiltimer`, `xilrsa`, `xilffs`, `libxil.a`.
- Header: `xparameters.h` automatically mapping all AXI peripherals.

## 2. Peripheral Address Bindings
- `XPAR_AXI_DMA_0_BASEADDR`: `0x40400000` (AXI Direct Memory Access)
- `XPAR_AXI_QUAD_SPI_0_BASEADDR`: `0x41E00000` (AXI Quad SPI Slave)
- `XPAR_RLE_ENGINE_0_BASEADDR`: `0x43C00000` (RLE Compression Engine CSR)
- `XPAR_LZ4_ENGINE_0_BASEADDR`: `0x43C10000` (LZ4 Compression Engine CSR)

## 3. Baseline Firmware Architecture (`cora7z_firmware`)
- Toolchain: `arm-none-eabi-gcc` 13.x via Vitis 2026.1 Unified CLI (`vitis -s`).
- Entry Point: `main()` in `cora7z/app/sw/src/main.c`.
- Hardware Profiling: Cortex-A9 PMU enabled via CP15 (`PMCCNTR`), calibrated overhead ~1-2 cycles.
- Diagnostics: Memory-mapped I/O status check for all instantiated IP cores with deterministic zero-allocation C11 code.
- Executable Binary: `cora7z/app/sw/vitis/cora7z_firmware/build/cora7z_firmware.elf` (archived to `out/vitis/task_1.4/cora7z_firmware.elf`).
