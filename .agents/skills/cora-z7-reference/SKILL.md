---
name: cora-z7-reference
description: Technical hardware profile and pinout reference for Digilent Cora Z7-10 (Zynq-7010, XC7Z010-1CLG400C) including clocks, memory, buttons, RGB LEDs, shield headers, and PMOD connectors.
---

# Cora Z7-10 Reference Skill

Comprehensive hardware specifications and physical pin constraints for the Digilent Cora Z7-10 board.

## 1. System-on-Chip (XC7Z010-1CLG400C)

- **Processing System (PS)**:
  - Dual-core ARM Cortex-A9 @ 667 MHz
  - 512 MB DDR3 memory with 16-bit bus @ 1050 Mbps
  - Performance Monitoring Unit (PMU) for cycle-accurate profiling
  - Internal PS Clocks: `FCLK_CLK0` (typically 50 MHz or 100 MHz) routed to PL fabric
- **Programmable Logic (PL - Artix-7 fabric)**:
  - 28,000 Logic Cells (~17,600 6-input LUTs)
  - 35,200 Flip-Flops
  - 60 Block RAMs of 36 Kb (total 2.1 Mb)
  - 80 DSP slices (18x25 MACs)
- **External Clocks**:
  - `H16`: 125 MHz single-ended reference clock connected to PL Bank 35 (`IO_L13P_T2_MRCC_35`).
  - PS input: 50 MHz crystal oscillator connected to `PS_CLK`.

## 2. On-board User Peripherals & Pinout

All PL user I/Os are on 3.3V powered banks (IOSTANDARD `LVCMOS33`).

### 2.1 Push Buttons
| Signal | Package Pin | Direction | Description |
|---|---|---|---|
| `btn[0]` | `D20` | Input | Button 0 (Active High) |
| `btn[1]` | `D19` | Input | Button 1 (Active High) |

### 2.2 RGB LEDs
| LED | Color | Package Pin | Description |
|---|---|---|---|
| `LD0` | Blue | `L15` | RGB0 Blue (`led0_b`) |
| `LD0` | Green | `G17` | RGB0 Green (`led0_g`) |
| `LD0` | Red | `N15` | RGB0 Red (`led0_r`) |
| `LD1` | Blue | `G14` | RGB1 Blue (`led1_b`) |
| `LD1` | Green | `L14` | RGB1 Green (`led1_g`) |
| `LD1` | Red | `M15` | RGB1 Red (`led1_r`) |

### 2.3 Dedicated SPI Pins (Arduino/ChipKIT Shield Header J1)
Protected with on-board 200 Ω series damping resistors against accidental short circuits.
| Shield Label | FPGA Pin | Bank | Description |
|---|---|---|---|
| `SCK` | `G20` | Bank 35 | SPI Clock input from ESP32 |
| `MOSI` | `T10` | Bank 34 | Master-Out Slave-In from ESP32 |
| `MISO` | `V15` | Bank 34 | Master-In Slave-Out to ESP32 |
| `SS` / `CS_n` | `F16` | Bank 35 | Active-Low Slave Select from ESP32 |

### 2.4 PMOD Connectors (2x6 Standard Female Headers)
- **PMOD JA** (Pins 1-4, 7-10): `Y18`, `Y19`, `Y16`, `Y17` (top row); `U18`, `U19`, `W18`, `W19` (bottom row).
- **PMOD JB** (Pins 1-4, 7-10): `W14`, `Y14`, `T11`, `T10` (top row); `V16`, `W16`, `V12`, `W13` (bottom row).

## 3. Invariants & Rules
- All pins must have explicit `IOSTANDARD LVCMOS33` unless connected to dedicated differential pairs.
- Inputs originating from off-board (such as the ESP32 SPI bus) must be treated as asynchronous to `FCLK_CLK0` and passed through synchronizers.
