---
name: memory-protocol
description: Defines how agents read and maintain technical memory in utils/memory/ (INDEX.md, modules, handoffs, decisions, lessons, episodes) between iterations.
---

# Memory Protocol Skill

This skill governs the persistence of technical knowledge between task iterations, preventing agents from re-reading the entire project from scratch.

## 1. When to Use
- At the start of an iteration: to identify what to read (INDEX.md -> task handoff -> dependency digests).
- At the end of an iteration: to update the module digest, calculate SHA-256 hashes of sources, and overwrite the task handoff.
- When an architecture or tool decision is reached: to register an ADR in `utils/memory/decisions.md`.
- When encountering tool quirks or bugs: to record in `utils/memory/lessons.md`.

## 2. Directory Layout and Ownership

```
utils/memory/
├── INDEX.md               # Overview of active modules, handoffs, compaction date (<= 40 lines)
├── modules/               # Per-module technical digests (<= 60 lines each)
│   └── <module>.md        # Port list, register map, clocking, status, sha256 hashes
├── handoff/               # Intra-task state between iterations (<= 50 lines each)
│   ├── <task-id>.md       # Current objective, changes made, last error, next steps
│   └── done/              # Archived handoffs for completed tasks
├── decisions.md           # Append-only architectural decisions (ADR-NNN)
├── lessons.md             # Tool quirks and solutions (<= 80 lines)
└── episodes/              # Automated iteration logs from loop-guard.py
    └── <task-id>.md
```

## 3. Module Digest Format (`utils/memory/modules/<module>.md`)

Every module digest must include frontmatter with source SHA-256 hashes:

```markdown
---
module: spi_slave
status: verified
sources:
  - cora7z/app/hw/src/spi_slave.vhdl sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
gates_passed: [vhdl-lint, vhdl-sim]
---

# SPI Slave Receiver

## Interface
- `clk_i`: 50 MHz system clock
- `sclk_i`, `mosi_i`, `cs_n_i`: SPI slave bus (synchronized to clk_i)
- `data_o`: 8-bit output byte
- `valid_o`: 1-cycle strobe

## Resource Usage
- Estimated / Measured: 42 FFs, 35 LUTs, 0 BRAM.

## Operational Notes
- 2-stage synchronizer on all asynchronous SPI inputs.
```

To update hashes after editing sources, run:
```bash
python3 .agents/hooks/memory-check.py --update <module>
```

## 4. Handoff Format (`utils/memory/handoff/<task-id>.md`)

Overwritten on each iteration by the active agent:

```markdown
# Handoff: Task 2.1 (Iteration 2)

## Current Objective
Resolve hold-time violation on SPI clock synchronizer.

## Completed Changes
- Replaced direct input sampling with 2-stage shift register in `cora7z/app/hw/src/spi_slave.vhdl`.
- Added test case `fast_spi_burst` in `cora7z/app/hw/test/tb_spi_slave.vhdl`.

## Status of Gates
- `vhdl-lint`: PASS
- `vhdl-sim`: FAIL (assertion mismatch on byte 3)

## Next Action
Check FIFO write enable gating when `valid_o` is active.
```

## 5. Memory Verification
Before concluding any task or iteration, run:
```bash
python3 .agents/hooks/memory-check.py
```
If any digest is `STALE` or file exceeds line limits, the check exits with code 1.
