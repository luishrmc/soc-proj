---
module: spi_receiver
status: verified
sources:
  - cora7z/app/hw/src/spi_receiver.vhdl sha256=6030d0707267772909efa52a1d679328dcaad88d8e75585e46ef43c1df68d005
  - cora7z/app/hw/test/tb_spi_receiver.vhdl sha256=3f983614f55aaf4f3f8d17e211790cfaee2bca75e1f0ac1a8572c85f08ca7770
  - docs/SPI_RECEIVER_ARCHITECTURE.md sha256=3a9ef798d6d7a2dd0b095cd3acbc0aa5331183438ed8403665f2ca06eab9f96d
gates_passed: [vhdl-lint, vhdl-sim]
---

# SPI Receiver Module Digest

## 1. Module Overview
- **Function**: High-speed synchronous SPI Slave receiver ingesting external telemetry from ESP32 master.
- **Clock Domain**: 100 MHz (`clk_i` driven by PS7 acceleration clock).
- **Physical Rate**: Supports up to 25.0 MHz SPI clock on Mode 0 (`CPOL=0`, `CPHA=0`).
- **CDC**: 2-stage DFF synchronizers with edge detection on `sclk`, `cs_n`, and `mosi`.

## 2. Pin and Bus Interfaces
- **External Physical Pins (J1 Shield Header)**:
  - `spi_sclk_i` -> Pin `G20` (Bank 35, 3.3V LVCMOS)
  - `spi_mosi_i` -> Pin `T10` (Bank 34, 3.3V LVCMOS)
  - `spi_miso_o` -> Pin `V15` (Bank 34, 3.3V LVCMOS)
  - `spi_cs_n_i` -> Pin `F16` (Bank 35, 3.3V LVCMOS)
- **Downstream Egress (AXI4-Stream Master)**:
  - `m_axis_tdata_o`: 8-bit received byte stream.
  - `m_axis_tvalid_o`: Strobe indicating available byte.
  - `m_axis_tready_i`: Downstream backpressure.
  - `m_axis_tlast_o`: Packet boundary marker, asserted on last byte when `cs_n` deasserts.
- **Status Signals**:
  - `rx_byte_count_o`: 16-bit counter of received bytes in current frame.
  - `frame_active_o`: High while `cs_n` is asserted.
  - `overflow_o`: Sticky flag indicating FIFO capacity saturation.

## 3. Internal Buffer Architecture
- Synchronous ring-buffer FIFO (depth 32 bytes).
- Decouples physical SPI transfer rate from downstream consumption stalls.
- Zero data loss under backpressure up to FIFO depth.

## 4. Verification & Gates
- **Static Lint**: `vhdl-lint` PASS (zero warnings, VHDL-2008, numeric_std only).
- **Self-Checking Testbench**: `tb_spi_receiver.vhdl` (5/5 VUnit test scenarios PASS: reset, 25 MHz single byte, multi-byte packet with TLAST, backpressure, capacity overflow).
