# Autonomous SPI Telemetry Injector Harness
## ESP32-WROOM (ESP-IDF v6.1 @ 240 MHz)

This directory contains the firmware for the external **ESP32-WROOM** microcontroller test harness, acting as an autonomous SPI master streaming synthetic telemetry frames into the Cora Z7-10.

---

## 1. Module Overview & Operational Role

The ESP32 simulates an industrial sensor cluster or avionics telemetry unit operating in a decoupled environment:
* **Clock & Protocol:** Hardware SPI Master in **Mode 0** (CPOL=0, CPHA=0, MSB-First) operating at up to **25 MHz**.
* **Dynamic Payload Cycling:** Transmits realistic telemetry frames across standardized lengths: **64 B, 256 B, 512 B, and 1024 B**.
* **Integrity Guard:** Formats frames with synchronization preambles, monotonic sequence counters, CRC-16 CCITT checksums, and EOF delimiters.
* **Autonomous Handshake:** Listens on **GPIO 32** for active-low burst trigger pulses emitted by the Cora Z7 Processing System on **PMOD JA1** (Pin Y18), eliminating manual push-button triggers.

---

## 2. Telemetry Frame Wire Specification

Every frame transmitted over the physical SPI bus adheres to the following byte layout:

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       Preamble (0xA55A)       |          Sequence ID (31:16)  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|      Sequence ID (15:0)       |   Payload Length (Little-End) |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    Reserved Padding (0x0000)  |  Payload Byte 0 | Payload 1   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                 ... Dynamic Payload Bytes ...                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|      CRC-16 CCITT Checksum    | EOF Delim (0x5A)|
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

| Field Name | Offset | Size | Description |
| :--- | :---: | :---: | :--- |
| `preamble` | 0 | 2 bytes | Synchronization marker (`0xA55A`) |
| `seq_id` | 2 | 4 bytes | Monotonic packet counter [31:0] (prevents replay attacks) |
| `payload_len` | 6 | 2 bytes | Unsigned payload byte count (64, 256, 512, 1024) |
| `reserved_align`| 8 | 2 bytes | Padding to guarantee 32-bit word alignment on `payload` (offset 10) |
| `payload` | 10 | $N$ bytes | Synthetic floating-point sensor telemetry |
| `crc16` | $10 + N$ | 2 bytes | CRC-16 CCITT (Polynom 0x1021, Init 0xFFFF) |
| `eof_delim` | $12 + N$ | 1 byte | End-of-frame framing delimiter (`0x5A`) |

---

## 3. Physical Hardware Pinout Mapping

Connect the ESP32 development board to the Digilent Cora Z7 board according to the pinout below:

| Signal Function | ESP32 GPIO | Cora Z7 Header / Pin | Standard | Description |
| :--- | :---: | :---: | :---: | :--- |
| **SPI SCLK** | **GPIO 18** | **Header J7 Pin 3 (Pin H15)** | LVCMOS33 | SPI Master Clock (up to 25 MHz) |
| **SPI MOSI** | **GPIO 23** | **Header J7 Pin 4 (Pin T12)** | LVCMOS33 | Master-Out Slave-In Telemetry Stream |
| **SPI MISO** | **GPIO 19** | **Header J7 Pin 1 (Pin W15)** | LVCMOS33 | Master-In Slave-Out Ciphertext ACK |
| **SPI SS_N** | **GPIO 5** | **Header J7 Pin 5 (Pin F16)** | LVCMOS33 | Active-Low Slave Select |
| **BURST TRIG** | **GPIO 32** | **PMOD JA Pin 1 (Pin Y18)** | LVCMOS33 | Active-low 30 ms pulse from Cora Z7 PS |
| **GROUND** | **GND** | **Header J7 Pin 6 (GND)** | --- | Common Ground Reference |

---

## 4. Build, Flash & Monitor Instructions

```bash
# Navigate to ESP32 project directory
cd esp32

# Set ESP-IDF target
idf.py set-target esp32

# Clean and compile firmware
idf.py build

# Flash to device on /dev/ttyACM0 and open serial monitor
idf.py -p /dev/ttyACM0 flash monitor
```

### Expected Serial Monitor Telemetry Output
```text
[ESP32_INJECTOR] SPI Master initialized. Ready to transmit frames.
[ESP32_INJECTOR] TX #0 | Seq: 0 | Len: 64 B (Wire: 75 B) | CRC: 0x93FC
[ESP32_INJECTOR] TX #1 | Seq: 1 | Len: 256 B (Wire: 267 B) | CRC: 0xC321
[ESP32_INJECTOR] TX #2 | Seq: 2 | Len: 512 B (Wire: 523 B) | CRC: 0x1A8E
[ESP32_INJECTOR] TX #3 | Seq: 3 | Len: 1024 B (Wire: 1035 B) | CRC: 0x5D43
```
