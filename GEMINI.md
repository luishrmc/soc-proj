# Workspace Directives: PS/PL Compression and Encryption on Zynq-7010 (Digilent Cora Z7-10)

Language: all code, comments, hooks, skills, agent definitions and memory files are in English. The values inside `utils/plan/*.csv` stay in Portuguese because they are part of the course deliverable.

## 1. Scope and workspace map

Goal (details in `utils/TEMA.md`): implement and compare compression (RLE, LZ4/LZSS) and encryption (AES-CTR, ChaCha20) in three scenarios on the Zynq-7010: PS only (Cortex-A9 bare-metal C/C++), PL only (VHDL pipeline), and hybrid (PS controls, PL accelerates over AXI4). An ESP32 injects synthetic data over SPI (up to 25 MHz). Metrics: latency, ARM PMU cycles, throughput, FPGA resources.

| Path | Content |
|---|---|
| `cora7z/app/hw/src/` | VHDL sources (`*.vhdl`), plus `INTERFACES.md` (ports, AXI register map, SPI contract) |
| `cora7z/app/hw/test/` | VUnit testbenches (`tb_<name>.vhdl`) |
| `cora7z/app/hw/scripts/` | Vivado Tcl (project creation, build, XSA export, reports) |
| `cora7z/app/hw/utils/` | XDC constraints (protected) |
| `cora7z/app/hw/{Makefile,run.py}` | Simulation entry points |
| `cora7z/app/sw/` | Vitis workspace sources and scripts |
| `cora7z/app/test_results/` | Measurement CSVs (raw dumps are ignored by git) |
| `esp32/` | ESP32 injector (developed later) |
| `docs/` | Datasheets, manuals, diagrams, report |
| `utils/plan/` | Project management (CSVs, `STATUS.md`, `CHANGELOG.md`) |
| `utils/memory/` | Technical memory between iterations |
| `.agents/` | Agents, skills, hooks, manifest, env loader |
| `out/` | Hook outputs and gate evidence (ignored by git) |

## 2. Decision hierarchy (highest first)

1. Explicit user instruction.
2. Course delivery constraints (`utils/Projeto Final.pdf`, `utils/plan/Checklist_de_Entregaveis.csv`).
3. Hardware invariants (section 7).
4. `utils/TEMA.md`, then `utils/plan/*.csv`, then `INTERFACES.md`.
5. Style conventions.

If two levels conflict, stop and ask the user. Never resolve it silently.

## 3. Session protocol (read in this order, nothing else first)

1. This file and `utils/memory/INDEX.md`.
2. `utils/plan/STATUS.md` (what is done, what is next, blockers).
3. The task row in `utils/plan/Cronograma_e_Tarefas.csv` and `utils/memory/handoff/<task-id>.md` if it exists.
4. Digests in `utils/memory/modules/` for the modules the task depends on.
5. Source files only for the module being edited, or when `memory-check.py` reports a digest as STALE.
6. PDFs only through the `doc-lookup` skill (page and excerpt, never the whole PDF).

At the end of every iteration: update the handoff, refresh digests (`python3 .agents/hooks/memory-check.py --update <module>`), report to the orchestrator. At the end of a session: the orchestrator updates the plan with `plan-sync.py` and commits.

## 4. Multi-agent topology

Defined in `.agents/manifest.json` (single source for write globs, protected files, limits and gates) and `.agents/agents/*.md`.

| Agent | Model | Role |
|---|---|---|
| `orchestrator-agent` | pro | Task DAG, loop control, sole writer of `utils/plan/`, `decisions.md`, `lessons.md`, `INDEX.md` |
| `rtl-agent` | pro | VHDL RTL and VUnit testbenches |
| `vivado-integrator-agent` | pro | Vivado batch flow, AXI IPs, address map, XDC, XSA export |
| `firmware-agent` | pro | Vitis platform, bare-metal C/C++, AXI drivers, ARM PMU |
| `test-bench-agent` | flash | Runs the test matrix and collects metrics |
| `technical-critic-agent` | pro | Read-only adversarial review |
| `doc-agent` | flash | README, diagrams, report, delivery package |

Loops:
- **Inner loop**: the author edits, then deterministic gates run (`vhdl-lint`, `vhdl-sim`, ...). Failures go back to the author. No reviewer is involved.
- **Outer loop**: only after all gates pass, the critic reviews and answers `APPROVE` or `REJECT` with JSON.
- **Limits**: at most 5 failed iterations per task, and stop if the same error hash repeats twice (`loop-guard.py`). On stop: revert with git (never a hard reset), record it in `lessons.md`, escalate to the user.
- Parallel work is allowed only when each agent owns disjoint files (for example one RTL core per agent).

## 5. Tool governance

