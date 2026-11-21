# Synthetic SPI Telemetry Injector Harness (ESP32)
## Firmware for ESP32-WROOM (ESP-IDF v6.1 @ 240 MHz)

This directory contains the firmware and build-time Python generator for the **ESP32-WROOM** hardware-in-the-loop (HIL) injector, operating as an SPI Mode 0 master transmitting fixed 1024-byte `Telemetry Frame`s to the Digilent Cora Z7-10 (Xilinx Zynq-7010).

> [!NOTE]
> **Architecture Alignment ([ADR-020](../docs/adr/0020-fixed-1024b-benchmark-payload.md) & [GLOSSARY.md](../GLOSSARY.md)):**
> All external LEDs and buttons (`ui_controller`) have been removed. The ESP32 connects directly to the Cora Z7 over SPI + a single falling-edge trigger line (`GPIO 32`), streaming a flash-resident `Embedded Dataset` generated at build time by [`esp32/scripts/generate_telemetry.py`](scripts/generate_telemetry.py).

---

## 1. Operational Role & Build-Time Python Generator

* **Python Synthetic Telemetry Generator ([`scripts/`](scripts/)):**
  * [`telemetry_profiles.py`](scripts/telemetry_profiles.py) synthesizes packed 16-byte `Telemetry Record`s (`timestamp_ms`, `temp_c_x100`, `vib_x`, `vib_y`, `vib_z`, `vcc_mv`, `status_flags`) across three `Entropy Profile`s: **`Quiescent`** (low entropy), **`Dynamic`** (medium entropy), and **`Chaotic`** (high entropy).
  * [`generate_telemetry.py`](scripts/generate_telemetry.py) emits `telemetry_dataset.{h,c}` automatically during `idf.py build` via CMake `add_custom_command`, storing `g_telemetry_dataset` (`30` frames = `10` per profile by default, deterministic `--seed 42`) in immutable flash `.rodata`.
  * [`test_generate_telemetry.py`](scripts/test_generate_telemetry.py) verifies binary packing, `1024`-byte payload sizing, determinism, entropy/compressibility ordering, JSON overrides, and C11 header syntax.
* **Bus Configuration:** Hardware SPI Master (`SPI3_HOST` / VSPI) in **Mode 0** (`CPOL=0`, `CPHA=0`, MSB-First) at `2 MHz` default (`CONFIG_ESP32_SPI_CLOCK_HZ`, configurable up to `25 MHz`).
* **Fixed Payload Contract (ADR-020):** `pkt_type = 0x02` (`SPI_PKT_TYPE_TELEMETRY`), fixed **`1024`-byte** payload (`64` × `16`-byte `Telemetry Record`s), `1035` bytes total on wire.
* **Hardware Trigger (`GPIO 32`):** [`trigger_gpio.c`](main/trigger_gpio.c) configures `GPIO 32` (`GPIO_INTR_NEGEDGE`, internal pull-up, `50 ms` ISR lockout) to detect the `30 ms` active-low pulse from Cora Z7 PMOD JA1 (`Y18`) and dispatch one paced burst (`30 ms` inter-frame gap default) with monotonic `seq_id` and full-duplex ACK validation.
* **Kconfig Options ([`main/Kconfig.projbuild`](main/Kconfig.projbuild)):** Configure SPI clock, inter-frame gap, trigger lockout, dataset seed/frames per profile, optional `CONFIG_ESP32_AUTO_TRIGGER_FALLBACK` (disabled by default), and non-blocking UART debug commands (`'t'` to trigger a burst, `'s'` for status).

---

## 2. Binary SPI Frame Wire Specification

Every frame clocked over the physical SPI bus adheres to [`main/spi_frame.h`](main/spi_frame.h):

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| Preamble 0xA5 | Pkt Type 0x02 |       Sequence ID (15:0)      | [0..3]
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   Payload Length (0x0400)     |   Reserved Padding (0x0000)   | [4..7]
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|         64 x 16-byte Telemetry Records (1024 B aligned)       | [8..1031]
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       CRC-16-CCITT (15:0)     | EOF Delim 0x5A|                 [1032..1034]
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

**Total Wire Size:** `8` (Header) + `1024` (Payload) + `3` (Trailer) = **`1035` Bytes**.

---

## 3. Physical Hardware Pinout Mapping

| Signal Function | ESP32 GPIO | Cora Z7 Header / Pin | Electrical Standard | Description |
| :--- | :---: | :---: | :---: | :--- |
| **SPI SCLK** | **GPIO 18** | **Header J7 Pin 3 (`H15`)** | LVCMOS33 | SPI Master Clock (`2 MHz` default, up to `25 MHz`) |
| **SPI MOSI** | **GPIO 23** | **Header J7 Pin 4 (`T12`)** | LVCMOS33 | Master-Out Slave-In `Telemetry Frame` stream |
| **SPI MISO** | **GPIO 19** | **Header J7 Pin 1 (`W15`)** | LVCMOS33 | Master-In Slave-Out ACK response (`0x81`) |
| **SPI SS_N** | **GPIO 5** | **Header J7 Pin 5 (`F16`)** | LVCMOS33 | Active-Low Hardware Slave Select |
| **TRIGGER** | **GPIO 32** | **PMOD JA Pin 1 (`Y18`)** | LVCMOS33 | Falling-edge burst trigger from Cora Z7 PS EMIO |
| **GROUND** | **GND** | **Header J7 Pin 6 (`GND`)** | --- | Common Ground Reference |

---

## 4. Build, Test, Flash & Monitor Instructions

### Step 1: Run Host Python Generator Unit Tests
```bash
python3 -m unittest discover -s esp32/scripts -v
```

### Step 2: Build ESP-IDF Firmware (Auto-Generates `Embedded Dataset`)
```bash
cd esp32
idf.py set-target esp32
idf.py build
```

### Step 3: Flash and Launch Serial Monitor (`/dev/ttyACM0`)
```bash
idf.py -p /dev/ttyACM0 flash monitor
```

### Verified Serial Monitor Output Format (`out/esp32_verify.log`)
```text
I (310) TRIGGER_GPIO: Armed GPIO 32 (NEGEDGE, internal pull-up, lockout=50 ms, level=1)
I (320) ESP32_MASTER: ============================================================
I (328) ESP32_MASTER:   ESP32 SPI Master Telemetry Injector (ADR-020 / 1024 B)
I (335) ESP32_MASTER: ============================================================
I (342) ESP32_MASTER: VSPI Bus   : SCK=18 MOSI=23 MISO=19 CS=5 Mode 0 @ 2000000 Hz
I (349) ESP32_MASTER: Dataset    : 30 frames (10/profile: Quiescent, Dynamic, Chaotic)
I (357) ESP32_MASTER: Frame Spec : pkt_type=0x02 payload=1024 B (64 records x 16 B) wire=1035 B seed=42
I (366) ESP32_MASTER: Pacing     : inter-frame gap=30 ms | GPIO 32 lockout=50 ms (level=1)
I (374) ESP32_MASTER: UART Debug : enabled (send 't' to trigger burst, 's' for stats)
I (382) ESP32_MASTER: Auto-Trig  : disabled (armed for GPIO 32 falling-edge trigger)
```
