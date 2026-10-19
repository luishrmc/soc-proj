# Hardware / Software Interfaces Specification

This document defines the formal architectural contracts between the Programmable Logic (PL), the Processing System (ARM Cortex-A9 PS), and the external ESP32 SPI data injector on the Digilent Cora Z7-10 platform (`xc7z010clg400-1`).

---

## 1. External SPI Ingestion Bus (ESP32 -> Cora Z7 PL)

### 1.1 Physical Pin Allocation (Arduino / ChipKIT Shield Header J1)
All external SPI signals route through Bank 34 and Bank 35 with 3.3V LVCMOS voltage levels (`IOSTANDARD LVCMOS33`) and 200 Ω series damping resistors on board:

| Signal Name | FPGA Pin | Bank | Direction | Drive / Slew | Description |
|---|---|---|---|---|---|
| `shield_spi_io0_io` (MOSI) | `T10` | 34 | Input | - | Master-Out Slave-In serial data from ESP32 |
| `shield_spi_io1_io` (MISO) | `V15` | 34 | Output | 8mA, SLOW | Master-In Slave-Out serial data to ESP32 (status/loopback) |
| `shield_spi_sck_io` (SCK) | `G20` | 35 | Input | - | SPI Clock input from ESP32 master (Mode 0, up to 25 MHz) |
| `shield_spi_ss_io` (CS_n) | `F16` | 35 | Input | - | Active-Low Slave Select (framing delineator) |

### 1.2 SPI Physical Layer Protocol
- **SPI Mode**: Mode 0 (`CPOL = 0`, `CPHA = 0`).
  - Serial clock idles low.
  - Data is driven on falling edge of `sck` and sampled on rising edge of `sck`.
- **Clock Domain Crossing (CDC) & Slave IP**:
  - In PL, physical SPI communication with ESP32 is handled exclusively through the `axi_quad_spi_0` LogiCORE IP (ADR-012) in slave mode with 256-byte FIFO.
  - CDC is managed internally within `axi_quad_spi_0` with `s_axi_aclk` on `FCLK_CLK0` (50 MHz) and `ext_spi_clk` on `FCLK_CLK1` (100 MHz) for high-speed sampling up to 25 MHz.
- **Maximum Bus Clock**: 25.0 MHz.

### 1.3 SPI Packet Frame Contract
Every frame transferred from the ESP32 to the Cora Z7 conforms to the following byte layout:

```
+---------------+-------------------+---------------+---------------+-------------------------+---------------+
| Preamble (2B) | Payload Type (1B) | Flags (1B)    | Length (4B)   | Payload Data (N Bytes)  | CRC-16 (2B)   |
| 0xAA, 0x55    | TYPE              | FLAGS         | Big-Endian    | [0 ... N-1]             | Big-Endian    |
+---------------+-------------------+---------------+---------------+-------------------------+---------------+
```

- **Preamble (2 Bytes)**: Fixed synchronization pattern `[0xAA, 0x55]`.
- **Payload Type (1 Byte)**:
  - `0x01` (`TYPE_REDUNDANT`): Highly repetitive pattern (test vectors for RLE and LZ4).
  - `0x02` (`TYPE_RANDOM`): Pseudo-random data ($H(X) \approx 8$ bits/byte, checks compression rejection).
  - `0x03` (`TYPE_TELEMETRY`): Mixed ASCII/binary sensor telemetry records (optimal for LZ4).
- **Flags (1 Byte)**:
  - `Bit 0`: `COMPRESS_EN` (1 = enable compression stage).
  - `Bit 1`: `ENCRYPT_EN` (1 = enable encryption stage).
  - `Bit 2`: `COMP_ALGO_SEL` (0 = RLE, 1 = LZ4).
  - `Bit 3`: `CRYPTO_ALGO_SEL` (0 = AES-128-CTR, 1 = ChaCha20).
  - `Bits [7:4]`: Reserved (must be 0).
- **Payload Length (4 Bytes)**: 32-bit unsigned integer, transmitted Big-Endian (valid range: 64 to 65,536 bytes).
- **Payload Data**: Variable byte array of length `N`.
- **Frame Check Sequence (2 Bytes)**: CRC-16-CCITT (polynomial `0x1021`, initial value `0xFFFF`), computed over the Header, Length, and Payload.

---

## 2. AXI4-Lite Memory-Mapped Register Map

All accelerator cores and control endpoints instantiate an AXI4-Lite slave interface. All registers are 32-bit wide, aligned on 4-byte boundaries.

### 2.1 Peripheral Base Address Allocation

