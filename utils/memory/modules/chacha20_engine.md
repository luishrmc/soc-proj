---
module: chacha20_engine
status: verified
sources:
  - cora7z/app/hw/src/chacha20_engine.vhdl sha256=e581f16b9a252ca90d8bb41d432543923420a34578a745626972150ed8581838
  - cora7z/app/hw/test/tb_chacha20_engine.vhdl sha256=251300ade853fe8522b3e70f9d6d38d6ab66b7d087fa6220b05ce11f8d3b19ac
  - docs/CHACHA20_ALGORITHM.md sha256=743d46a665adaf53b8ad121036164e2c5a4914497b71e8b88a4b85429dd23e8d
gates_passed: [vhdl-lint, vhdl-sim]
---

# ChaCha20 Stream Cipher Engine Digest

## 1. Module Overview
- **Function**: Hardware cryptographic coprocessor implementing ChaCha20 stream cipher per IETF RFC 8439.
- **Clock Domain**: 100 MHz (`aclk` driven by PS7 `FCLK_CLK1`).
- **Reset**: Active-low synchronous reset (`aresetn`).
- **Throughput**: 20 clock cycles per 64-byte block (320 MB/s @ 100 MHz line rate).

## 2. Bus Interfaces & Addresses
- **AXI4-Lite Slave (`s_axi_lite`)**:
  - Base Address: `0x43C30000` (mapped via `axi_interconnect_0/M05_AXI`).
  - Standard CSRs: `0x00 CONTROL`, `0x04 STATUS`, `0x08 SRC_LEN`, `0x0C DST_LEN`, `0x10 CYCLE_COUNT`.
  - Specific CSRs: `0x14-0x30 KEY_0..7` (256-bit key), `0x34-0x3C NONCE_0..2` (96-bit nonce), `0x40 BLOCK_COUNTER`.
- **AXI4-Stream Interfaces**:
  - Ingress: `s_axis_tdata` (32-bit), `s_axis_tkeep`, `s_axis_tvalid`, `s_axis_tready`, `s_axis_tlast`.
  - Egress: `m_axis_tdata` (32-bit), `m_axis_tkeep`, `m_axis_tvalid`, `m_axis_tready`, `m_axis_tlast`.
- **Interrupt Output (`irq_o`)**:
  - Connected to `xlconcat_0/In6` -> `processing_system7_0/IRQ_F2P`.

## 3. Memory & Resource Decoupling (ADR-012)
- Zero large inferred RAM arrays inside RTL.
- Streaming data buffering connected to standard `axis_data_fifo` in Vivado Block Design.
- Compact 4 parallel Quarter-Round ALUs with 32-bit ARX datapaths.

## 4. Verification & Gates
- **Static Lint**: `vhdl-lint` PASS (0 errors, 0 warnings).
- **VUnit Testbench**: `tb_chacha20_engine.vhdl` (4/4 tests PASS: CSR access, IETF RFC 8439 Section 2.3.2 golden keystream, backpressure, soft reset).
