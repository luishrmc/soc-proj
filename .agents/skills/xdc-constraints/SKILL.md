---
name: xdc-constraints
description: Authoring, auditing, and validating XDC physical pin and timing constraints for the Digilent Cora Z7-10 against board schematics and reference manuals.
---

# XDC Constraints Skill

Guidelines for writing and validating physical and timing constraint files (`*.xdc`) for the Digilent Cora Z7-10.

## 1. When to Use
- Assigning FPGA package pins and I/O standards for external board interfaces (SPI, buttons, LEDs, external clocks).
- Creating timing constraints for external input clocks and asynchronous boundaries.
- Auditing constraints before running synthesis and implementation.

## 2. Protected File Status
Files matching `cora7z/app/hw/utils/*.xdc` are **protected** in `.agents/manifest.json`.
- Changes can only be made when `ALLOW_PROTECTED=1` is explicitly set for the task step.
- Every pin assignment must reference the exact net name in `docs/cora7z/Cora+Z7_sch-public.pdf`.

## 3. Physical Constraints Template

All PL user I/Os on Cora Z7 require explicit `PACKAGE_PIN` and `IOSTANDARD LVCMOS33`:

```tcl
# 125 MHz Reference Clock from Ethernet PHY
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { clk_125m_i }];
create_clock -add -name sys_clk_pin -period 8.000 -waveform {0 4} [get_ports { clk_125m_i }];

# Push Buttons
set_property -dict { PACKAGE_PIN D20   IOSTANDARD LVCMOS33 } [get_ports { btn_i[0] }];
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { btn_i[1] }];

# RGB LED 0
set_property -dict { PACKAGE_PIN L15   IOSTANDARD LVCMOS33 } [get_ports { rgb_led0_b_o }];
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { rgb_led0_g_o }];
set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { rgb_led0_r_o }];

# SPI Slave Interface from ESP32 (Shield Header J1)
set_property -dict { PACKAGE_PIN G20   IOSTANDARD LVCMOS33 } [get_ports { spi_sclk_i }];
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { spi_mosi_i }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { spi_miso_o }];
set_property -dict { PACKAGE_PIN F16   IOSTANDARD LVCMOS33 } [get_ports { spi_cs_n_i }];
```

## 4. Verification Check
Every top-level port in the synthesized design must have:
1. Exactly one assigned `PACKAGE_PIN`.
2. Explicit `IOSTANDARD`.
3. No duplicate pin allocations.
4. Input clocks properly declared via `create_clock`.
