# Lessons learned

Tool quirks and recurring errors. Keep under 80 lines. Format: `symptom -> cause -> fix`.

- `touch .venv/bin/python` fails with "Permission denied" -> it is a symlink to the system Python -> use a stamp file (`.venv/.installed`) as the Makefile target.
- VUnit logs contain ANSI color codes even when redirected -> `grep 'pass N of N'` finds nothing -> strip escapes with `sed 's/\x1b\[[0-9;]*m//g'` before parsing.
- `ghdl -m` rejects `-o` -> unknown command option -> run it inside the work directory with `--workdir=.`.
- GHDL warns "entity was also defined in file" on repeated lint runs -> stale `.cf` library in the work dir -> delete `out/ghdl` at the start of each lint run.
- Vivado, Vitis and ARM GCC are not on PATH -> `command not found` in hooks -> `source .agents/env.sh` (it never edits the global PATH).
- Reference project `exercises/slides/corez7` references `hw/scripts/build.tcl` but the file does not exist there -> do not copy that task blindly, write `cora7z/app/hw/scripts/build.tcl` here.
- Vitis 2026.1 uses the unified/SDT flow (`vitis-comp.json`, CMake + Ninja), not the classic XSCT SDK flow -> validate the platform script with a hello_world before integrating IPs (risk R1).
