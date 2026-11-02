#!/usr/bin/env python3
"""
generate_soc_diagram.py: High-Resolution Heterogeneous SoC Architectural Diagram Generator
Outputs publication-quality PNG, JPG, and PDF diagrams for the DELT UFMG deliverable.
"""

import math
import sys
from pathlib import Path
import cairo

OUT_DIR = Path(__file__).resolve().parent
PNG_FILE = OUT_DIR / "cora7z_top.png"
JPG_FILE = OUT_DIR / "cora7z_top.jpg"
ARCH_PNG = OUT_DIR / "cora7z_soc_architecture.png"
PDF_FILE = OUT_DIR / "cora7z_soc_architecture.pdf"

WIDTH = 3200
HEIGHT = 1800

def draw_rounded_rect(ctx, x, y, w, h, r):
    ctx.new_sub_path()
    ctx.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    ctx.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    ctx.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    ctx.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    ctx.close_path()

def draw_card(ctx, x, y, w, h, bg_color, border_color, title, subtitle=None, r=12):
    # Shadow
    ctx.save()
    draw_rounded_rect(ctx, x + 6, y + 6, w, h, r)
    ctx.set_source_rgba(0, 0, 0, 0.25)
    ctx.fill()
    ctx.restore()

    # Body
    draw_rounded_rect(ctx, x, y, w, h, r)
    ctx.set_source_rgb(*bg_color)
    ctx.fill_preserve()
    ctx.set_source_rgb(*border_color)
    ctx.set_line_width(3.0)
    ctx.stroke()

    # Title header banner
    draw_rounded_rect(ctx, x, y, w, 46, r)
    ctx.set_source_rgb(*border_color)
    ctx.fill()

    # Header text
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(22)
    ctx.set_source_rgb(1.0, 1.0, 1.0)
    ctx.move_to(x + 16, y + 32)
    ctx.show_text(title)

    if subtitle:
        ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        ctx.set_font_size(15)
        ctx.set_source_rgb(0.9, 0.9, 0.9)
        ctx.move_to(x + w - 16 - len(subtitle) * 8.5, y + 30)
        ctx.show_text(subtitle)

def draw_arrow(ctx, x1, y1, x2, y2, color, line_width=4.0, arrow_size=12, label=None, label_side="top"):
    ctx.save()
    ctx.set_source_rgb(*color)
    ctx.set_line_width(line_width)
    ctx.move_to(x1, y1)
    ctx.line_to(x2, y2)
    ctx.stroke()

    # Arrowhead
    angle = math.atan2(y2 - y1, x2 - x1)
    ctx.move_to(x2, y2)
    ctx.line_to(x2 - arrow_size * math.cos(angle - math.pi / 6), y2 - arrow_size * math.sin(angle - math.pi / 6))
    ctx.line_to(x2 - arrow_size * math.cos(angle + math.pi / 6), y2 - arrow_size * math.sin(angle + math.pi / 6))
    ctx.close_path()
    ctx.fill()

    if label:
        ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        ctx.set_font_size(14)
        mx = (x1 + x2) / 2
        my = (y1 + y2) / 2
        if label_side == "top":
            my -= 10
        elif label_side == "bottom":
            my += 20
        elif label_side == "left":
            mx -= len(label) * 8
        elif label_side == "right":
            mx += 10
        ctx.move_to(mx - len(label) * 4, my)
        ctx.show_text(label)
    ctx.restore()

