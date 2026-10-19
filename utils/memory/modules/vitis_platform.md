---
module: vitis_platform
status: verified
sources:
  - cora7z/app/sw/scripts/build_sw.py sha256=17bb10d4f883148b8116f34955c0ca3ee8ca7b3bca2a80421663c17d4cd01911
  - cora7z/app/sw/src/main.c sha256=d024bfa28609cfa07127e8888726e063b1a7c0aa5bb0df72fcec2aa60eef321f
  - cora7z/app/hw/scripts/export_hw_platform.tcl sha256=184668f0aae65f0cfcdc55dd2a5fb8c04ce33b470a57b2199ffdf928f38a02a4
gates_passed: [c-lint, vitis-build, elf-link]
---

# Vitis Hardware Platform & Cortex-A9 Firmware Digest

## 1. Platform Setup (`cora7z_platform`)
- Container: `cora7z/app/hw/vivado/cora7z_top.xsa` (PS7 + AXI DMA + Quad SPI + 4 Accelerators).
- Processing Unit: ARM Cortex-A9 Core 0 (`ps7_cortexa9_0`) @ 667 MHz, bare-metal standalone.

## 2. Peripheral Address Bindings (Synchronized with INTERFACES.md)
- `XPAR_AXI_DMA_0_BASEADDR`: `0x40400000` (AXI Direct Memory Access Simple Mode)
- `XPAR_AXI_QUAD_SPI_0_BASEADDR`: `0x41E00000` (AXI Quad SPI Slave @ G20, T10, V15, F16)
- `XPAR_RLE_ENGINE_0_BASEADDR`: `0x43C00000` | `LZ4_ENGINE_0`: `0x43C10000`
- `XPAR_AES_CTR_ENGINE_0_BASEADDR`: `0x43C20000` | `CHACHA20_ENGINE_0`: `0x43C30000`

## 3. Modular Reference Software Algorithms (Scenario 1: PS Puro)
- `rle.[ch]`, `lz4_simple.[ch]`, `aes_ctr.[ch]`, `chacha20.[ch]`, `benchmark_ps.[ch]`.
- MISRA-aligned C11, zero dynamic memory allocation, ARM PMU profiling.

## 4. AXI Communication Drivers (PG021 / PG153 / ADR-012)
- `axi_accel_ctrl.[ch]`: AXI4-Lite control for RLE, LZ4, AES-CTR, and ChaCha20.
- `axi_dma_driver.[ch]`: AXI DMA 7.1 Simple Mode (MM2S & S2MM) with L1/L2 cache coherency.
- `axi_spi_receiver.[ch]`: AXI Quad SPI 3.2 slave mode, 256B FIFO drain, CRC-16-CCITT parser.
- `pipeline_mgr.[ch]`: Orchestrator connecting SPI ingress, PL accelerators, DMA, and PS.
- `axi_io.h`: Hardware MMIO abstraction (`Xil_In32`/`Xil_Out32`) and host mock engine.
- Executable: `cora7z/app/sw/vitis/cora7z_firmware/build/cora7z_firmware.elf`.
