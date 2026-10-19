#!/usr/bin/env python3
"""
build_sw.py: Automated Vitis 2026.1 Unified Platform & Firmware Build Engine
=============================================================================
Configures the bare-metal software workspace on ARM Cortex-A9 (ps7_cortexa9_0)
using the Vitis 2026.1 Python API:
  1. Creates or updates the hardware platform component from cora7z_top.xsa.
  2. Generates and compiles the standalone Board Support Package (BSP).
  3. Creates or updates the embedded application component (cora7z_firmware).
  4. Copies application source files from cora7z/app/sw/src/.
  5. Compiles and links the application with ARM GCC, producing the .elf binary.
=============================================================================
"""

import sys
import os
import shutil
from pathlib import Path

# Identify repository root
script_dir = Path(__file__).resolve().parent
repo_root = script_dir.parents[3]

# Workspace and hardware artifact paths
workspace_dir = repo_root / "cora7z" / "app" / "sw" / "vitis"
xsa_path = repo_root / "cora7z" / "app" / "hw" / "vivado" / "cora7z_top.xsa"
src_dir = repo_root / "cora7z" / "app" / "sw" / "src"
out_dir = repo_root / "out" / "vitis" / "task_1.4"

out_dir.mkdir(parents=True, exist_ok=True)
workspace_dir.mkdir(parents=True, exist_ok=True)

# Remove stale workspace lock file if left over from previous process
lock_file = workspace_dir / "_ide" / ".wsdata" / ".lock"
if lock_file.is_file():
    try:
        lock_file.unlink()
        print("[VITIS] Removed stale workspace lock file.")
    except Exception as lock_err:
        print(f"[NOTE] Could not remove lock file: {lock_err}")

if not xsa_path.is_file():
    print(f"[FATAL] Hardware platform container '{xsa_path}' not found.", file=sys.stderr)
    sys.exit(1)

print("=" * 80)
print("[VITIS BUILD] Starting Automated Software Build Workflow")
print(f"[VITIS BUILD] Workspace:  {workspace_dir}")
print(f"[VITIS BUILD] XSA File:   {xsa_path}")
print(f"[VITIS BUILD] Source Dir: {src_dir}")
print("=" * 80)

try:
    import vitis
except ImportError as err:
    print(f"[FATAL] Failed to import 'vitis' module: {err}", file=sys.stderr)
    print("Ensure this script is executed via: vitis -s cora7z/app/sw/scripts/build_sw.py", file=sys.stderr)
    sys.exit(1)

# Initialize Vitis client
client = vitis.create_client()
client.set_workspace(path=str(workspace_dir))
print("[VITIS] Workspace initialized successfully.")

# -----------------------------------------------------------------------------
# 1. Platform Component Management
# -----------------------------------------------------------------------------
platform_name = "cora7z_platform"
platform = None

try:
    platform = client.get_component(name=platform_name)
    print(f"[VITIS] Found existing platform component '{platform_name}'.")
    try:
        platform.update_hw(hw_design=str(xsa_path))
        print("[VITIS] Platform hardware updated with latest XSA container.")
    except Exception as hw_err:
        print(f"[NOTE] Platform hardware update: {hw_err}")
except Exception:
    print(f"[VITIS] Creating new platform component '{platform_name}'...")
    platform = client.create_platform_component(
        name=platform_name,
        hw_design=str(xsa_path),
        os="standalone",
        cpu="ps7_cortexa9_0",
        domain_name="standalone_ps7_cortexa9_0",
        compiler="gcc"
    )
    print(f"[VITIS] Platform component '{platform_name}' created.")

print("[VITIS] Building platform component (compiling BSP and generating xparameters.h)...")
platform.build()
print("[VITIS] Platform component built successfully.")

# -----------------------------------------------------------------------------
# 2. Application Component Management
# -----------------------------------------------------------------------------
app_name = "cora7z_firmware"
app = None
xpfm_path = workspace_dir / platform_name / "export" / platform_name / f"{platform_name}.xpfm"

try:
    app = client.get_component(name=app_name)
    print(f"[VITIS] Found existing application component '{app_name}'.")
except Exception:
    print(f"[VITIS] Creating new application component '{app_name}'...")
    target_platform = str(xpfm_path) if xpfm_path.is_file() else platform_name
    app = client.create_app_component(
        name=app_name,
        platform=target_platform,
        domain="standalone_ps7_cortexa9_0"
    )
    print(f"[VITIS] Application component '{app_name}' created.")

# Synchronize source files into application component
app_src_dir = workspace_dir / app_name / "src"
app_src_dir.mkdir(parents=True, exist_ok=True)

for src_file in src_dir.glob("*.[ch]"):
    dest_file = app_src_dir / src_file.name
    shutil.copy2(src_file, dest_file)
    print(f"[VITIS] Copied '{src_file.name}' -> {dest_file}")

# -----------------------------------------------------------------------------
# 3. Application Compilation
# -----------------------------------------------------------------------------
print(f"[VITIS] Compiling application component '{app_name}'...")
try:
    app.build()
    print(f"[VITIS] Application '{app_name}' compiled successfully.")
except Exception as build_err:
    print(f"[FATAL] Application build failed: {build_err}", file=sys.stderr)
    client.close()
    sys.exit(1)

# Verify generated .elf
elf_candidates = list((workspace_dir / app_name).glob("**/*.elf"))
if elf_candidates:
    print(f"[SUCCESS] Generated executable binary: {elf_candidates[0]}")
    # Copy .elf to out_dir for archival and easy reference
    shutil.copy2(elf_candidates[0], out_dir / f"{app_name}.elf")
else:
    print("[WARNING] Build reported success, but no .elf file was detected.")

client.close()
print("=" * 80)
print("[VITIS BUILD] Workflow Completed Cleanly (Exit Code 0)")
print("=" * 80)
sys.exit(0)