| Peripheral | Base Address | High Address | Size | Description |
|---|---|---|---|---|
| `axi_dma_0` | `0x40400000` | `0x4040FFFF` | 64 KB | AXI Direct Memory Access (Simple DMA Mode, 50 MHz FCLK0) |
| `axi_quad_spi_0` | `0x41E00000` | `0x41E0FFFF` | 64 KB | AXI Quad SPI LogiCORE IP (Slave Mode, 50 MHz FCLK0 / 100 MHz FCLK1) |
| `rle_engine_0` | `0x43C00000` | `0x43C0FFFF` | 64 KB | RLE Compression Accelerator (100 MHz FCLK1, 4 KB CSR) |
| `lz4_engine_0` | `0x43C10000` | `0x43C1FFFF` | 64 KB | LZ4 Sliding Window Compression Accelerator (100 MHz FCLK1, 4 KB CSR) |
| `aes_ctr_engine_0` | `0x43C20000` | `0x43C2FFFF` | 64 KB | AES-128-CTR Symmetric Crypto Accelerator (100 MHz FCLK1, 4 KB CSR) |
| `chacha20_engine_0` | `0x43C30000` | `0x43C3FFFF` | 64 KB | ChaCha20 Stream Cipher Engine (RFC 8439, 100 MHz FCLK1, 4 KB CSR) |

---

### 2.2 Standard Accelerator Common Registers (Offsets 0x00 to 0x10)
Every computation core (`rle_engine`, `lz4_engine`, `aes_ctr_engine`, `chacha20_engine`) implements the following standardized register layout:

| Offset | Name | Type | Reset Value | Description |
|---|---|---|---|---|
| `0x00` | `CONTROL` | R/W | `0x00000000` | Control register (see bit definitions below) |
| `0x04` | `STATUS` | RO | `0x00000000` | Status register (see bit definitions below) |
| `0x08` | `SRC_LEN` | R/W | `0x00000000` | Input block length in bytes (32-bit integer) |
| `0x0C` | `DST_LEN` | RO | `0x00000000` | Processed output block length in bytes |
| `0x10` | `CYCLE_COUNT` | RO | `0x00000000` | Hardware latency: clock cycles active in current run |

#### `CONTROL` Register Bit Definitions (`0x00`):
- `Bit 0` (`START`): Pulse `1` to initiate processing of a new block. Self-clearing.
- `Bit 1` (`RESET_CORE`): Synchronous soft reset for datapath logic (clears FIFOs and state machines).
- `Bit 2` (`IRQ_EN`): Interrupt enable. If set, an interrupt pulse is generated upon completion.
- `Bits [31:3]`: Reserved.

#### `STATUS` Register Bit Definitions (`0x04`):
- `Bit 0` (`BUSY`): Asserted (`1`) while datapath is processing data.
- `Bit 1` (`DONE`): Asserted (`1`) when processing completes. Cleared when `START` is pulsed.
- `Bit 2` (`ERR`): Asserted (`1`) if an error occurred (e.g., input buffer overflow or length mismatch).
- `Bits [31:3]`: Reserved.

---

### 2.3 AES-128-CTR Core Specific Registers (`0x43C20000`)

| Offset | Name | Type | Reset Value | Description |
|---|---|---|---|---|
| `0x14` | `KEY_0` | R/W | `0x00000000` | AES Key bits [31:0] (Little-Endian word) |
| `0x18` | `KEY_1` | R/W | `0x00000000` | AES Key bits [63:32] |
| `0x1C` | `KEY_2` | R/W | `0x00000000` | AES Key bits [95:64] |
| `0x20` | `KEY_3` | R/W | `0x00000000` | AES Key bits [127:96] |
| `0x24` | `IV_0` | R/W | `0x00000000` | Initialization Vector / Nonce bits [31:0] |
| `0x28` | `IV_1` | R/W | `0x00000000` | Initialization Vector / Nonce bits [63:32] |
| `0x2C` | `IV_2` | R/W | `0x00000000` | Initialization Vector / Nonce bits [95:64] |
| `0x30` | `COUNTER_INIT` | R/W | `0x00000001` | Initial 32-bit counter value (bits [127:96] of block) |

---

### 2.4 ChaCha20 Core Specific Registers (`0x43C30000`)

| Offset | Name | Type | Reset Value | Description |
|---|---|---|---|---|
| `0x14` | `KEY_0` | R/W | `0x00000000` | 256-bit Key word 0 (bits [31:0]) |
| `0x18` | `KEY_1` | R/W | `0x00000000` | 256-bit Key word 1 (bits [63:32]) |
| `0x1C` | `KEY_2` | R/W | `0x00000000` | 256-bit Key word 2 (bits [95:64]) |
| `0x20` | `KEY_3` | R/W | `0x00000000` | 256-bit Key word 3 (bits [127:96]) |
| `0x24` | `KEY_4` | R/W | `0x00000000` | 256-bit Key word 4 (bits [159:128]) |
| `0x28` | `KEY_5` | R/W | `0x00000000` | 256-bit Key word 5 (bits [191:160]) |
| `0x2C` | `KEY_6` | R/W | `0x00000000` | 256-bit Key word 6 (bits [223:192]) |
| `0x30` | `KEY_7` | R/W | `0x00000000` | 256-bit Key word 7 (bits [255:224]) |
| `0x34` | `NONCE_0` | R/W | `0x00000000` | 96-bit Nonce word 0 (bits [31:0]) |
| `0x38` | `NONCE_1` | R/W | `0x00000000` | 96-bit Nonce word 1 (bits [63:32]) |
| `0x3C` | `NONCE_2` | R/W | `0x00000000` | 96-bit Nonce word 2 (bits [95:64]) |
| `0x40` | `BLOCK_COUNTER` | R/W | `0x00000001` | Initial block counter (starts at 1 per RFC 8439) |

