---
module: lz4_engine
status: verified
sources:
  - cora7z/app/hw/src/lz4_engine.vhdl sha256=2311f5d5aa4f56ba09975454652d75bc5658feaab353008f12bcad64851a4b78
  - cora7z/app/hw/test/tb_lz4_engine.vhdl sha256=4daa9639b04063136dfc81718e4108996a7b4f1a71819631502ae0109c338709
  - docs/LZ4_ALGORITHM.md sha256=63726bf5a6ab3d5fc2167842c3ab3f106bac43d1afb2bf2c16aa41151730e2b4
gates_passed: [vhdl-lint, vhdl-sim, vivado-bd]
---

# LZ4 Compression Engine Digest

## 1. Module Overview
- **Function**: Hardware compression accelerator implementing simplified LZ4 sliding window compression.
- **Clock Domain**: 100 MHz (`aclk` driven by PS7 `FCLK_CLK1`).
- **Reset**: Active-low synchronous reset (`aresetn` driven by `rst_ps7_100M/peripheral_aresetn`).

## 2. Bus Interfaces & Connections
- **AXI4-Lite Slave (`s_axi_lite`)**:
  - Base Address: `0x43C10000` (mapped via `axi_interconnect_0/M03_AXI`).
  - CSRs: `0x00 CONTROL`, `0x04 STATUS`, `0x08 SRC_LEN`, `0x0C DST_LEN`, `0x10 CYCLE_COUNT`.
- **AXI4-Stream Slave (`s_axis`)**:
  - Ingress width: 32 bits (`s_axis_tdata`, `s_axis_tkeep`, `s_axis_tvalid`, `s_axis_tready`, `s_axis_tlast`).
- **AXI4-Stream Master (`m_axis`)**:
  - Egress width: 32 bits (`m_axis_tdata`, `m_axis_tkeep`, `m_axis_tvalid`, `m_axis_tready`, `m_axis_tlast`).
- **Interrupt Output (`irq_o`)**:
  - Connected to: `xlconcat_0/In4` -> `processing_system7_0/IRQ_F2P`.

## 3. Compression Token & Sequence Format
- Sequence Token: 1 byte `[Literal Length (4 bits) | Match Length - 4 (4 bits)]`.
- Followed by `Literal Length` raw bytes.
- Followed by 16-bit little-endian Match Offset (`offset[7:0]`, `offset[15:8]`).
- Trailing literals sequence: emitted on end of block without match offset.
- Circular history buffer: 2048 bytes; Hash table: 1024 entries.

## 4. Verification & Gates
- Static Lint: Clean (no GHDL warnings with `-Wall -Wno-hide`).
- Self-checking Testbench: `tb_lz4_engine.vhdl` (5 test scenarios covering CSRs, pure literals, 4-byte match detection, structured streams, backpressure).
- Vivado Block Design: Instantiated and validated cleanly.