def render_diagram(ctx):
    # Background gradient
    pat = cairo.LinearGradient(0, 0, WIDTH, HEIGHT)
    pat.add_color_stop_rgb(0, 0.08, 0.10, 0.15)
    pat.add_color_stop_rgb(1, 0.03, 0.04, 0.07)
    ctx.rectangle(0, 0, WIDTH, HEIGHT)
    ctx.set_source(pat)
    ctx.fill()

    # Top Master Header Banner
    draw_rounded_rect(ctx, 40, 30, WIDTH - 80, 100, 16)
    ctx.set_source_rgb(0.12, 0.16, 0.24)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.25, 0.35, 0.52)
    ctx.set_line_width(2.5)
    ctx.stroke()

    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(32)
    ctx.set_source_rgb(0.95, 0.96, 0.98)
    ctx.move_to(70, 75)
    ctx.show_text("Heterogeneous SoC Architecture: PS/PL Acceleration on Digilent Cora Z7-10")

    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(18)
    ctx.set_source_rgb(0.65, 0.75, 0.88)
    ctx.move_to(70, 108)
    ctx.show_text("Xilinx Zynq-7010 (XC7Z010-1CLG400C) | ARM Cortex-A9 @ 667 MHz + True Dual-Port BRAM Decoupled LZSS & AES-128-CTR Accelerators")

    # Author and board tags
    ctx.set_font_size(16)
    ctx.set_source_rgb(0.40, 0.70, 0.95)
    ctx.move_to(WIDTH - 550, 75)
    ctx.show_text("DELT UFMG - Sistemas em Silício")
    ctx.set_source_rgb(0.65, 0.75, 0.88)
    ctx.move_to(WIDTH - 550, 105)
    ctx.show_text("Luis H. R. M. C. | Academic Year 2026")

    # =========================================================================
    # 1. External Stimulus Domain (ESP32-WROOM-32) - Left Column
    # =========================================================================
    draw_card(ctx, 50, 160, 480, 960, (0.10, 0.14, 0.20), (0.18, 0.55, 0.85),
              "EXTERNAL STIMULUS (ESP32-WROOM)", "SPI Master Link")

    items_esp = [
        ("Core Architecture", "Xtensa 32-bit Dual-Core LX6 @ 240 MHz"),
        ("Firmware Stack", "ESP-IDF v6.1 FreeRTOS Bare-Metal Injector"),
        ("Physical Interface", "SPI Master (Mode 0, MSB-First, Up to 25 MHz)"),
        ("Frame Framing", "Preamble 0xA55A | SeqID [31:0] | Reserved [15:0]"),
        ("Payload Spectrum", "Dynamic Cycling: 64 B, 256 B, 512 B, 1024 B"),
        ("Integrity & Guard", "CRC-16 CCITT (0x1021) + EOF Delimiter 0x5A"),
        ("Autonomous Trigger", "Active-Low Handshake on GPIO 32 (Ext Int)")
    ]

    y_pos = 230
    for title, desc in items_esp:
        draw_rounded_rect(ctx, 70, y_pos, 440, 68, 8)
        ctx.set_source_rgb(0.14, 0.18, 0.26)
        ctx.fill_preserve()
        ctx.set_source_rgb(0.24, 0.32, 0.44)
        ctx.set_line_width(1.5)
        ctx.stroke()

        ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        ctx.set_font_size(15)
        ctx.set_source_rgb(0.35, 0.75, 0.98)
        ctx.move_to(85, y_pos + 26)
        ctx.show_text(title)

        ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        ctx.set_font_size(13)
        ctx.set_source_rgb(0.85, 0.88, 0.92)
        ctx.move_to(85, y_pos + 50)
        ctx.show_text(desc)
        y_pos += 82

    # Physical Pinout Mapping Box on ESP32
    draw_rounded_rect(ctx, 70, 810, 440, 280, 8)
    ctx.set_source_rgb(0.12, 0.15, 0.22)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.85, 0.45, 0.15)
    ctx.set_line_width(2.0)
    ctx.stroke()

    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(16)
    ctx.set_source_rgb(0.95, 0.55, 0.20)
    ctx.move_to(85, 840)
    ctx.show_text("PHYSICAL HEADER J7 / PMOD JA PINOUT")

    pins = [
        ("SPI SCLK", "ESP32 GPIO 18  ->  Cora Z7 J7.3 (Pin H15)"),
        ("SPI MOSI", "ESP32 GPIO 23  ->  Cora Z7 J7.4 (Pin T12)"),
        ("SPI MISO", "ESP32 GPIO 19  <-  Cora Z7 J7.1 (Pin W15)"),
        ("SPI SS_N", "ESP32 GPIO 5   ->  Cora Z7 J7.5 (Pin F16)"),
        ("BURST TRIG", "ESP32 GPIO 32  <-  Cora Z7 PMOD JA1 (Pin Y18)"),
        ("GROUND", "Common GND     <-> Cora Z7 Header GND")
    ]
    py = 875
    for p_name, p_desc in pins:
        ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        ctx.set_font_size(13)
        ctx.set_source_rgb(0.9, 0.9, 0.9)
        ctx.move_to(85, py)
        ctx.show_text(f"{p_name:<11} : {p_desc}")
        py += 33

    # =========================================================================
    # 2. Processing System Domain (PS - Zynq-7010) - Middle Top
    # =========================================================================
    draw_card(ctx, 580, 160, 960, 520, (0.10, 0.14, 0.20), (0.22, 0.65, 0.35),
              "PROCESSING SYSTEM 7 (PS - Cortex-A9 @ 667 MHz)", "Bare-Metal BSP / Standalone OS")

    # Inner PS Subcomponents
    # Cortex-A9 Core
    draw_rounded_rect(ctx, 610, 230, 430, 160, 10)
    ctx.set_source_rgb(0.14, 0.20, 0.18)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.28, 0.72, 0.42)
    ctx.set_line_width(2.0)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(18)
    ctx.set_source_rgb(0.40, 0.92, 0.55)
    ctx.move_to(630, 262)
    ctx.show_text("ARM Cortex-A9 MPCore (Core 0)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.85, 0.92, 0.88)
    ctx.move_to(630, 292)
    ctx.show_text("• 667 MHz Peak Frequency | VFPv3-D32 + NEON SIMD")
    ctx.move_to(630, 316)
    ctx.show_text("• 32 KB L1 Instruction + 32 KB L1 Data Caches")
    ctx.move_to(630, 340)
    ctx.show_text("• ARM PMU (CP15 Cycle Counter, 29 Cyc Overhead)")
    ctx.move_to(630, 364)
    ctx.show_text("• Golden Software Pipeline (Heatshrink + NIST AES-CTR)")

    # DDR3 Memory Controller
    draw_rounded_rect(ctx, 1070, 230, 440, 160, 10)
    ctx.set_source_rgb(0.14, 0.18, 0.24)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.35, 0.55, 0.80)
    ctx.set_line_width(2.0)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(18)
    ctx.set_source_rgb(0.45, 0.75, 0.98)
    ctx.move_to(1090, 262)
    ctx.show_text("DDR3 Memory Controller (512 MB)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.85, 0.90, 0.95)
    ctx.move_to(1090, 292)
    ctx.show_text("• 16-bit Bus @ 533 MHz (1066 Mbps DDR3-1066)")
    ctx.move_to(1090, 316)
    ctx.show_text("• Staging Ingress Telemetry Buffers (Raw / Cipher)")
    ctx.move_to(1090, 340)
    ctx.show_text("• High-Precision Timing Calibration & Logging Arrays")
    ctx.move_to(1090, 364)
    ctx.show_text("• Zero Dynamic Allocation (Deterministic MISRA C)")

    # PS Peripherals Strip (DEVCFG, EMIO GPIO, Master AXI)
    draw_rounded_rect(ctx, 610, 410, 900, 120, 8)
    ctx.set_source_rgb(0.12, 0.16, 0.22)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.45, 0.55, 0.70)
    ctx.set_line_width(1.5)
    ctx.stroke()

    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(15)
    ctx.set_source_rgb(0.85, 0.90, 0.95)
    ctx.move_to(630, 440)
    ctx.show_text("PS Control Peripherals & Interconnect Anchors:")

    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.75, 0.82, 0.90)
    ctx.move_to(630, 470)
    ctx.show_text("• DEVCFG: Address 0xF800700C (Bit 2 PCFG_DONE Interlock - Prevents CPU Bus Hangs)")
    ctx.move_to(630, 495)
    ctx.show_text("• EMIO GPIO: 1-Bit Slice routed to PMOD JA1 (Pin Y18) for Autonomous 30 ms ESP32 Trigger")
    ctx.move_to(630, 520)
    ctx.show_text("• M_AXI_GP0: 32-bit AXI Master Interface driving PL Interconnect @ 50 MHz (Synchronous)")

    # Status / Address Base Box inside PS
    draw_rounded_rect(ctx, 610, 545, 900, 115, 8)
    ctx.set_source_rgb(0.08, 0.12, 0.16)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.25, 0.45, 0.65)
    ctx.set_line_width(1.5)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(14)
    ctx.set_source_rgb(0.35, 0.75, 0.98)
    ctx.move_to(630, 575)
    ctx.show_text("AXI Address Map Master Table (M_AXI_GP0):")
    ctx.select_font_face("Monospace", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(12)
    ctx.set_source_rgb(0.85, 0.92, 0.88)
    ctx.move_to(630, 600)
    ctx.show_text("0x41E00000 : AXI Quad SPI 0 (Ingress FIFO) | 0x43C00000 : LZSS Accel CSRs")
    ctx.move_to(630, 622)
    ctx.show_text("0x43C10000 : AES-128-CTR Accel CSRs       | 0x40000000 : LZSS In BRAM (8 KB)")
    ctx.move_to(630, 644)
    ctx.show_text("0x40002000 : LZSS Out BRAM (8 KB)         | 0x40010000 : AES In BRAM (8 KB) | 0x40012000 : AES Out BRAM")

    # =========================================================================
    # 3. Programmable Logic Domain (PL - Artix-7 Fabric) - Right & Center Bottom
    # =========================================================================
    draw_card(ctx, 1580, 160, 1560, 1580, (0.09, 0.12, 0.17), (0.75, 0.35, 0.20),
              "PROGRAMMABLE LOGIC (PL - Artix-7 Fabric)", "FPGA Accelerators & BRAM Memory Hierarchy")

    # --- AXI Interconnect Crossbar ---
    draw_rounded_rect(ctx, 1620, 230, 1480, 85, 10)
    ctx.set_source_rgb(0.14, 0.18, 0.25)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.30, 0.50, 0.80)
    ctx.set_line_width(2.5)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(20)
    ctx.set_source_rgb(0.45, 0.75, 0.98)
    ctx.move_to(1650, 270)
    ctx.show_text("AXI Interconnect: ps7_0_axi_periph (Crossbar + Clock Converters 50M -> 100M)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(14)
    ctx.set_source_rgb(0.80, 0.85, 0.90)
    ctx.move_to(1650, 298)
    ctx.show_text("Demultiplexes M_AXI_GP0 into 7 Master Channels: 1x SPI IP, 2x Accel CSRs, 4x AXI BRAM Controllers")

    # --- Subsystem A: Ingress AXI Quad SPI ---
    draw_rounded_rect(ctx, 1620, 345, 1480, 160, 10)
    ctx.set_source_rgb(0.12, 0.16, 0.22)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.85, 0.55, 0.20)
    ctx.set_line_width(2.0)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(18)
    ctx.set_source_rgb(0.95, 0.65, 0.25)
    ctx.move_to(1650, 380)
    ctx.show_text("Unified Ingress: axi_quad_spi_0 (Base: 0x41E00000)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.85, 0.88, 0.92)
    ctx.move_to(1650, 412)
    ctx.show_text("• Slave Mode 0 (CPOL=0, CPHA=0) with 256-Byte Hardware FIFO | Status Register SPISR = 0x25")
    ctx.move_to(1650, 436)
    ctx.show_text("• Physical Pins: SCLK (H15), MOSI (T12), MISO (W15), SS (F16) connected to Cora Z7 Shield Header J7")
    ctx.move_to(1650, 460)
    ctx.show_text("• Firmware Ingestion Service drains FIFO over AXI4-Lite into DDR3 staging buffers before hardware offload")
    ctx.move_to(1650, 484)
    ctx.show_text("• Zero Frame Corruption: 100% CRC-16 CCITT parity verified across 64 B to 1024 B payloads")

    # --- Subsystem B: LZSS Compression Core & BRAMs ---
    draw_rounded_rect(ctx, 1620, 535, 1480, 560, 12)
    ctx.set_source_rgb(0.11, 0.14, 0.18)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.20, 0.60, 0.70)
    ctx.set_line_width(2.5)
    ctx.stroke()

    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(20)
    ctx.set_source_rgb(0.30, 0.85, 0.95)
    ctx.move_to(1650, 575)
    ctx.show_text("HARDWARE ACCELERATOR 1: lzss_accel (Sliding-Window Dictionary Compressor)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(14)
    ctx.set_source_rgb(0.75, 0.85, 0.90)
    ctx.move_to(1650, 602)
    ctx.show_text("Base CSR: 0x43C00000 | FCLK1 = 100 MHz | Window = 256 Bytes | Lookahead = 16 Bytes | Heatshrink Bit-Exact Format")

    # LZSS Input BRAM Box
    draw_rounded_rect(ctx, 1650, 630, 430, 260, 8)
    ctx.set_source_rgb(0.14, 0.18, 0.22)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.30, 0.65, 0.50)
    ctx.set_line_width(1.8)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(16)
    ctx.set_source_rgb(0.40, 0.85, 0.65)
    ctx.move_to(1670, 665)
    ctx.show_text("Input BRAM (bmg_lzss_in)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.85, 0.90, 0.88)
    ctx.move_to(1670, 700)
    ctx.show_text("• Capacity: 8 KB (2048 x 32-bit words)")
    ctx.move_to(1670, 725)
    ctx.show_text("• Port A: AXI BRAM Controller @ 0x40000000")
    ctx.move_to(1670, 750)
    ctx.show_text("  (PS writes raw telemetry frames via MMIO)")
    ctx.move_to(1670, 775)
    ctx.show_text("• Port B: Native Synchronous Accelerator Bus")
    ctx.move_to(1670, 800)
    ctx.show_text("  (clk, addr[12:0], din, dout[31:0], we)")
    ctx.move_to(1670, 825)
    ctx.show_text("• True Dual-Port Independent Clocks & BRAM")

    # LZSS RTL Engine Box
    draw_rounded_rect(ctx, 2110, 630, 480, 260, 8)
    ctx.set_source_rgb(0.16, 0.20, 0.26)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.35, 0.75, 0.95)
    ctx.set_line_width(2.0)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(16)
    ctx.set_source_rgb(0.45, 0.85, 0.98)
    ctx.move_to(2130, 665)
    ctx.show_text("lzss_accel RTL Core (VHDL-2008)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.85, 0.90, 0.95)
    ctx.move_to(2130, 700)
    ctx.show_text("• FSM: IDLE -> READ_IN -> SEARCH -> EMIT -> WRITE")
    ctx.move_to(2130, 725)
    ctx.show_text("• Sliding Window: 256 B circular buffer search")
    ctx.move_to(2130, 750)
    ctx.show_text("• Variable-length bitstream packer & flag byte")
    ctx.move_to(2130, 775)
    ctx.show_text("• Local 32-bit PL Hardware Cycle Counter")
    ctx.move_to(2130, 800)
    ctx.show_text("• Resources: 2,840 LUTs | 1,420 FFs | 2 BRAMs")
    ctx.move_to(2130, 825)
    ctx.show_text("• Empirical PL Latency: 269,675 cyc (1024 B)")

    # LZSS Output BRAM Box
    draw_rounded_rect(ctx, 2620, 630, 450, 260, 8)
    ctx.set_source_rgb(0.14, 0.18, 0.22)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.30, 0.65, 0.50)
    ctx.set_line_width(1.8)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(16)
    ctx.set_source_rgb(0.40, 0.85, 0.65)
    ctx.move_to(2640, 665)
    ctx.show_text("Output BRAM (bmg_lzss_out)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.85, 0.90, 0.88)
    ctx.move_to(2640, 700)
    ctx.show_text("• Capacity: 8 KB (2048 x 32-bit words)")
    ctx.move_to(2640, 725)
    ctx.show_text("• Port B: Native Synchronous Accelerator Bus")
    ctx.move_to(2640, 750)
    ctx.show_text("  (Accelerator writes compressed tokens)")
    ctx.move_to(2640, 775)
    ctx.show_text("• Port A: AXI BRAM Controller @ 0x40002000")
    ctx.move_to(2640, 800)
    ctx.show_text("  (PS reads back compressed bitstream)")
    ctx.move_to(2640, 825)
    ctx.show_text("• Comp. Ratio: 54.9% (1024 B -> 562 B)")

    # Memory Access Bottleneck Warning Banner inside LZSS
    draw_rounded_rect(ctx, 1650, 910, 1420, 65, 8)
    ctx.set_source_rgb(0.22, 0.12, 0.12)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.85, 0.35, 0.35)
    ctx.set_line_width(1.8)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(14)
    ctx.set_source_rgb(1.0, 0.45, 0.45)
    ctx.move_to(1670, 936)
    ctx.show_text("MICROARCHITECTURAL BOTTLENECK ANALYSIS (RISK R9):")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.92, 0.82, 0.82)
    ctx.move_to(1670, 960)
    ctx.show_text("Sequential BRAM Port B linear search @ 100 MHz requires up to 768 cyc/byte. Cortex-A9 @ 667 MHz with L1/L2 cache completes faster (0.596 ms vs 0.951 ms).")

    # --- Subsystem C: AES-128-CTR Encryption Core & BRAMs ---
    draw_rounded_rect(ctx, 1620, 1120, 1480, 580, 12)
    ctx.set_source_rgb(0.11, 0.14, 0.18)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.65, 0.25, 0.55)
    ctx.set_line_width(2.5)
    ctx.stroke()

    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(20)
    ctx.set_source_rgb(0.88, 0.45, 0.82)
    ctx.move_to(1650, 1160)
    ctx.show_text("HARDWARE ACCELERATOR 2: aes_accel (NIST SP 800-38A AES-128-CTR Cryptographic Engine)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(14)
    ctx.set_source_rgb(0.85, 0.75, 0.85)
    ctx.move_to(1650, 1187)
    ctx.show_text("Base CSR: 0x43C10000 | FCLK1 = 100 MHz | 10-Round Iterative Pipeline | Keystream XOR | 11 Cycles / 16-Byte Block")

    # AES Input BRAM Box
    draw_rounded_rect(ctx, 1650, 1215, 430, 260, 8)
    ctx.set_source_rgb(0.14, 0.18, 0.22)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.30, 0.65, 0.50)
    ctx.set_line_width(1.8)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(16)
    ctx.set_source_rgb(0.40, 0.85, 0.65)
    ctx.move_to(1670, 1250)
    ctx.show_text("Input BRAM (bmg_aes_in)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.85, 0.90, 0.88)
    ctx.move_to(1670, 1285)
    ctx.show_text("• Capacity: 8 KB (2048 x 32-bit words)")
    ctx.move_to(1670, 1310)
    ctx.show_text("• Port A: AXI BRAM Controller @ 0x40010000")
    ctx.move_to(1670, 1335)
    ctx.show_text("  (PS writes compressed payload for encryption)")
    ctx.move_to(1670, 1360)
    ctx.show_text("• Port B: Native Synchronous Accelerator Bus")
    ctx.move_to(1670, 1385)
    ctx.show_text("  (Acc reads 128-bit blocks into cipher)")
    ctx.move_to(1670, 1410)
    ctx.show_text("• Dual-port isolation prevents bus contention")

    # AES RTL Engine Box
    draw_rounded_rect(ctx, 2110, 1215, 480, 260, 8)
    ctx.set_source_rgb(0.20, 0.14, 0.20)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.85, 0.40, 0.75)
    ctx.set_line_width(2.0)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(16)
    ctx.set_source_rgb(0.95, 0.55, 0.88)
    ctx.move_to(2130, 1250)
    ctx.show_text("aes_accel RTL Core (VHDL-2008)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.92, 0.85, 0.92)
    ctx.move_to(2130, 1285)
    ctx.show_text("• SubBytes (S-Box) -> ShiftRows -> MixColumns")
    ctx.move_to(2130, 1310)
    ctx.show_text("• 128-bit Round Key Expansion on-the-fly")
    ctx.move_to(2130, 1335)
    ctx.show_text("• Big-Endian Counter Increment & Keystream XOR")
    ctx.move_to(2130, 1360)
    ctx.show_text("• Local 32-bit PL Hardware Cycle Counter")
    ctx.move_to(2130, 1385)
    ctx.show_text("• Resources: 3,410 LUTs | 2,150 FFs | 2 BRAMs")
    ctx.move_to(2130, 1410)
    ctx.show_text("• Measured PL Cycles: 829 cyc (1024 B payload)")

    # AES Output BRAM Box
    draw_rounded_rect(ctx, 2620, 1215, 450, 260, 8)
    ctx.set_source_rgb(0.14, 0.18, 0.22)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.30, 0.65, 0.50)
    ctx.set_line_width(1.8)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(16)
    ctx.set_source_rgb(0.40, 0.85, 0.65)
    ctx.move_to(2640, 1250)
    ctx.show_text("Output BRAM (bmg_aes_out)")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.85, 0.90, 0.88)
    ctx.move_to(2640, 1285)
    ctx.show_text("• Capacity: 8 KB (2048 x 32-bit words)")
    ctx.move_to(2640, 1310)
    ctx.show_text("• Port B: Native Synchronous Accelerator Bus")
    ctx.move_to(2640, 1335)
    ctx.show_text("  (Acc writes ciphertext blocks in real-time)")
    ctx.move_to(2640, 1360)
    ctx.show_text("• Port A: AXI BRAM Controller @ 0x40012000")
    ctx.move_to(2640, 1385)
    ctx.show_text("  (PS retrieves encrypted frame for staging/ACK)")
    ctx.move_to(2640, 1410)
    ctx.show_text("• 100% NIST SP 800-38A Golden Parity Verified")

    # Peak Speedup Highlight Banner inside AES
    draw_rounded_rect(ctx, 1650, 1495, 1420, 75, 8)
    ctx.set_source_rgb(0.12, 0.22, 0.16)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.35, 0.85, 0.45)
    ctx.set_line_width(1.8)
    ctx.stroke()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(15)
    ctx.set_source_rgb(0.45, 1.0, 0.55)
    ctx.move_to(1670, 1523)
    ctx.show_text("PEAK HETEROGENEOUS ACCELERATION (CENÁRIO 3: SW LZSS + PL AES-CTR):")
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.85, 0.95, 0.88)
    ctx.move_to(1670, 1548)
    ctx.show_text("AES hardware offload eliminates 360,000 CPU cycles in pure SW! 256 B: 0.381 ms (vs 0.596 ms SW) -> 1.56x Net System Speedup (0.64 MB/s Throughput).")

    # =========================================================================
    # 4. Bus Routing & Interconnect Arrows
    # =========================================================================
    # A) ESP32 to Ingress SPI (Physical Off-Chip Link)
    draw_arrow(ctx, 530, 425, 1620, 425, (0.95, 0.60, 0.20), 4.0, 14,
               "Physical SPI Link: Header J7 (H15, T12, W15, F16)", "top")

    # B) PS PMOD JA1 to ESP32 Trigger
    draw_arrow(ctx, 610, 495, 530, 495, (0.35, 0.85, 0.95), 3.5, 12,
               "PMOD JA1 (Y18) -> ESP32 GPIO 32 Trigger", "bottom")

    # C) PS M_AXI_GP0 to PL AXI Interconnect
    draw_arrow(ctx, 1540, 272, 1620, 272, (0.30, 0.65, 0.95), 5.0, 15,
               "M_AXI_GP0 (50 MHz)", "top")

    # D) Interconnect to AXI Quad SPI
    draw_arrow(ctx, 2360, 315, 2360, 345, (0.30, 0.65, 0.95), 3.5, 12,
               "AXI4-Lite: 0x41E00000", "right")

    # E) Interconnect to LZSS Input BRAM Ctrl
    draw_arrow(ctx, 1865, 315, 1865, 630, (0.30, 0.70, 0.45), 3.5, 12,
               "AXI BRAM Ctrl: 0x40000000", "left")

    # F) Interconnect to LZSS Accel CSRs
    draw_arrow(ctx, 2350, 315, 2350, 630, (0.30, 0.65, 0.95), 3.5, 12,
               "AXI4-Lite CSRs: 0x43C00000", "right")

    # G) Interconnect to LZSS Output BRAM Ctrl
    draw_arrow(ctx, 2845, 315, 2845, 630, (0.30, 0.70, 0.45), 3.5, 12,
               "AXI BRAM Ctrl: 0x40002000", "right")

    # H) Interconnect to AES Input BRAM Ctrl
    draw_arrow(ctx, 1865, 890, 1865, 1215, (0.30, 0.70, 0.45), 3.5, 12,
               "AXI BRAM Ctrl: 0x40010000", "left")

    # I) Interconnect to AES Accel CSRs
    draw_arrow(ctx, 2350, 890, 2350, 1215, (0.30, 0.65, 0.95), 3.5, 12,
               "AXI4-Lite CSRs: 0x43C10000", "right")

    # J) Interconnect to AES Output BRAM Ctrl
    draw_arrow(ctx, 2845, 890, 2845, 1215, (0.30, 0.70, 0.45), 3.5, 12,
               "AXI BRAM Ctrl: 0x40012000", "right")

    # K) Native BRAM Port B (LZSS In -> Engine -> LZSS Out)
    draw_arrow(ctx, 2080, 760, 2110, 760, (0.80, 0.40, 0.85), 3.5, 12,
               "Native Port B", "top")
    draw_arrow(ctx, 2590, 760, 2620, 760, (0.80, 0.40, 0.85), 3.5, 12,
               "Native Port B", "top")

    # L) Native BRAM Port B (AES In -> Engine -> AES Out)
    draw_arrow(ctx, 2080, 1345, 2110, 1345, (0.80, 0.40, 0.85), 3.5, 12,
               "Native Port B", "top")
    draw_arrow(ctx, 2590, 1345, 2620, 1345, (0.80, 0.40, 0.85), 3.5, 12,
               "Native Port B", "top")

    # =========================================================================
    # 5. Lower Summary: 12-Combination Empirical Matrix & Legend
    # =========================================================================
    draw_card(ctx, 580, 1140, 960, 600, (0.10, 0.14, 0.20), (0.70, 0.60, 0.25),
              "EMPIRICAL BENCHMARK CONSOLIDATION & SYSTEM METRICS", "12 Target Measurements")

    headers = ["Scenario", "Config", "Payload", "Latency", "CPU Cyc", "PL Cyc", "Speedup"]
    table_rows = [
        ("Case 1 (SW/SW)", "SW LZSS + SW AES", "256 B", "0.596 ms", "397,343", "0", "1.00x (Ref)"),
        ("Case 1 (SW/SW)", "SW LZSS + SW AES", "512 B", "2.024 ms", "1,349,888", "0", "1.00x (Ref)"),
        ("Case 1 (SW/SW)", "SW LZSS + SW AES", "1024 B", "4.846 ms", "3,232,400", "0", "1.00x (Ref)"),
        ("Case 2 (HW/SW)", "PL LZSS + SW AES", "256 B", "0.951 ms", "634,308", "25,631", "0.63x (R9)"),
        ("Case 2 (HW/SW)", "PL LZSS + SW AES", "512 B", "3.210 ms", "2,141,194", "107,539", "0.63x (R9)"),
        ("Case 2 (HW/SW)", "PL LZSS + SW AES", "1024 B", "7.695 ms", "5,132,354", "269,675", "0.63x (R9)"),
        ("Case 3 (SW/HW)", "SW LZSS + PL AES", "256 B", "0.381 ms", "254,021", "217", "1.56x (Peak)"),
        ("Case 3 (SW/HW)", "SW LZSS + PL AES", "512 B", "1.580 ms", "1,054,168", "421", "1.28x (Peak)"),
        ("Case 3 (SW/HW)", "SW LZSS + PL AES", "1024 B", "3.953 ms", "2,636,750", "829", "1.23x (Peak)"),
        ("Case 4 (HW/HW)", "PL LZSS + PL AES", "256 B", "0.734 ms", "489,777", "25,848", "0.81x"),
        ("Case 4 (HW/HW)", "PL LZSS + PL AES", "512 B", "2.767 ms", "1,845,887", "107,960", "0.73x"),
        ("Case 4 (HW/HW)", "PL LZSS + PL AES", "1024 B", "6.794 ms", "4,531,431", "270,504", "0.71x"),
    ]

    tx = 610
    ty = 1210
    col_w = [140, 160, 90, 100, 120, 100, 110]

    # Header row
    draw_rounded_rect(ctx, tx, ty, 900, 32, 4)
    ctx.set_source_rgb(0.20, 0.25, 0.35)
    ctx.fill()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(13)
    ctx.set_source_rgb(0.95, 0.95, 0.95)
    cur_x = tx + 10
    for h, w in zip(headers, col_w):
        ctx.move_to(cur_x, ty + 22)
        ctx.show_text(h)
        cur_x += w

    ty += 38
    ctx.select_font_face("Monospace", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(12)
    for row in table_rows:
        cur_x = tx + 10
        # Highlight Case 3
        if "Peak" in row[6]:
            ctx.set_source_rgb(0.40, 0.95, 0.55)
        elif "R9" in row[6]:
            ctx.set_source_rgb(1.0, 0.55, 0.55)
        else:
            ctx.set_source_rgb(0.85, 0.88, 0.92)

        for val, w in zip(row, col_w):
            ctx.move_to(cur_x, ty + 16)
            ctx.show_text(val)
            cur_x += w
        ty += 24

    # Legend strip at bottom of left domain
    draw_rounded_rect(ctx, 50, 1140, 480, 600, 12)
    ctx.set_source_rgb(0.10, 0.14, 0.20)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.45, 0.55, 0.65)
    ctx.set_line_width(2.0)
    ctx.stroke()

    draw_rounded_rect(ctx, 50, 1140, 480, 46, 12)
    ctx.set_source_rgb(0.25, 0.35, 0.45)
    ctx.fill()
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(18)
    ctx.set_source_rgb(1.0, 1.0, 1.0)
    ctx.move_to(70, 1172)
    ctx.show_text("BUS ARCHITECTURE & COLOR KEY")

    legend_items = [
        ((0.95, 0.60, 0.20), "Physical Off-Chip SPI & Trigger (Header J7 / PMOD JA)"),
        ((0.30, 0.65, 0.95), "AXI4-Lite Control Bus (CSRs @ 0x41E0/43C0/43C1)"),
        ((0.30, 0.70, 0.45), "AXI4 BRAM Memory Bus (Port A @ 0x4000/4001)"),
        ((0.80, 0.40, 0.85), "Native Synchronous BRAM Port B (RTL Engine Datapath)"),
        ((0.40, 0.92, 0.55), "ARM Cortex-A9 Processing System (PS @ 667 MHz)"),
        ((0.85, 0.45, 0.15), "Artix-7 Programmable Logic Fabric (PL @ 100 MHz)"),
    ]

    ly = 1220
    for col, text in legend_items:
        draw_rounded_rect(ctx, 75, ly, 28, 28, 6)
        ctx.set_source_rgb(*col)
        ctx.fill_preserve()
        ctx.set_source_rgb(1.0, 1.0, 1.0)
        ctx.set_line_width(1.5)
        ctx.stroke()

        ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        ctx.set_font_size(13)
        ctx.set_source_rgb(0.9, 0.9, 0.95)
        ctx.move_to(115, ly + 20)
        ctx.show_text(text)
        ly += 45

    # FPGA Resource summary inside legend box
    draw_rounded_rect(ctx, 70, 1510, 440, 205, 8)
    ctx.set_source_rgb(0.14, 0.18, 0.24)
    ctx.fill_preserve()
    ctx.set_source_rgb(0.35, 0.45, 0.60)
    ctx.set_line_width(1.5)
    ctx.stroke()

    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(15)
    ctx.set_source_rgb(0.45, 0.85, 0.98)
    ctx.move_to(85, 1540)
    ctx.show_text("TOTAL PL UTILIZATION (XC7Z010 Budget):")

    res_items = [
        ("LUTs (Logic)", "8,856 / 17,600", "50.3% Utilization"),
        ("Registers (FFs)", "12,047 / 35,200", "34.2% Utilization"),
        ("Block RAM (RAMB36)", "9.0 / 60", "15.0% Utilization"),
        ("DSP48E1 Slices", "0 / 80", "0.0% (Pure Logic)"),
        ("Worst Negative Slack", "+1.242 ns", "Timing MET (100 MHz)")
    ]
    ry = 1570
    for r_name, r_val, r_pct in res_items:
        ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        ctx.set_font_size(13)
        ctx.set_source_rgb(0.85, 0.88, 0.92)
        ctx.move_to(85, ry)
        ctx.show_text(f"{r_name:<20}: {r_val:<16} ({r_pct})")
        ry += 26


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[1/4] Generating 3200x1800 Image Surface for SoC Block Diagram...")
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, WIDTH, HEIGHT)
    ctx = cairo.Context(surface)
    render_diagram(ctx)

    print(f"[2/4] Saving high-resolution PNG: {PNG_FILE}...")
    surface.write_to_png(str(PNG_FILE))
    surface.write_to_png(str(ARCH_PNG))

    print(f"[3/4] Converting to high-quality JPG: {JPG_FILE}...")
    try:
        from PIL import Image
        img = Image.open(str(PNG_FILE))
        rgb_img = img.convert("RGB")
        rgb_img.save(str(JPG_FILE), quality=95)
    except Exception as e:
        print(f"[WARN] PIL conversion to JPG failed: {e}")

    print(f"[4/4] Generating vector PDF: {PDF_FILE}...")
    pdf_surface = cairo.PDFSurface(str(PDF_FILE), WIDTH, HEIGHT)
    pdf_ctx = cairo.Context(pdf_surface)
    render_diagram(pdf_ctx)
    pdf_surface.finish()

    print("[OK] All diagram deliverables generated successfully!")
    print(f"  - PNG: {PNG_FILE.relative_to(OUT_DIR.parents[1])}")
    print(f"  - JPG: {JPG_FILE.relative_to(OUT_DIR.parents[1])}")
    print(f"  - PDF: {PDF_FILE.relative_to(OUT_DIR.parents[1])}")

if __name__ == "__main__":
    main()
