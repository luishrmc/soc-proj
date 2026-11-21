# SPI Telemetry Injector & Dataset Pipeline (`spi_injector_master` / `trigger_gpio`)
## Autonomous Transmission Firmware for ESP32-WROOM (ESP-IDF v6.1 @ 240 MHz)

The modules in [`esp32/main/`](main/) and [`esp32/scripts/`](scripts/) implement the build-time synthetic telemetry dataset pipeline, `GPIO 32` hardware trigger listener, and VSPI master injector targeting the Digilent Cora Z7-10.

---

## 1. Operational Overview

* **Build-Time `Embedded Dataset` ([`scripts/generate_telemetry.py`](scripts/generate_telemetry.py)):** CMake (`main/CMakeLists.txt`) runs the Python generator during `idf.py build` to emit `telemetry_dataset.{h,c}` in flash `.rodata`. Each entry stores a `1024`-byte payload (`64` packed `16`-byte `Telemetry Record`s) tagged with its `Entropy Profile` (`Quiescent`, `Dynamic`, `Chaotic`).
* **SPI Master Link ([`main/spi_injector_master.c`](main/spi_injector_master.c)):** Uses `SPI3_HOST` (VSPI) in Mode 0 with DMA buffers at `CONFIG_ESP32_SPI_CLOCK_HZ` (`2 MHz` default, up to `25 MHz`).
* **Hardware Trigger ([`main/trigger_gpio.c`](main/trigger_gpio.c)):** `GPIO 32` (`GPIO_INTR_NEGEDGE`, internal pull-up) uses an `IRAM_ATTR` ISR with `esp_timer_get_time()` lockout (`CONFIG_ESP32_TRIGGER_LOCKOUT_MS`, default `50 ms`) and `xTaskNotifyFromISR()` to launch one complete burst per Cora Z7 pulse (`30 ms` active-low on PMOD JA1 `Y18`).
* **Paced Burst Loop ([`main/main.c`](main/main.c)):** Iterates over `g_telemetry_dataset[0..TELEMETRY_DATASET_FRAME_COUNT-1]`, calls `spi_injector_build_frame()` with `SPI_PKT_TYPE_TELEMETRY` (`0x02`) and monotonic `seq_id`, validates ACKs via `spi_injector_validate_ack()`, and delays `CONFIG_ESP32_INTER_FRAME_GAP_MS` (`30 ms` default) between frames.

---

## 2. Physical Pinout Mapping to Digilent Cora Z7-10

| Signal | ESP32 GPIO | Cora Z7 Header / Pin | Function |
| :--- | :---: | :---: | :--- |
| **SCLK** | **GPIO 18** | **Header J7.3 (Pin H15)** | SPI Bus Clock (Mode 0) |
| **MOSI** | **GPIO 23** | **Header J7.4 (Pin T12)** | Master-Out Slave-In `Telemetry Frame` stream |
| **MISO** | **GPIO 19** | **Header J7.1 (Pin W15)** | Master-In Slave-Out ACK (`0x81`) response |
| **SS_N** | **GPIO 5** | **Header J7.5 (Pin F16)** | Active-low hardware slave select |
| **TRIGGER** | **GPIO 32** | **PMOD JA1 (Pin Y18)** | Falling-edge burst trigger from Cora Z7 PS EMIO |
| **GND** | **GND** | **Header J7.6 (GND)** | Common ground reference |

---

## 3. Canonical 16-Byte `Telemetry Record` Layout

Each `1024`-byte payload packs `64` little-endian `Telemetry Record`s (`<IhhhhHH`):

| Field | Type | Width | Description |
| :--- | :---: | :---: | :--- |
| `timestamp_ms` | `uint32_t` | 4 B | Monotonic sample timestamp (ms) |
| `temp_c_x100` | `int16_t` | 2 B | Temperature in 0.01 °C units |
| `vib_x` | `int16_t` | 2 B | X-axis vibration sample |
| `vib_y` | `int16_t` | 2 B | Y-axis vibration sample |
| `vib_z` | `int16_t` | 2 B | Z-axis vibration sample |
| `vcc_mv` | `uint16_t` | 2 B | Supply rail voltage (mV) |
| `status_flags` | `uint16_t` | 2 B | Sensor health/alarm bitmask |

---

## 4. Dynamic Frame Construction (`spi_injector_build_frame`)

```c
void spi_injector_build_frame(TelemetryFrame *frame, uint8_t pkt_type,
                              uint16_t seq_id, const uint8_t *payload, uint16_t len)
```

1. Populates the 8-byte header (`preamble = 0xA5`, `pkt_type = 0x02`, Big-Endian `seq_id`, `payload_len = 1024`, `reserved_align = 0`).
2. Copies the immutable `1024`-byte payload from `g_telemetry_dataset[i].payload` into `frame->payload` (32-bit aligned at byte offset 8).
3. Computes CRC-16 CCITT (`0x1021`, init `0xFFFF`) over `[0 .. 1031]` and appends Big-Endian `crc16` + `0x5A` EOF delimiter (`1035` bytes total on wire).
