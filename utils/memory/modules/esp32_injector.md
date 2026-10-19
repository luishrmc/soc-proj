---
module: esp32_injector
status: verified
sources:
  - esp32/main/main.c sha256=9ceb5e974dbb9f664d95cc6db7023d908507bc2862c4339d2367b55df0b5244c
  - esp32/main/spi_injector_master.c sha256=c572f11a8fcad3b7fa0f699a330713a2130600364d3638964f540d641d4896f2
  - esp32/components/ui_controller/ui_controller.c sha256=15b41324bcdea4accd50a947c30f3d87099f3c3a2333514d59a794c95cc4759e
  - esp32/components/ui_controller/ui_controller.h sha256=f0cd06a4427e29bf6a156c706b748f63351c2073597a8b30cad7a6e4cd8afe65
gates_passed: [esp-idf-build, esp32-selftest]
---

# ESP32 Autonomous UI & SPI Injector Digest

## 1. Module Overview
- **Function**: Autonomous SPI Master synthetic data generator with physical UI controls (pushbuttons) and visual status indicators (LEDs) for the Cora Z7 benchmark setup.
- **Microcontroller**: ESP32-D0WD-V3 (revision v3.1), Dual-Core Xtensa LX6 @ 240 MHz.
- **Toolchain**: ESP-IDF v6.1 with FreeRTOS SMP.

## 2. Pin Mapping & Hardware Interface
- **SPI Master Bus (VSPI)**:
  - SCLK: GPIO 18 (25 MHz) -> Cora Z7 G20
  - MOSI: GPIO 23 -> Cora Z7 T10
  - MISO: GPIO 19 -> Cora Z7 V15
  - CS#: GPIO 5 -> Cora Z7 F16
- **Autonomous User Interface (UI)**:
  - BTN_TRIGGER: GPIO 4 (Active-low, internal pull-up, 40ms debounce) -> Start burst
  - BTN_SELECT: GPIO 16 (Active-low, internal pull-up, 40ms debounce) -> Cycle profile
  - LED_READY: GPIO 2 (Blue onboard, 1 Hz heartbeat)
  - LED_TX: GPIO 21 (TX Active / Busy)
  - LED_STATUS: GPIO 22 (Profile pulse count / Continuous ON for Error alert)

## 3. Supported Test Profiles
- `Profile 0`: 64 B High-Redundancy (`s_buf_64b` -> RLE)
- `Profile 1`: 1 KB Pseudo-Random (`s_buf_1kb` -> LZ4)
- `Profile 2`: 64 KB Telemetry (`s_buf_64kb` -> AES-128-CTR)
- `Profile 3`: 64 KB Telemetry (`s_buf_64kb` -> ChaCha20)
- `Profile 4`: Full Benchmark Suite (All 4 patterns back-to-back)

## 4. On-Board Verification Evidence
- **Build**: `idf.py build` produced `esp32_spi_injector.bin` (187,440 bytes, 82% free partition).
- **Flash & Self-Test**: Tested on physical silicon via `/dev/ttyACM0`.
  - LED chaser sequence passed.
  - Pull-up default HIGH levels verified on GPIO 4 and GPIO 16.
  - CRC-16-CCITT validated on 64B, 1KB, and 64KB buffers.
  - Dry-run SPI DMA transmission passed in 198 us.
  - Full execution log captured in `out/esp32_selftest.log`.
