# Lessons learned

Tool quirks and recurring errors. Keep under 80 lines. Format: `symptom -> cause -> fix`.

- `touch .venv/bin/python` fails with "Permission denied" -> it is a symlink to the system Python -> use a stamp file (`.venv/.installed`) as the Makefile target.
- VUnit logs contain ANSI color codes even when redirected -> `grep 'pass N of N'` finds nothing -> strip escapes with `sed 's/\x1b\[[0-9;]*m//g'` before parsing.
- `ghdl -m` rejects `-o` -> unknown command option -> run it inside the work directory with `--workdir=.`.
- GHDL warns "entity was also defined in file" on repeated lint runs -> stale `.cf` library in the work dir -> delete `out/ghdl` at the start of each lint run.
- Vivado, Vitis and ARM GCC are not on PATH -> `command not found` in hooks -> `source .agents/env.sh` (it never edits the global PATH).
- Reference project `exercises/slides/corez7` references `hw/scripts/build.tcl` but the file does not exist there -> do not copy that task blindly, write `cora7z/app/hw/scripts/build.tcl` here.
- Vitis 2026.1 uses the unified/SDT flow (`vitis-comp.json`, CMake + Ninja), not the classic XSCT SDK flow -> validate the platform script with a hello_world before integrating IPs (risk R1).
- Cortex-A9 hangs when reading unprogrammed PL registers -> `M_AXI_GP0` transactions stall indefinitely without slave response -> verify `Xil_In32(0xF800700C) & 0x04` (`PCFG_DONE` in DEVCFG) before PL MMIO.
- Vivado Place DRC over-utilization with multi-port combinational arrays -> sliding window arrays infer distributed LUT multiplexers instead of BRAM -> limit window sizes or convert to synchronous Block RAM.
- `xil_printf` on standalone Cortex-A9 does not support `%lu` -> prints corrupted large integers -> cast to `(unsigned int)` and format with `%u` or `%x`.
- Vivado Block Design module reference `.xci` caches old generics -> source changes do not automatically propagate to BD synthesis -> set property `CONFIG.<name>` explicitly in BD or reset BD synthesis runs.
- `update_module_reference` fails or does nothing when targeting `get_bd_cells` in batch Tcl -> module references are instantiated IP definitions -> run `update_module_reference [get_ips *<pattern>*]`.
- AES-128 combinational key expansion causes severe setup violation (WNS = -18.9 ns) due to 39 unrolled logic levels -> calculate round keys sequentially over 10 cycles -> drops delay to 2.2 ns.
- ChaCha20 quarter-rounds in 1 cycle violate 100 MHz timing (-2.8 ns) due to 4 chained additions (31 levels, 25 CARRY4s) -> split quarter-rounds into 2 half-rounds over 2 cycles -> closes timing cleanly (WNS = +0.21 ns).
