---
module: lzss_accel
status: verified
sources:
  - cora7z/app/hw/src/lzss_accel.vhdl sha256=e13dbef2fbadb4e8d9f99b44529f7a67707778c40d0425371132065e0d4f28c6
  - cora7z/app/hw/test/tb_lzss_accel.vhdl sha256=9df2a85fcb698b56a1f81ddc43bd987f0d59c2f9dd1ca8d9ceebc99606f31f86
gates_passed: [vhdl-lint, vhdl-sim, vivado-build]
---

# LZSS Dual-Port BRAM Accelerator Digest

## 1. Module Overview
- **Function**: Hardware sliding-window dictionary compression coprocessor (Heatshrink-compatible, 256 B window, 16 B lookahead, 3 B min match, 8-token flag chunking).
- **Clock Domain**: 100 MHz (`clk` driven by PS7 `FCLK_CLK1`).
- **Reset**: Active-low synchronous reset (`rst_n`).
- **Throughput**: Dual-Port BRAM direct burst access, cycle counter latching upon completion.

## 2. Bus Interfaces & Memory Map
- **AXI4-Lite Slave CSR**: Base Address `0x43C00000`
  - `0x00`: CTRL (`bit 0`: START, `bit 1`: SOFT_RESET, `bit 2`: IRQ_EN)
  - `0x04`: STATUS (`bit 0`: BUSY, `bit 1`: DONE, `bit 2`: ERROR)
  - `0x08`: INPUT_LEN (Uncompressed payload length in bytes)
  - `0x0C`: OUTPUT_LEN (Compressed payload length in bytes)
  - `0x10`: CYCLES (32-bit hardware execution cycle counter)
- **Port B BRAM Interfaces**:
  - Input BRAM: `bram_in_addr` (11-bit), `bram_in_dout` (32-bit), `bram_in_en`
  - Output BRAM: `bram_out_addr` (11-bit), `bram_out_din` (32-bit), `bram_out_we` (4-bit), `bram_out_en`

## 3. Verification & Metrics
- VUnit testbench: `tb_lzss_accel.vhdl` (CSR, redundant compression, soft reset).
- Vivado bitstream: zero timing violations ($WNS=+0.695$ ns, $WHS=+0.012$ ns).
