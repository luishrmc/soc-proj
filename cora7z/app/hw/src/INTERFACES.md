# Hardware / Software Interfaces Specification

This document defines the formal architectural contracts between the Programmable Logic (PL), the Processing System (ARM Cortex-A9 PS), and the external ESP32 SPI data injector on the Digilent Cora Z7-10 platform (`xc7z010clg400-1`).

---

## 1. External SPI Ingestion Bus (ESP32 -> Cora Z7 PL)

### 1.1 Physical Pin Allocation (Arduino / ChipKIT Shield Header J1)
All external SPI signals route through Bank 34 and Bank 35 with 3.3V LVCMOS voltage levels (`IOSTANDARD LVCMOS33`) and 200 Ω series damping resistors on board:

| Signal Name | FPGA Pin | Bank | Direction | Drive / Slew | Description |
|---|---|---|---|---|---|
| `spi_sclk_i` | `G20` | 35 | Input | - | SPI Clock input from ESP32 master (Mode 0, up to 25 MHz) |
| `spi_mosi_i` | `T10` | 34 | Input | - | Master-Out Slave-In serial data from ESP32 |
| `spi_miso_o` | `V15` | 34 | Output | 8mA, SLOW | Master-In Slave-Out serial data to ESP32 (status/loopback) |
| `spi_cs_n_i` | `F16` | 35 | Input | - | Active-Low Slave Select (framing delineator) |

### 1.2 SPI Physical Layer Protocol
- **SPI Mode**: Mode 0 (`CPOL = 0`, `CPHA = 0`).
  - Serial clock idles low.
  - Data is driven on falling edge of `spi_sclk_i` and sampled on rising edge of `spi_sclk_i`.
- **Clock Domain Crossing (CDC)**:
  - `spi_sclk_i`, `spi_mosi_i`, and `spi_cs_n_i` are treated as asynchronous inputs.
  - In PL, each input passes through an explicit 2-stage DFF synchronizer clocked by `clk_accel` (100 MHz) with edge-detection logic.
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

All accelerator cores and control endpoints instantiate an AXI4-Lite slave interface. All registers are 32-bit wide, aligned on 4-byte boundaries, and clocked by `s_axi_aclk` (`FCLK_CLK0` @ 50 MHz).

### 2.1 Peripheral Base Address Allocation

| Peripheral | Base Address | High Address | Size | Description |
|---|---|---|---|---|
| `dma_controller` | `0x40400000` | `0x4040FFFF` | 64 KB | AXI Direct Memory Access (Simple DMA Mode) |
| `rle_engine` | `0x43C00000` | `0x43C00FFF` | 4 KB | RLE Compression Accelerator |
| `lz4_engine` | `0x43C10000` | `0x43C10FFF` | 4 KB | LZ4 Sliding Window Compression Accelerator |
| `aes_ctr_engine` | `0x43C20000` | `0x43C20FFF` | 4 KB | AES-128-CTR Symmetric Crypto Accelerator |
| `chacha20_engine` | `0x43C30000` | `0x43C30FFF` | 4 KB | ChaCha20 Stream Cipher Engine (RFC 8439) |
| `spi_ingest_engine` | `0x43C40000` | `0x43C40FFF` | 4 KB | SPI Ingest Buffer & Status Controller |

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

### 2.5 SPI Ingest Controller Registers (`0x43C40000`)

| Offset | Name | Type | Reset Value | Description |
|---|---|---|---|---|
| `0x00` | `SPI_CTRL` | R/W | `0x00000000` | Bit 0: `FIFO_RD_EN`, Bit 1: `FIFO_RST`, Bit 2: `IRQ_EN` |
| `0x04` | `SPI_STATUS` | RO | `0x00000001` | Bit 0: `RX_EMPTY`, Bit 1: `RX_FULL`, Bit 2: `FRAME_READY`, Bit 3: `CRC_ERR` |
| `0x08` | `FRAME_LEN` | RO | `0x00000000` | Byte length of most recently received valid frame |
| `0x0C` | `FRAME_TYPE` | RO | `0x00000000` | Frame type & flags byte of current packet |
| `0x10` | `FIFO_DATA` | RO | `0x00000000` | 32-bit data read port popping words from RX FIFO |
| `0x14` | `DROPPED_FRAMES` | RO | `0x00000000` | Cumulative count of frames rejected due to FIFO full |

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
- **SHA-256**: *(Pending Vivado synthesis and export in Phase 3)*