---

### 2.5 AXI Quad SPI Slave Registers (`0x41E00000`, PG153)

| Offset | Name | Type | Reset Value | Description |
|---|---|---|---|---|
| `0x40` | `SRR` | WO | `0x00000000` | Software Reset Register (write `0x0000000A` to soft-reset core) |
| `0x60` | `SPICR` | R/W | `0x00000180` | SPI Control Register (bit 1: `SPE`, bit 5: `TX_RST`, bit 6: `RX_RST`, bit 8: `Master_Inhibit`) |
| `0x64` | `SPISR` | RO | `0x00000025` | SPI Status Register (bit 0: `RX_Empty`, bit 1: `RX_Full`, bit 2: `TX_Empty`, bit 3: `TX_Full`) |
| `0x68` | `DTR` | WO | `0x00000000` | Data Transmit Register (writes byte into TX FIFO) |
| `0x6C` | `DRR` | RO | `0x00000000` | Data Receive Register (reads byte from RX FIFO) |
| `0x78` | `RX_FIFO_OCY` | RO | `0x00000000` | RX FIFO Occupancy Register (occupancy count minus 1) |

---

### 2.6 Accelerator Stream Multiplexer Registers (`0x43C40000`)

| Offset | Name | Type | Reset Value | Description |
|---|---|---|---|---|
| `0x00` | `ROUTING_CTRL` | R/W | `0x00000000` | Stream Route: `0`=Auto by core BUSY, `1`=RLE, `2`=LZ4, `3`=AES-128-CTR, `4`=ChaCha20 |
| `0x04` | `ACTIVE_CORE` | RO | `0x00000000` | Currently active/routed accelerator core ID (bits [2:0]) |

---

## 3. AXI4-Stream Data Streaming Protocol

All high-bandwidth data transfers between the AXI DMA, FIFOs, and accelerator engines use the AXI4-Stream protocol (ARM IHI 0051A):

### 3.1 Signal Definition and Bit Widths
All stream interfaces operate in the `clk_accel` domain (100 MHz):

| Signal Name | Direction (Master -> Slave) | Width | Description |
|---|---|---|---|
| `axis_aclk` | Common | 1 bit | Synchronous stream clock (`clk_accel` @ 100 MHz) |
| `axis_aresetn` | Common | 1 bit | Synchronous active-low reset |
| `axis_tdata` | Master -> Slave | 32 bits | Stream data word (Little-Endian byte layout) |
| `axis_tvalid` | Master -> Slave | 1 bit | Asserted when Master presents valid data |
| `axis_tready` | Slave -> Master | 1 bit | Asserted when Slave can accept data |
| `axis_tlast` | Master -> Slave | 1 bit | Packet boundary flag: asserted on final word of block |
| `axis_tkeep` | Master -> Slave | 4 bits | Byte qualifiers: designates valid byte lanes on final word |

### 3.2 Handshake Invariants
- **No Cyclic Dependency**: A master must **never** wait for `tready` before asserting `tvalid`. Once `tvalid` is asserted, `tdata`, `tlast`, and `tkeep` must remain stable until the handshake completes (`tvalid AND tready = '1'`).
- **Packet Delimitation**: The `tlast` signal must be asserted on the exact final 32-bit beat of each data block.
- **Byte Alignment (`tkeep`)**:
  - `4'b1111` (`0xF`): All 4 bytes valid (`tdata[31:0]`).
  - `4'b0001` (`0x1`): 1 byte valid (`tdata[7:0]`).
  - `4'b0011` (`0x3`): 2 bytes valid (`tdata[15:0]`).
  - `4'b0111` (`0x7`): 3 bytes valid (`tdata[23:0]`).

---

## 4. Hardware Platform Record (.xsa)

- **Target Device**: `xc7z010clg400-1`
- **Board Part**: `digilentinc.com:cora-z7-10:part0:1.1`
- **Exported Container**: `cora7z/app/hw/vivado/cora7z_top.xsa`
- **SHA-256**: `513af306ce6810542219632e7745f65d3f05d900198017d2319c5aa7b9022346`
