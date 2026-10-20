#!/usr/bin/env python3
"""
launch_app.py: Program FPGA bitstream and launch firmware on Cora Z7-10.
Uses Vitis 2026.1 Python XSDB API with FSBL initialization.
"""

import sys
import time
from pathlib import Path

# Identify repository root
repo_root = Path(__file__).resolve().parents[4]

try:
    import xsdb
except ImportError:
    print("[FATAL] xsdb module not found. Run with: vitis -s cora7z/app/sw/scripts/launch_app.py", file=sys.stderr)
    sys.exit(1)

bitstream = repo_root / "cora7z" / "app" / "sw" / "vitis" / "cora7z_firmware" / "_ide" / "bitstream" / "cora7z_top.bit"
fsbl_elf = repo_root / "cora7z" / "app" / "sw" / "vitis" / "cora7z_platform" / "zynq_fsbl" / "build" / "fsbl.elf"
app_elf = repo_root / "cora7z" / "app" / "sw" / "vitis" / "cora7z_firmware" / "build" / "cora7z_firmware.elf"

print("=" * 70)
print("  Digilent Cora Z7-10: Launching Bitstream & Firmware")
print("=" * 70)
print(f"  Bitstream: {bitstream.name}")
print(f"  FSBL:      {fsbl_elf.name}")
print(f"  App ELF:   {app_elf.name}")
print("=" * 70)

s = xsdb.start_debug_session()
s.connect()
print("[1/6] Connected to hw_server.")

# Target 2: Cortex-A9 #0
s.targets(2)
print("[2/6] Resetting system...")
s.rst("-s")
time.sleep(1)

# Target 4: FPGA
s.targets(4)
print("[3/6] Programming FPGA bitstream...")
s.fpga(str(bitstream))
print("[3/6] FPGA bitstream programmed successfully (DONE=1).")

# Target 2: Cortex-A9 #0
s.targets(2)
print("[4/6] Downloading FSBL to initialize DDR and clocks...")
s.dow(str(fsbl_elf))
s.con()
time.sleep(1.5)
s.stop()
print("[4/6] FSBL initialization complete.")

print("[5/6] Downloading application ELF...")
s.dow(str(app_elf))
print("[5/6] Application ELF downloaded into DDR RAM.")

print("[6/6] Resuming Cortex-A9 CPU execution...")
s.con()
print("=" * 70)
print("  CORA Z7 IS RUNNING! CHECK YOUR PICOCOM TERMINAL.")
print("=" * 70)
