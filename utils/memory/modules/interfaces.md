---
module: interfaces
status: verified
sources:
  - cora7z/app/hw/src/INTERFACES.md sha256=07382e2f74edbad710bbf3f7dc7ae695a556a8ce837b6fc3e644da23b1c7b622
  - docs/SYSTEM_ARCHITECTURE.md sha256=e675fd60f4b5a99a216719e7c22e968d6e0a23761e7f79ecb62a481cfb7bd990
gates_passed: [address-map]
---

# Interfaces & Architecture Digest

## 1. Physical External Bus (ESP32 SPI Ingest)
- Pins (Arduino Header J1): `SCK` (G20), `MOSI` (T10), `MISO` (V15), `CS_n` (F16). LVCMOS33.
- Mode: Mode 0 (CPOL=0, CPHA=0), up to 25 MHz.
- CDC: 2-stage synchronizer + edge detector into async FIFO.
- Frame Contract: `[0xAA, 0x55, TYPE, FLAGS, LEN_MSB..LSB, PAYLOAD, CRC16_MSB..LSB]`.

## 2. AXI4-Lite Address Map (50 MHz FCLK0)
- `dma_controller`: `0x40400000` - `0x4040FFFF` (64 KB)
- `rle_engine`: `0x43C00000` - `0x43C00FFF` (4 KB)
- `lz4_engine`: `0x43C10000` - `0x43C10FFF` (4 KB)
- `aes_ctr_engine`: `0x43C20000` - `0x43C20FFF` (4 KB)
- `chacha20_engine`: `0x43C30000` - `0x43C30FFF` (4 KB)
- `spi_ingest_engine`: `0x43C40000` - `0x43C40FFF` (4 KB)

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
