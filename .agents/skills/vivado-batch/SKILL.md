---
name: vivado-batch
description: Non-interactive Vivado 2026.1 batch flow for project recreation, block design synthesis, implementation, timing/utilization closure, and fixed XSA platform export.
---

# Vivado Batch Flow Skill

Enforces a script-first, reproducible Vivado batch execution flow where no intermediate project databases (`.xpr`, `.gen/`, `.runs/`) are committed to Git.

## 1. When to Use
- Recreating the Vivado project from scratch using Tcl scripts.
- Running synthesis, placement, routing, and bitstream generation non-interactively.
- Inspecting timing summary reports (`WNS`, `WHS`, `TNS`) and resource utilization (LUTs, FFs, BRAMs).
- Exporting the verified `.xsa` hardware platform for the Vitis firmware workflow.

## 2. Directory Layout
- Tcl automation scripts: `cora7z/app/hw/scripts/`
  - `create_project.tcl`: Rebuilds the Vivado project, configures Zynq PS7, and adds Block Design IPs.
  - `build.tcl`: Launches synthesis and implementation runs, waits for completion, and writes bitstream.
  - `export_xsa.tcl`: Exports the `.xsa` container containing bitstream and hardware handoff.
  - `reports.tcl`: Generates timing, DRC, and utilization reports into `out/vivado_reports/`.
- Working directory: `cora7z/app/hw/vivado/` (git-ignored).

## 3. Canonical Commands

Always execute with the environment loaded (`source .agents/env.sh`):

```bash
# Run build from scripts inside the git-ignored vivado working directory
cd cora7z/app/hw/vivado
vivado -mode batch -notrace -source ../scripts/build.tcl
```

## 4. XSA Platform Export Protocol

In Vivado 2026.1, hardware export requires:
```tcl
open_run impl_1
write_hw_platform -fixed -include_bit -force -file cora7z/app/hw/vivado/cora7z_top.xsa
```

## 5. Convergence & Quality Gates
- **Zero Critical Warnings**: No `CRITICAL WARNING` allowed in synthesis or implementation logs.
- **Timing Closure**:
  - Worst Negative Slack (`WNS`) >= 0.000 ns
  - Worst Hold Slack (`WHS`) >= 0.000 ns
  - Total Negative Slack (`TNS`) == 0.000 ns
- **Resource Limits (Zynq-7010)**:
  - LUTs: <= 14,900 (~85% of 17,600)
  - FFs: <= 29,900 (~85% of 35,200)
  - BRAM (36Kb): <= 50 (~83% of 60)
