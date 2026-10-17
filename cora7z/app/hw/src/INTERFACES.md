# Hardware / Software Interfaces Specification

This document defines the formal architectural contracts between the Programmable Logic (PL), the Processing System (ARM Cortex-A9 PS), and the external ESP32 SPI data injector on the Digilent Cora Z7-10.

---

## 1. External SPI Ingestion Bus (ESP32 -> Cora Z7 PL)

Physical connection on Arduino/ChipKIT Shield Header (J1):
- `spi_sclk_i` (Pin `G20`, Bank 35): Serial clock up to 25 MHz (Mode 0: CPOL=0, CPHA=0).
- `spi_mosi_i` (Pin `T10`, Bank 34): Data from ESP32 master to Cora Z7 slave.
- `spi_miso_o` (Pin `V15`, Bank 34): Data from Cora Z7 slave to ESP32 master (for status / loopback).
- `spi_cs_n_i` (Pin `F16`, Bank 35): Active-low frame chip select.

### SPI Packet Frame Contract
- **Frame Structure**:
  1. Header: 4 bytes `[0xAA, 0x55, PAYLOAD_TYPE, FLAGS]`
     - `PAYLOAD_TYPE`: `0x01` (High Redundancy), `0x02` (Pseudo-Random), `0x03` (Telemetry)
  2. Length: 4 bytes Big-Endian `[PAYLOAD_LENGTH_31_0]` (64 to 65536 bytes)
  3. Payload: `PAYLOAD_LENGTH` bytes of data
  4. CRC-16 / Checksum: 2 bytes

---

## 2. AXI4-Lite Memory-Mapped Register Map (PS <-> PL Accelerators)

All registers are 32-bit wide, aligned on 4-byte boundaries.

| Peripheral | Base Address | High Address | Size | Description |
|---|---|---|---|---|
| `rle_engine` | `0x43C00000` | `0x43C00FFF` | 4 KB | RLE Compression Accelerator |
| `lz4_engine` | `0x43C10000` | `0x43C10FFF` | 4 KB | LZ4 Window Accelerator |
| `aes_ctr_engine` | `0x43C20000` | `0x43C20FFF` | 4 KB | AES-128 CTR Crypto Accelerator |
| `chacha20_engine` | `0x43C30000` | `0x43C30FFF` | 4 KB | ChaCha20 Stream Cipher Engine |
| `dma_controller` | `0x40400000` | `0x4040FFFF` | 64 KB | AXI DMA Engine (Scatter-Gather or Direct) |

### Standard Accelerator Register Layout (Offset from Peripheral Base)
- `0x00`: **CONTROL** (R/W)
  - `Bit 0`: `START` (Pulse 1 to initiate processing)
  - `Bit 1`: `RESET_CORE` (Active high synchronous soft reset)
  - `Bit 2`: `IRQ_EN` (Interrupt enable on completion)
- `0x04`: **STATUS** (RO)
  - `Bit 0`: `BUSY` (1 while core is processing)
  - `Bit 1`: `DONE` (Asserted upon completion, cleared on START)
  - `Bit 2`: `ERR` (Asserted if buffer overflow or invalid length)
- `0x08`: **SRC_LEN** (R/W): Input block length in bytes (32-bit).
- `0x0C`: **DST_LEN** (RO): Processed output length in bytes (32-bit).
- `0x10`: **CYCLE_COUNT** (RO): Hardware clock cycles consumed during active state.

---

## 3. Data Transfer Buffers (AXI-Stream / DMA)

- In **Scenario 2 (PL Only)**:
  SPI receiver FIFO directly feeds the compression engine via internal streaming bus (`tdata[7:0]`, `tvalid`, `tready`), which feeds the encryption engine, which buffers to an output FIFO.
- In **Scenario 3 (Hybrid)**:
  The ARM Cortex-A9 allocates buffers in DDR3 memory (`0x10000000` - `0x1FFFFFFF`).
  Blocks are dispatched to the accelerators via AXI DMA using AXI4-Stream interfaces (`s_axis_tdata[31:0]`, `m_axis_tdata[31:0]`).

---

## 4. Hardware Platform (.xsa) Record

- Target Device: `xc7z010clg400-1`
- Board: `digilentinc.com:cora-z7-10:part0:1.1`
- Exported Container: `cora7z/app/hw/vivado/cora7z_top.xsa`
- SHA-256: *(Pending Vivado synthesis and export in Phase 3)*
