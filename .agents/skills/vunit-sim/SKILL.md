---
name: vunit-sim
description: Execution, filtering, waveform inspection, and automated diagnosis of VHDL testbenches using VUnit and GHDL through the Makefile harness.
---

# VUnit Simulation Skill

Drives the local simulation workflow using VUnit with GHDL as the simulator engine, mirroring the reference structure in `cora7z/app/hw/Makefile` and `cora7z/app/hw/run.py`.

## 1. When to Use
- Running all unit tests or filtered subsets of testbenches during RTL authoring.
- Opening waveform traces in GTKWave to debug unexpected signal transitions.
- Listing discovered testbenches and verifying test suite registration.
- Cleaning up simulation artifacts (`build/`, `vunit_out/`).

## 2. Directory Layout & Configuration
- Root Makefile: `cora7z/app/hw/Makefile`
- VUnit script: `cora7z/app/hw/run.py`
- Python environment: `.venv/bin/python` at repo root
- GHDL binary: `/opt/ghdl/bin/ghdl`

## 3. Canonical Makefile Commands

Always run from `cora7z/app/hw/`:

```bash
# Run all discovered tests
make test

# Run tests matching a specific substring (e.g., rle or chacha20)
make test TB=rle

# List all discovered testbenches without executing them
make list

# Open waveform in GTKWave for a specific testbench
make view TB=smoke_counter

# Clean build directory and temporary simulator outputs
make clean
```

## 4. Gate Integration
When called by automated task loops, the simulation gate hook wraps the Makefile execution and verifies that:
1. GHDL compiles without fatal errors.
2. VUnit discovers at least 1 testbench.
3. Every test case passes without an assertion failure.
4. An evidence JSON is written to `out/gates/<task>.json`.

Command:
```bash
TASK_ID=2.1 bash .agents/hooks/vhdl-sim-gate.sh [TB_FILTER]
```
