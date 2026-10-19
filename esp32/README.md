# ESP32 High-Speed SPI Master Synthetic Data Injector

Firmware for the ESP32 (ESP32-WROOM-32 / ESP32-DevKitC) acting as a high-speed SPI Master data injector into the Digilent Cora Z7-10 (Xilinx Zynq-7010) platform. Transmits structured synthetic benchmark blocks across SPI at up to 25 MHz to validate hardware coprocessors and hybrid co-design pipelines.

---

## 1. Physical Hardware Interconnect (Pinout)

Connect the ESP32 GPIOs directly to the Cora Z7-10 Shield Header J1 (Bank 34 / 35, 3.3V LVCMOS):

| Signal Name | ESP32 GPIO | Cora Z7 FPGA Pin | Shield Header J1 Pin | Description |
|---|:---:|:---:|:---:|---|
| **SCLK** | `GPIO 18` | `G20` | `SCK / IO13` | SPI Bus Clock (Mode 0, up to 25 MHz) |
| **MOSI** | `GPIO 23` | `T10` | `MOSI / IO11` | Master-Out Slave-In serial data |
| **MISO** | `GPIO 19` | `V15` | `MISO / IO12` | Master-In Slave-Out serial data |
| **CS / SS** | `GPIO 5` | `F16` | `SS / IO10` | Active-Low Chip Select (frame framing) |
| **BTN_TRIGGER** | `GPIO 4` | N/A | Pushbutton 1 | Trigger burst injection (Active-Low, internal pull-up) |
| **BTN_SELECT** | `GPIO 16` | N/A | Pushbutton 2 | Cycle benchmark profile (Active-Low, internal pull-up) |
| **LED_READY** | `GPIO 2` | N/A | Blue Onboard | Heartbeat 1 Hz (Alive & Ready indicator) |
| **LED_TX** | `GPIO 21` | N/A | External LED | TX Active / Busy indicator |
| **LED_STATUS** | `GPIO 22` | N/A | External LED | Profile Blink Code / Critical Error alert |
| **GND** | `GND` | `GND` | `GND` | Common Ground Reference |

> [!IMPORTANT]
> Both the ESP32 and the Cora Z7-10 operate on 3.3V logic levels. Ensure a solid, low-impedance common ground connection to minimize transmission ringing at 25 MHz.

---

## 2. Autonomous UI & Single-Cable Bench Workflow

Because the test setup utilizes **a single micro-USB cable**, the cable is time-multiplexed:
1. **Flashing & Diagnostics**: USB cable connected to ESP32 (`/dev/ttyACM0`).
2. **End-to-End Benchmarks**: USB cable connected to Cora Z7 (capturing Cortex-A9 PMU / UART). The ESP32 is powered independently via external 5V/VIN or 3.3V rail.

### Pushbutton Controls
- **BTN_SELECT (GPIO 16)**: Cycles the active test profile:
  - `Profile 0`: 64 B High-Redundancy (RLE)
  - `Profile 1`: 1 KB Pseudo-Random (LZ4)
  - `Profile 2`: 64 KB Telemetry (AES-128-CTR)
  - `Profile 3`: 64 KB Telemetry (ChaCha20)
  - `Profile 4`: Full Benchmark Suite (All 4 patterns back-to-back)
- **BTN_TRIGGER (GPIO 4)**: Injects the active burst over SPI.

### Visual LED Telemetry
- **LED_READY (GPIO 2)**: 1 Hz blinking heartbeat indicating the FreeRTOS orchestrator is ready.
- **LED_TX (GPIO 21)**: Solid ON during packet transmission; OFF when idle.
- **LED_STATUS (GPIO 22)**:
  - Emits `profile + 1` pulses (e.g., 2 blinks = 1KB LZ4), followed by a 1.4s pause.
  - Solid continuous ON in case of critical error (CRC or SPI failure).

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
