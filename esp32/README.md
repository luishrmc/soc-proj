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
| **GND** | `GND` | `GND` | `GND` | Common Ground Reference |

> [!IMPORTANT]
> Both the ESP32 and the Cora Z7-10 operate on 3.3V logic levels. Ensure a solid, low-impedance common ground connection to minimize transmission ringing at 25 MHz.

---

## 2. SPI Frame Protocol Format

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

## 3. Toolchain & Development Workflow

The project is structured according to the clean ESP-IDF model from [`luishrmc/weather_system_esp`](https://github.com/luishrmc/weather_system_esp).

### 3.1 Using VS Code with ESP-IDF Extension

The root `.vscode/settings.json` is preconfigured with the local ESP-IDF v6.1 installation:
1. Open the project root in VS Code.
2. Select **ESP-IDF: Select Current ESP-IDF Version** -> `v6.1`.
3. Set Target device to `esp32`.
4. Click **Build**, **Flash**, and **Monitor** from the VS Code status bar.

### 3.2 Using Command Line Interface (CLI)

```bash
# 1. Load the ESP-IDF v6.1 environment
source /home/luis/.espressif/tools/activate_idf_v6.1.sh

# 2. Navigate to the ESP32 project directory
cd esp32

# 3. Set the target chip (one-time setup)
idf.py set-target esp32

# 4. Compile the firmware
idf.py build

# 5. Flash and open serial monitor (adjust port if needed)
idf.py -p /dev/ttyUSB0 flash monitor
```
