# Technical Memory: Pre-Phase 5 System-Wide Audit & Hardware/Software Convergence

**Date**: 2026-10-19  
**Target Platform**: Digilent Cora Z7-10 (Xilinx Zynq-7010 SoC, `xc7z010clg400-1`)  
**Toolchain**: Vivado 2026.1 / Vitis 2026.1 Unified CLI & Python Flow  
**Status**: APPROVED FOR PHASE 5 (SPI Physical Link Bringup)

---

## 1. Executive Summary & Audit Scope

Prior to commencing Phase 5 (physical SPI link between the ESP32 synthetic data injector and the Cora Z7-10 header), a comprehensive, adversarial system audit was conducted across all workspace layers (`cora7z/app/hw/`, `cora7z/app/sw/`, `esp32/`, and `utils/memory/`).

The audit addressed 5 critical vectors:
1. **Axis 1 (Register Map & AXI Synchronization)**: Full consistency between `INTERFACES.md`, Vivado Block Design (`cora7z_top.bd`), Vitis BSP (`xparameters.h`), and C drivers (`axi_*.[ch]`).
2. **Axis 2 (Algorithmic Parity & Golden Vectors)**: Mathematical parity between VHDL-2008 RTL engines and C11 reference implementations (RLE, LZ4, AES-128-CTR, ChaCha20).
3. **Axis 3 (AXI DMA, SPI & Memory Coherency)**: Compliance with Xilinx PG021 (AXI DMA v7.1) and PG153 (AXI Quad SPI v3.2), cache L1/L2 management, deadlock prevention, and DEVCFG `is_pl_programmed()` bus fault protection.
4. **Axis 4 (Optimization & Redundancy Pruning)**: Removal of dead code, duplicate RAM buffers, eliminating inferred latches, and closing timing ($WNS \ge 0$) on the 100 MHz clock domain.
5. **Axis 5 (Technical Memory Hygiene)**: Updating SHA-256 source digests across `utils/memory/modules/` and adhering to manifest line limits.

---

## 2. Key Technical Findings & Resolutions

### 2.1 Multi-Accelerator AXI4-Stream Routing (`axis_accel_mux.vhdl`)
- **Problem**: `axi_dma_0` was hardwired to only one accelerator core at a time, preventing dynamic runtime selection between RLE, LZ4, AES-CTR, and ChaCha20.
- **Resolution**: Implemented `axis_accel_mux.vhdl` mapped to AXI4-Lite CSR base `0x43C40000`. The mux supports both automatic routing (monitoring `busy_i` from each accelerator) and manual software override. Exposed `busy_o` on all 4 accelerator engines to standardize the interface.

### 2.2 AXI DMA Buffer Expansion (`c_sg_length_width`)
- **Problem**: Default AXI DMA simple mode buffer descriptor length width was set to 14 bits (maximum transfer of 16 KB), which restricted full 64 KB block streaming.
- **Resolution**: Updated `axi_dma_0` in the Block Design with `CONFIG.c_sg_length_width {23}`, enabling direct DMA buffer allocations up to 8 MB.

### 2.3 FPGA Resource Budget Optimization (`lz4_engine.vhdl`)
- **Problem**: The original `lz4_engine.vhdl` inferred multi-port parallel shift registers with 15 simultaneous write ports in `out_queue_r`, consuming 6,578 LUTs. Total FPGA utilization reached 18,591 LUTs, exceeding the 17,600 LUT capacity of the XC7Z010.
- **Resolution**: Refactored `lz4_engine.vhdl` into a clean sequential byte/word packer datapath. Standalone resource utilization dropped to ~1,850 LUTs, reducing total chip utilization to 11,906 LUTs (67.65%), providing 32.35% headroom.

### 2.4 Timing Closure: AES-128-CTR Key Expansion (`aes_ctr_engine.vhdl`)
- **Problem**: Initial implementation unrolled all 40 words of AES key expansion into a single combinational state (`ST_EXPAND_KEYS`), resulting in 39 logic levels, 28.6 ns path delay, and a $WNS = -18.974$ ns violation on the 100 MHz clock (`clk_fpga_1`).
- **Resolution**: Refactored `ST_EXPAND_KEYS` to compute 4 round-key words per clock cycle over 10 sequential cycles (`key_exp_round_r` 1..10). Logic levels dropped from 39 to 3, with combinational delay falling to 2.2 ns.

### 2.5 Timing Closure: ChaCha20 Quarter-Round Pipelining (`chacha20_engine.vhdl`)
- **Problem**: `chacha_qr` chained 4 additions of 32 bits sequentially within a single clock cycle during `S_ROUNDS` (31 logic levels, 25 `CARRY4` carry-chain stages), yielding a 12.71 ns delay and a $WNS = -2.792$ ns violation.
- **Resolution**: Decomposed quarter-rounds into two half-rounds (`chacha_qr_half1` and `chacha_qr_half2`) executed across 2 clock cycles using register flag `round_half_r`. Carry-chain stages per cycle dropped from 32 to 16, path delay dropped below 5.8 ns, and timing closed cleanly with $WNS = +0.207$ ns.

### 2.6 Software Buffer Pruning & MMIO Modernization
- **Problem**: Redundant temporary buffers (`s_rx_temp`, `s_out_64b`, `s_out_1kb`) and obsolete duplicate MMIO macros existed in `cora7z/app/sw/src/`.
- **Resolution**: Pruned dead buffers and centralized MMIO accesses through `axi_io.h` with `is_pl_programmed()` sanity checks before any `M_AXI_GP0` operations.

---

## 3. Implementation & Verification Gate Results

### 3.1 Vivado Implementation & Timing Summary
- **Target Part**: Xilinx Zynq-7010 (`xc7z010clg400-1`, Digilent Cora Z7-10)
- **Slice LUTs**: 11,906 / 17,600 (67.65%)
- **Slice Registers**: 14,379 / 35,200 (40.85%)
- **Latches**: 0 (0.00%)
- **Timing Closure**:
  - $WNS = +0.207\text{ ns}$ (MET)
  - $TNS = 0.000\text{ ns}$ (MET)
  - $WHS = +0.019\text{ ns}$ (MET)
- **DRC / Critical Warnings**: 0 Errors, 0 Critical Warnings
- **Platform Export**: `cora7z/app/hw/vivado/cora7z_top.xsa` (SHA-256: `513af306ce6810542219632e7745f65d3f05d900198017d2319c5aa7b9022346`)

### 3.2 Automated Verification Matrix
- **`vhdl-lint.sh`**: PASS (5 core files checked)
- **`vhdl-sim-gate.sh` (VUnit + GHDL)**: PASS (23 of 23 testbenches passed in 1.6 s)
- **`c-lint.sh`**: PASS (20 C/H files validated with `-Wall -Wextra -Werror`)
- **Host Algorithm Golden Tests**: PASS (RLE, LZ4, NIST SP 800-38A, IETF RFC 8439)
- **Host AXI Driver Mock Tests**: PASS (DMA v7.1 simple mode, SPI receiver, Accel Mux, Pipeline Mgr)
- **Vitis 2026.1 Unified Build**: PASS (`cora7z_firmware.elf` compiled cleanly)
- **`memory-check.py`**: PASS (all module digests fresh and within line boundaries)

---

## 4. Final Verdict

All blocking issues identified during the pre-Phase 5 audit have been fully remediated. The hardware, software, and register contracts are synchronized and validated.

**VERDICT: APROVADO PARA FASE 5**
