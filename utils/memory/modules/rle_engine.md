---
module: rle_engine
status: verified
sources:
  - cora7z/app/hw/src/rle_engine.vhdl sha256=b666cdbc47eb88630defdb6fb4cf38111924d3962f8868a612c8b297a4867e55
  - cora7z/app/hw/test/tb_rle_engine.vhdl sha256=a9a6ab75fbabf254976715789444a6f73457402551552de847fcaf6faf6ce66e
  - docs/RLE_ALGORITHM.md sha256=4ca4d59ebf5c4a2e06505e5e93be84509c8b5dadce4c6663d0ee5c740a24c423
gates_passed: [vhdl-lint, vhdl-sim, vivado-bd]
---

# RLE Compression Engine Digest

## 1. Module Overview
- **Function**: Hardware compression engine executing Run-Length Encoding on incoming 8-bit stream bytes.
- **Clock Domain**: 100 MHz (`aclk` driven by PS7 `FCLK_CLK1`).
- **Reset**: Active-low synchronous reset (`aresetn` driven by `rst_ps7_100M/peripheral_aresetn`).

## 2. Bus Interfaces & Connections
- **AXI4-Lite Slave (`s_axi_lite`)**:
  - Base Address: `0x43C00000` (mapped via `axi_interconnect_0/M02_AXI`).
  - CSRs: `0x00 CONTROL`, `0x04 STATUS`, `0x08 SRC_LEN`, `0x0C DST_LEN`, `0x10 CYCLE_COUNT`.
- **AXI4-Stream Slave (`s_axis`)**:
  - Connected to: `axi_dma_0/M_AXIS_MM2S`.
  - Ingress width: 32 bits (`s_axis_tdata`, `s_axis_tkeep`, `s_axis_tvalid`, `s_axis_tready`, `s_axis_tlast`).
- **AXI4-Stream Master (`m_axis`)**:
  - Connected to: `axi_dma_0/S_AXIS_S2MM`.
  - Egress width: 32 bits (`m_axis_tdata`, `m_axis_tkeep`, `m_axis_tvalid`, `m_axis_tready`, `m_axis_tlast`).
- **Interrupt Output (`irq_o`)**:
  - Connected to: `xlconcat_0/In3` -> `processing_system7_0/IRQ_F2P`.

## 3. Compression Token Format
- 16-bit packed tuple: `[count (8 bits), symbol (8 bits)]`.
- Two 16-bit tuples are packed into each 32-bit AXI-Stream beat.
- Odd trailing tuple asserted with `tkeep = "0011"` and `tlast = '1'`.
- Run saturation threshold: 255. When count reaches 255, a tuple `[255, symbol]` is emitted and a new run begins.

## 4. Verification & Gates
- Static Lint: Clean (no GHDL warnings with `-Wall -Wno-hide`).
- Self-checking Testbench: `tb_rle_engine.vhdl` (5 test scenarios covering CSRs, high compression, multiple runs, run saturation, backpressure).
- Vivado Block Design: Instantiated and validated with exit code 0.
