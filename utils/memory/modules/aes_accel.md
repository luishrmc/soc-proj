---
module: aes_accel
status: verified
sources:
  - cora7z/app/hw/src/aes_accel.vhdl sha256=b554e67e85b84767af748bfe1b7590fa227ad485e647c4eedd761f6575ddfd09
  - cora7z/app/hw/test/tb_aes_accel.vhdl sha256=54a173d2fca8ff29c40501e0a37e53ffaa37f0c0fd1371c1a1115b5a696b22d0
gates_passed: [vhdl-lint, vhdl-sim, vivado-build]
---

# AES-128-CTR Dual-Port BRAM Accelerator Digest

## 1. Module Overview
- **Function**: Hardware cryptographic coprocessor implementing AES-128-CTR with native True Dual-Port Block RAM interfaces (Port B) adhering to ADR-012/ADR-017.
- **Clock Domain**: 100 MHz (`clk` driven by PS7 `FCLK_CLK1`).
- **Reset**: Active-low synchronous reset (`rst_n`).
- **Throughput**: 10 clock cycles per 128-bit block (160 MB/s raw cipher core rate).

## 2. Bus Interfaces & Memory Map
- **AXI4-Lite Slave CSR**: Base Address `0x43C10000`
  - `0x00`: CTRL (`bit 0`: START, `bit 1`: SOFT_RESET, `bit 2`: IRQ_EN)
  - `0x04`: STATUS (`bit 0`: BUSY, `bit 1`: DONE, `bit 2`: ERROR)
  - `0x08`: INPUT_LEN (Payload length in bytes, 1..2048)
  - `0x0C`: OUTPUT_LEN (Ciphertext length in bytes)
  - `0x10`: CYCLES (32-bit hardware execution cycle counter)
  - `0x14-0x20`: KEY_0..3 (128-bit key words)
  - `0x24-0x2C`: IV_0..2 (96-bit nonce words)
  - `0x30`: COUNTER_INIT (32-bit initial counter word)
- **Port B BRAM Interfaces**:
  - Input BRAM: `bram_in_addr` (11-bit), `bram_in_dout` (32-bit), `bram_in_en`
  - Output BRAM: `bram_out_addr` (11-bit), `bram_out_din` (32-bit), `bram_out_we` (4-bit), `bram_out_en`

## 3. Verification & Metrics
- VUnit testbench: `tb_aes_accel.vhdl` (CSR, NIST SP 800-38A vector over BRAM, soft reset).
- Vivado bitstream: zero timing violations ($WNS=+0.695$ ns, $WHS=+0.012$ ns).
