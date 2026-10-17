---
name: vitis-build
description: Vitis 2026.1 unified CLI and Python workflow for creating standalone Cortex-A9 platforms from XSA containers and compiling bare-metal applications.
---

# Vitis Build Flow Skill

Automates the standalone bare-metal development environment on the Cortex-A9 using Vitis 2026.1 unified Python client and CMake/Ninja underlying build systems.

## 1. When to Use
- Creating or updating the Vitis hardware platform component from an exported `.xsa`.
- Creating and building standalone C/C++ application components for `ps7_cortexa9_0`.
- Compiling code with strict warning flags (`-Wall -Wextra -Werror`).
- Verifying hardware parameters in generated `xparameters.h`.

## 2. Environment Setup
Always source `.agents/env.sh` before executing Vitis commands:
```bash
source .agents/env.sh
```
This loads `/home/luis/Xilinx/2026.1/Vitis/bin` and `arm-none-eabi-gcc`.

## 3. Automation Script (`cora7z/app/sw/scripts/build_sw.py`)

In Vitis 2026.1, workspace configuration and builds are scripted using the Python API:

```python
import vitis
import sys
from pathlib import Path

workspace_dir = Path("cora7z/app/sw/vitis").resolve()
xsa_path = Path("cora7z/app/hw/vivado/cora7z_top.xsa").resolve()

client = vitis.create_client()
client.set_workspace(path=str(workspace_dir))

# 1. Create or update platform component
platform_name = "cora7z_platform"
try:
    platform = client.get_component(name=platform_name)
except Exception:
    platform = client.create_platform_component(
        name=platform_name,
        hw_design=str(xsa_path),
        os="standalone",
        cpu="ps7_cortexa9_0",
        domain_name="standalone_ps7_cortexa9_0",
        compiler="gcc"
    )

platform.build()

# 2. Build application component
app_name = "app_ps"
try:
    comp = client.get_component(name=app_name)
    comp.build()
    print("[OK] Application built successfully.")
except Exception as e:
    print(f"[FAIL] Build error: {e}", file=sys.stderr)
    sys.exit(1)
```

Run via:
```bash
vitis -s cora7z/app/sw/scripts/build_sw.py
```

## 4. Invariants
- The generated `platform/`, `_ide/`, and `build/` directories are strictly excluded by `.gitignore`.
- Only application source files (`cora7z/app/sw/src/`) and build scripts (`cora7z/app/sw/scripts/`) are versioned.
