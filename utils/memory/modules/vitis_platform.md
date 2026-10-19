---
module: vitis_platform
status: verified
sources:
  - cora7z/app/sw/scripts/build_sw.py sha256=17bb10d4f883148b8116f34955c0ca3ee8ca7b3bca2a80421663c17d4cd01911
  - cora7z/app/sw/src/main.c sha256=ee77e67fbb7d094397d76bebe7f768715d15deb24e7784116ba1851ce27a810b
  - cora7z/app/hw/scripts/export_hw_platform.tcl sha256=184668f0aae65f0cfcdc55dd2a5fb8c04ce33b470a57b2199ffdf928f38a02a4
gates_passed: [c-lint, vitis-build, elf-link]
---

# Vitis Hardware Platform & Cortex-A9 Firmware Digest

## 1. Platform Setup (`cora7z_platform`)
- Container: `cora7z/app/hw/vivado/cora7z_top.xsa` (PS7 + AXI DMA + Quad SPI + 4 Accelerators).
- Processing Unit: ARM Cortex-A9 Core 0 (`ps7_cortexa9_0`) @ 667 MHz.
- Operating System: Bare-metal standalone (`standalone_ps7_cortexa9_0`), GCC toolchain.

## 2. Peripheral Address Bindings (Synchronized with INTERFACES.md)
- `XPAR_AXI_DMA_0_BASEADDR`: `0x40400000` (AXI Direct Memory Access)
- `XPAR_AXI_QUAD_SPI_0_BASEADDR`: `0x41E00000` (AXI Quad SPI Slave)
- `XPAR_RLE_ENGINE_0_BASEADDR`: `0x43C00000` (RLE Engine CSR)
- `XPAR_LZ4_ENGINE_0_BASEADDR`: `0x43C10000` (LZ4 Engine CSR)
- `XPAR_AES_CTR_ENGINE_0_BASEADDR`: `0x43C20000` (AES-CTR Engine CSR)
- `XPAR_CHACHA20_ENGINE_0_BASEADDR`: `0x43C30000` (ChaCha20 Engine CSR)

## 3. Modular Reference Software Algorithms (Scenario 1: PS Puro)
- `rle.[ch]`: Lossless Run-Length Encoding/Decoding (2-byte tokens `[run_len, symbol]`).
- `lz4_simple.[ch]`: LZ4 block compression/decompression with 2048-entry hash table.
- `aes_ctr.[ch]`: NIST SP 800-38A AES-128-CTR with key schedule and 32-bit big-endian counter.
- `chacha20.[ch]`: IETF RFC 8439 20-round stream cipher (256-bit key, 96-bit nonce, 32-bit counter).
- `benchmark_ps.[ch]`: Cycle-accurate profiling via ARM PMU (`PMCCNTR`), 10-run stats ($\mu$, $\sigma$).
- Quality: MISRA-aligned C11, zero dynamic memory allocation, decoupled host-testable architecture.
- Executable: `cora7z/app/sw/vitis/cora7z_firmware/build/cora7z_firmware.elf`.
