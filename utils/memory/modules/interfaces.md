---
module: interfaces
status: verified
sources:
  - cora7z/app/hw/src/INTERFACES.md sha256=1fa85e2751315d51e622075f3c8289cd9627d00a91250a455d8c63f3be7fb640
  - docs/SYSTEM_ARCHITECTURE.md sha256=e675fd60f4b5a99a216719e7c22e968d6e0a23761e7f79ecb62a481cfb7bd990
gates_passed: [address-map]
---

# Interfaces & Architecture Digest

## 1. Physical External Bus (ESP32 SPI Ingest via AXI Quad SPI)
- Pins (Dedicated SPI Header J7): `SCK` (G20, Pin 3), `MOSI` (T10, Pin 4), `MISO` (V15, Pin 1), `CS_n` (F16, Pin 5), `GND` (Pin 6). LVCMOS33.
- Mode: Mode 0 (CPOL=0, CPHA=0), up to 25 MHz via `axi_quad_spi_0` (256-byte FIFO, ADR-012).
- CDC: Handled internally by `axi_quad_spi_0` (`s_axi_aclk` 50 MHz, `ext_spi_clk` 100 MHz).
- Frame Contract: `[0xAA, 0x55, TYPE, FLAGS, LEN_MSB..LSB, PAYLOAD, CRC16_MSB..LSB]`.

## 2. AXI4-Lite Address Map (M_AXI_GP0)
- `axi_dma_0`: `0x40400000` - `0x4040FFFF` (64 KB, 50 MHz FCLK0)
- `axi_quad_spi_0`: `0x41E00000` - `0x41E0FFFF` (64 KB, 50 MHz FCLK0)
- `rle_engine_0`: `0x43C00000` - `0x43C0FFFF` (64 KB BD / 4 KB CSR, 100 MHz FCLK1)
- `lz4_engine_0`: `0x43C10000` - `0x43C1FFFF` (64 KB BD / 4 KB CSR, 100 MHz FCLK1)
- `aes_ctr_engine_0`: `0x43C20000` - `0x43C2FFFF` (64 KB BD / 4 KB CSR, 100 MHz FCLK1)
- `chacha20_engine_0`: `0x43C30000` - `0x43C3FFFF` (64 KB BD / 4 KB CSR, 100 MHz FCLK1)

## 3. Standard Accelerator CSR Layout
- `0x00`: `CONTROL` (bit 0: `START`, bit 1: `RESET_CORE`, bit 2: `IRQ_EN`)
- `0x04`: `STATUS` (bit 0: `BUSY`, bit 1: `DONE`, bit 2: `ERR`)
- `0x08`: `SRC_LEN` (Input length in bytes)
- `0x0C`: `DST_LEN` (Output length in bytes)
- `0x10`: `CYCLE_COUNT` (HW cycle counter)
- Crypto keys and nonces mapped from `0x14` onward.

## 4. AXI4-Stream Standard (100 MHz clk_accel)
- Width: 32-bit `tdata`, `tvalid`, `tready`, `tlast`, `tkeep[3:0]`.
- No cyclic dependence (`tvalid` unconditionally asserted when data ready).
- Simple DMA Direct Register mode (MM2S & S2MM) over `AXI_HP0`.
