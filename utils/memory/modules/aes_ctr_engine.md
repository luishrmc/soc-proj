---
module: aes_ctr_engine
status: retired
sources: []
gates_passed: [vhdl-lint, vhdl-sim]
---

# AES-128-CTR Coprocessor Engine Digest

## 1. Module Overview
- **Function**: Hardware cryptographic coprocessor implementing AES-128 in Counter Mode (CTR) per NIST FIPS-197 and NIST SP 800-38A.
- **Clock Domain**: 100 MHz (`aclk` driven by PS7 `FCLK_CLK1`).
- **Reset**: Active-low synchronous reset (`aresetn`).
- **Throughput**: 10 clock cycles per 128-bit block (160 MB/s @ 100 MHz).

## 2. Bus Interfaces & Addresses
- **AXI4-Lite Slave (`s_axi_lite`)**:
  - Base Address: `0x43C20000` (mapped via `axi_interconnect_0/M04_AXI`).
  - Standard CSRs: `0x00 CONTROL`, `0x04 STATUS`, `0x08 SRC_LEN`, `0x0C DST_LEN`, `0x10 CYCLE_COUNT`.
  - Specific CSRs: `0x14-0x20 KEY_0..3`, `0x24-0x2C IV_0..2`, `0x30 COUNTER_INIT`.
- **AXI4-Stream Interfaces**:
  - Ingress: `s_axis_tdata` (32-bit), `s_axis_tkeep`, `s_axis_tvalid`, `s_axis_tready`, `s_axis_tlast`.
  - Egress: `m_axis_tdata` (32-bit), `m_axis_tkeep`, `m_axis_tvalid`, `m_axis_tready`, `m_axis_tlast`.
- **Interrupt Output (`irq_o`)**:
  - Connected to `xlconcat_0/In5` -> `processing_system7_0/IRQ_F2P`.

## 3. Memory & Resource Decoupling (ADR-012)
- Zero large inferred RAM arrays inside RTL.
- Streaming data buffering connected to standard `axis_data_fifo` in Vivado Block Design.
- Compact parallel S-Box logic for SubBytes.

## 4. Verification & Gates
- **Static Lint**: `vhdl-lint` PASS (0 errors, 0 warnings).
- **VUnit Testbench**: `tb_aes_ctr_engine.vhdl` (4/4 tests PASS: CSR access, NIST SP 800-38A golden vector, backpressure, soft reset).
