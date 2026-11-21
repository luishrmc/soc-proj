---
module: esp32_injector
status: verified
sources:
  - esp32/main/main.c sha256=d54de8b255ad6ecf4aca9001f8e5f3515355b789ca12802b11cff86642aa02e5
  - esp32/main/spi_injector_master.c sha256=8170018862f35a46699319100dcb555cd8adca38a30e6c7c178252ba1bdcaf44
  - esp32/main/trigger_gpio.c sha256=9480200db9eaf8af8152990f521fbb17835e56852dadfbc4f5ba0784238e52ae
  - esp32/main/trigger_gpio.h sha256=bd576752bdea8a5762bf1cc5b585bef8f54fbbfd774c443850008c8db0de0bcc
  - esp32/main/CMakeLists.txt sha256=f4a34f64899fa5654f96d62710417885ba4d11025171e01799b79b9c6d2384c9
  - esp32/main/Kconfig.projbuild sha256=4dc06941554ccf97bd55c24d47bcdf0845bc8962a1eef76ec2a668bee51458e6
  - esp32/scripts/generate_telemetry.py sha256=42fa3a5734b54e9a79e50686085fb7946e07e459b03ba5e436c47892a4eb1d72
  - esp32/scripts/telemetry_profiles.py sha256=73fcf2a0d7ccf451fec901252f9a4dcba2329329236926075f9cefe2af4344ea
gates_passed: [esp32-unittest, esp-idf-build, esp32-ttyACM0-verify]
---

# ESP32 Telemetry Generator & SPI Injector Digest

## 1. Module Overview
- **Function**: Streams flash-resident `Embedded Dataset` `Telemetry Frame`s (`1024` B payload, `pkt_type=0x02`, `1035` B wire) over VSPI Mode 0 upon falling-edge `GPIO 32` trigger from Cora Z7.
- **Target**: ESP32-D0WD-V3 (rev v3.1), ESP-IDF v6.1 @ 240 MHz.
- **Cleanup**: Removed unused `ui_controller` (LEDs `GPIO 2/21/22` and button polling).

## 2. Pinout & Trigger Interface
- **VSPI Master**: `SCLK=18` (`H15`), `MOSI=23` (`T12`), `MISO=19` (`W15`), `CS=5` (`F16`), `2 MHz` default (`CONFIG_ESP32_SPI_CLOCK_HZ`, up to `25 MHz`).
- **Hardware Trigger**: `GPIO 32` (`PMOD JA1 Y18`), `GPIO_INTR_NEGEDGE` + pull-up, `50 ms` ISR lockout (`xTaskNotifyFromISR`), `30 ms` inter-frame gap.

## 3. Build-Time Python Telemetry Generator
- `esp32/main/CMakeLists.txt` invokes `generate_telemetry.py` (`seed=42`, `10` frames/profile = `30` frames) during `idf.py build`.
- `telemetry_profiles.py` synthesizes `64` × `16`-byte `Telemetry Record`s (`<IhhhhHH`) across `Quiescent`, `Dynamic`, and `Chaotic` `Entropy Profile`s.

## 4. Verification Evidence
- **Host Unit Tests**: `python3 -m unittest discover -s esp32/scripts -v` -> 7/7 OK.
- **ESP-IDF Build**: `idf.py build` (`-Wall -Wextra -Werror`) -> 0 warnings, `esp32_spi_injector.bin` = `220,896` bytes (`0x35ee0`, 79% free).
- **Target `/dev/ttyACM0`**: Flashed & verified boot summary, `GPIO 32` armed state, UART `'s'` stats, and `'t'` 30-frame burst TX (`out/esp32_verify.log`).
