---
module: lz4_engine
status: verified
sources:
  - cora7z/app/hw/src/lz4_engine.vhdl sha256=52955bd0844c9571cb917ccd4709ab7e87195f809ef55a8379aecd7b7c04565f
  - cora7z/app/hw/test/tb_lz4_engine.vhdl sha256=c10d565661105c3de889c073ba9cdbc303b3284a9588ee4a90dd1ff38b16c9ae
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
- Circular history buffer: `c_window_size = 64` bytes; Hash table: `c_hash_size = 32` entries (compact LUT budget per ADR-012).

## 4. Verification & Gates
- Static Lint: Clean (no GHDL warnings with `-Wall -Wno-hide`).
- Self-checking Testbench: `tb_lz4_engine.vhdl` (5 test scenarios covering CSRs, pure literals, 4-byte match detection, structured streams, backpressure).
- Vivado Block Design: Instantiated and validated cleanly.
