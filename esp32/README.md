# ESP32 High-Speed SPI Master Synthetic Data Injector

Firmware for the ESP32 (ESP32-WROOM-32 / ESP32-DevKitC) acting as a high-speed SPI Master data injector into the Digilent Cora Z7-10 (Xilinx Zynq-7010) platform. Transmits structured synthetic benchmark blocks across SPI at up to 25 MHz to validate hardware coprocessors and hybrid co-design pipelines.

---

## 1. Physical Hardware Interconnect (Pinout)

Connect the ESP32 GPIOs directly to the Cora Z7-10 **Dedicated SPI Header J7** (2x3 pin header, 3.3V LVCMOS):

| Signal Name | ESP32 GPIO | Cora Z7 FPGA Pin | Cora Z7 Connector J7 | Description |
|---|:---:|:---:|:---:|---|
| **MISO** | `GPIO 19` | `W15` | **J7 Pin 1** (`MISO`) | Master-In Slave-Out serial data (via 200Ω R108, CK_MISO) |
| **SCLK** | `GPIO 18` | `H15` | **J7 Pin 3** (`SCK`) | SPI Bus Clock (Mode 0, up to 25 MHz, via 200Ω R109, CK_SCK) |
| **MOSI** | `GPIO 23` | `T12` | **J7 Pin 4** (`MOSI`) | Master-Out Slave-In serial data (via 200Ω R110, CK_MOSI) |
| **CS / SS** | `GPIO 5` | `F16` | **J7 Pin 5** (`SS`) | Active-Low Chip Select framing (via 200Ω R111, CK_SS) |
| **GND** | `GND` | `GND` | **J7 Pin 6** (`GND`) | Common Ground Reference |
| *(5.0V)* | *N/A* | *N/A* | **J7 Pin 2** (`5V0`) | **DO NOT CONNECT** (Power rail) |
| **BTN_TRIGGER** | `GPIO 32` | N/A | Pushbutton (to GND) | Trigger Full Benchmark Suite (Active-Low, internal pull-up) |
| **LED_GREEN** | `GPIO 21` | N/A | RGB LED Green Channel | Heartbeat (1 Hz) / Busy (Solid ON) / Success (3 Rapid Blinks) |
| **LED_RED** | `GPIO 22` | N/A | RGB LED Red Channel | Alert / Critical Error (5 Hz Rapid Blink) |
| **LED_READY** | `GPIO 2` | N/A | Blue Onboard | Onboard Ready Heartbeat mirror |

> [!IMPORTANT]
> Both the ESP32 and the Cora Z7-10 operate on 3.3V logic levels. On the Cora Z7, all four SPI lines on J7 pass through 200Ω series protection resistors ($R108 \dots R111$) directly into FPGA Banks 34 and 35. Ensure a solid, low-impedance common ground connection (J7 Pin 6 to ESP32 GND) to minimize transmission ringing at 25 MHz. **Do not connect J7 Pin 2 (5V)**.

---

## 2. Autonomous UI & Single-Cable Bench Workflow

Because the test setup utilizes **a single micro-USB cable** and limited breadboard area, the hardware UI is streamlined:
1. **Flashing & Diagnostics**: USB cable connected to ESP32 (`/dev/ttyACM0`).
2. **End-to-End Benchmarks**: USB cable connected to Cora Z7 (capturing Cortex-A9 PMU / UART). The ESP32 is powered independently via external 5V/VIN or 3.3V rail.

### Pushbutton Controls
- **BTN_TRIGGER (GPIO 32)**: Single button connected between GPIO 32 and GND. Pushing the button immediately executes the full sequential benchmark suite:
  1. 64 B High-Redundancy block (RLE pipeline)
  2. 1 KB Pseudo-Random block (LZ4 pipeline)
  3. 64 KB Synthetic Telemetry block (AES-128-CTR pipeline)
  4. 64 KB Synthetic Telemetry block (ChaCha20 pipeline)

### Visual LED Telemetry (RGB LED on GPIO 21 & 22)
- **IDLE / Ready**: Green LED (GPIO 21) pulses with a 1 Hz heartbeat; Red LED is OFF.
- **BUSY (Transmitting)**: Green LED (GPIO 21) remains Solid ON during SPI packet injection.
- **SUCCESS**: Green LED (GPIO 21) emits 3 rapid blinks upon completing all 4 benchmark patterns with valid handshake, then returns to IDLE heartbeat.
- **ERROR / Alert**: Red LED (GPIO 22) flashes rapidly at 5 Hz if a timeout, CRC mismatch, or framing error occurs.

---

## 3. SPI Frame Protocol Format

Each frame strictly adheres to the protocol specified in `cora7z/app/hw/src/INTERFACES.md` (Section 1.3):

```text
+---------------+-------------------+---------------+---------------+-------------------------+---------------+
| Preamble (2B) | Payload Type (1B) | Flags (1B)    | Length (4B)   | Payload Data (N Bytes)  | CRC-16 (2B)   |
| 0xAA, 0x55    | TYPE              | FLAGS         | Big-Endian    | [0 ... N-1]             | Big-Endian    |
+---------------+-------------------+---------------+---------------+-------------------------+---------------+
```

- **Preamble**: `0xAA, 0x55` (Fixed synchronization marker).
- **Payload Types**:
  - `0x01` (`TYPE_REDUNDANT`): 64 B repeated pattern (for RLE benchmarking).
  - `0x02` (`TYPE_RANDOM`): 1 KB pseudo-random data (for LZ4 benchmarking).
  - `0x03` (`TYPE_TELEMETRY`): 64 KB structured sensor records (for AES-CTR / ChaCha20).
- **Flags**:
  - `Bit 0`: `COMPRESS_EN`
  - `Bit 1`: `ENCRYPT_EN`
  - `Bit 2`: `COMP_ALGO` (`0` = RLE, `1` = LZ4)
  - `Bit 3`: `CRYPTO_ALGO` (`0` = AES-128-CTR, `1` = ChaCha20)
- **Length**: 32-bit unsigned integer (Big-Endian).
- **CRC-16**: CRC-16-CCITT (polynomial `0x1021`, initial `0xFFFF`) over Header + Payload.

---

## 4. Toolchain & Development Workflow

The project is structured according to the clean ESP-IDF model from [`luishrmc/weather_system_esp`](https://github.com/luishrmc/weather_system_esp).

### 4.1 Command Line Interface (CLI)

```bash
# 1. Load the ESP-IDF v6.1 environment
source $HOME/.espressif/tools/activate_idf_v6.1.sh

# 2. Navigate to the ESP32 project directory
cd esp32

# 3. Compile the firmware
idf.py build

# 4. Flash and open serial monitor via native USB-Serial (/dev/ttyACM0)
idf.py -p /dev/ttyACM0 flash monitor
```