- Write access is limited to each agent's globs in `manifest.json`. `boundary-guard.py` verifies it after each agent step.
- Protected files (`*.xdc`, `INTERFACES.md`, `requirements.txt`, `manifest.json`) change only with explicit user approval (`ALLOW_PROTECTED=1`).
- Vivado commands: vivado-integrator-agent only. Vitis and ARM GCC: firmware-agent only. Simulation: rtl-agent. Git commits: orchestrator, through `git-safety-guard`.
- Always `source .agents/env.sh` before calling tools. Never edit the global PATH.
- Forbidden: `git reset --hard`, `git clean -fd`, `--no-verify`, `rm -rf` outside `out/` and `build/`, deleting plan or memory files.

## 6. Canonical commands

```bash
source .agents/env.sh                                   # load Vivado, Vitis, ARM GCC, GHDL, venv
make -C cora7z/app/hw venv                              # create .venv and install requirements.txt
make -C cora7z/app/hw test [TB=<substring>]             # VUnit + GHDL (the Makefile drives it)
make -C cora7z/app/hw list | clean | view TB=<name>     # list tests, clean, open GTKWave
TASK_ID=<id> bash .agents/hooks/vhdl-lint.sh            # static VHDL checks, records gate evidence
TASK_ID=<id> bash .agents/hooks/vhdl-sim-gate.sh        # simulation gate, records gate evidence
bash .agents/hooks/pre-task-audit.sh                    # before a task loop
python3 .agents/hooks/boundary-guard.py check --agent <name>
python3 .agents/hooks/loop-guard.py start|tick <task> [gate] [errfile]
python3 .agents/hooks/memory-check.py [--update <module>]
python3 .agents/hooks/plan-sync.py next|check|sync
python3 .agents/hooks/plan-sync.py set <task> "<status>" [--evidence gate:<id>|file:<path>] [--notes "..."]
```

## 7. Conventions and invariants (zero tolerance)

VHDL:
- VHDL-2008, `ieee.numeric_std` only (never `std_logic_arith`/`std_logic_unsigned`).
- One entity per file, file name equals entity name, extension `.vhdl`.
- Suffixes: `_i` input, `_o` output, `_io` bidirectional, `_r` registered signal, `_s` combinational signal, `_n` active low, `_c` constant, `_t` type. Names in `snake_case`.
- Synchronous design with a single rising-edge clock per domain. Clock-domain crossings use explicit synchronizers (SPI inputs always pass through one).
- No `wait for` or `after` in synthesizable code. No inferred latches.
- Every entity has a testbench `tb_<entity>.vhdl` using VUnit checks. A module without a passing testbench is not done.
- The same algorithm in C and VHDL must match the same golden vectors (RFC 8439 for ChaCha20, NIST for AES-CTR).

AXI and SoC:
- AXI4-Lite for control and status registers, AXI4-Stream or AXI4 full for data. The address map lives in `INTERFACES.md` and must equal Vivado's address editor and `xparameters.h`.
- No pin assignment without checking it against `docs/cora7z/Cora+Z7_sch-public.pdf` and the reference manual.

C/C++ (Cortex-A9 bare-metal):
- C11 or C++17, fixed-width types, `volatile` for MMIO, no dynamic allocation, `-Wall -Wextra -Werror`.
- Cycle counts come from the ARM PMU cycle counter. Calibrate its own overhead and run each measurement at least 10 times, reporting mean and standard deviation.

Evidence and honesty:
- Never write a performance number that was not measured. Never fill a result cell with an estimate.
- Never claim a build, simulation or synthesis passed without the matching hook exiting 0. A `SKIPPED` gate means the task is not complete.
- A task is `Concluída` only when `plan-sync.py` accepts its evidence.

## 8. Delivery constraints

Deliverables (see `utils/plan/Checklist_de_Entregaveis.csv`): VHDL sources, testbenches, C/C++ code (PS firmware and ESP32 injector), block diagram (PNG/JPG), final report (PDF), public GitHub repository, final `.zip`.
- The repository must reproduce on another computer: only sources, scripts, XDC, plans, memory and docs are versioned. Generated trees (Vivado project, Vitis workspace, simulation output, bitstreams) are ignored by `.gitignore`.
- No absolute paths in committed files except documented tool roots in `.agents/env.sh`. No secrets.
- The three scenarios and all rows of `Matriz_de_Testes_e_Métricas.csv` must be covered by real measurements.

## 9. File integrity

- Generated artifacts go only to `out/`, `build/` and `cora7z/app/test_results/`.
- `utils/plan/Cronograma_e_Tarefas.csv` keeps its original columns first. Only the orchestrator edits `utils/plan/`, and only through `plan-sync.py`.
- Before changing a protected or shared file, state which task and which decision justify it.
- Temporary smoke files (`smoke_counter.vhdl`, `tb_smoke_counter.vhdl`) are removed when task 2.1 starts.
