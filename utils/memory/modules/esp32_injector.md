---
module: esp32_injector
status: verified
sources:
  - esp32/main/main.c sha256=525bd55eec62fc3dc951e7fab0a880ea398d69f24bb20b05ef2584aecf821b11
  - esp32/main/spi_injector_master.c sha256=eb5628970976d1728ba4abdf9119a9041b23d0a20a0b2b6ace4c314902a6af2d
  - esp32/components/ui_controller/ui_controller.c sha256=18279652e25d67948f2663a52eec18af415eaa347dc1389b77519f9533106a86
  - esp32/components/ui_controller/ui_controller.h sha256=986db277793083dfa065a0b31287bc20b47526631c6fe6cbf5098b9a5bd9cb2a
gates_passed: [esp-idf-build, esp32-selftest]
---

# ESP32 Autonomous UI & SPI Injector Digest

## 1. Module Overview
- **Function**: Autonomous SPI Master synthetic data generator with physical UI controls (pushbuttons) and visual status indicators (LEDs) for the Cora Z7 benchmark setup.
- **Microcontroller**: ESP32-D0WD-V3 (revision v3.1), Dual-Core Xtensa LX6 @ 240 MHz.
- **Toolchain**: ESP-IDF v6.1 with FreeRTOS SMP.

## 2. Pin Mapping & Hardware Interface
- **SPI Master Bus (VSPI)**:
  - SCLK: GPIO 18 (25 MHz) -> Cora Z7 J7.3 (G20)
  - MOSI: GPIO 23 -> Cora Z7 J7.4 (T10)
  - MISO: GPIO 19 -> Cora Z7 J7.1 (V15)
  - CS#: GPIO 5 -> Cora Z7 J7.5 (F16)
- **Minimalist Autonomous UI**:
  - BTN_TRIGGER: GPIO 32 (Active-low to GND, internal pull-up, 40ms debounce) -> Dispatches Full Suite
  - LED_GREEN: GPIO 21 (RGB Green: 1 Hz heartbeat in IDLE, Solid ON in BUSY, 3 rapid blinks in SUCCESS)
  - LED_RED: GPIO 22 (RGB Red: 5 Hz rapid blink in ERROR / alert)
  - LED_READY: GPIO 2 (Blue onboard mirror)

## 3. Operational Mode
- Single-button trigger: pressing GPIO 32 immediately transmits the full sequential benchmark suite:
  1. 64 B High-Redundancy (`s_buf_64b` -> RLE)
  2. 1 KB Pseudo-Random (`s_buf_1kb` -> LZ4)
  3. 64 KB Telemetry (`s_buf_64kb` -> AES-128-CTR)
  4. 64 KB Telemetry (`s_buf_64kb` -> ChaCha20)

## 4. On-Board Verification Evidence
- **Build**: `idf.py build` produced `esp32_spi_injector.bin` (187,440 bytes, 82% free partition).
- **Flash & Self-Test**: Tested on physical silicon via `/dev/ttyACM0`.
  - LED chaser sequence passed.
  - Pull-up default HIGH levels verified on GPIO 4 and GPIO 16.
  - CRC-16-CCITT validated on 64B, 1KB, and 64KB buffers.
  - Dry-run SPI DMA transmission passed in 198 us.
  - Full execution log captured in `out/esp32_selftest.log`.
