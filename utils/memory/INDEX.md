# Memory index

Read this first. Technical knowledge lives here, project management lives in `utils/plan/`.
Protocol: `.agents/skills/memory-protocol/SKILL.md`. Limit: 40 lines.

## Layout

| Path | Purpose | Writer |
|---|---|---|
| `modules/<module>.md` | Digest per RTL/SW module (interface, decisions, gates, source hashes) | owner agent |
| `handoff/<task-id>.md` | State between iterations of one task (overwritten each iteration) | task agent |
| `decisions.md` | Append-only ADR log | orchestrator |
| `lessons.md` | Tool quirks and recurring errors with fixes | orchestrator |
| `episodes/<task-id>.md` | One row per failed iteration (written by `loop-guard.py`) | hook |

## Active modules

- `interfaces`: SPI ingest framing, AXI4-Lite CSR map, AXI4-Stream datapath (`modules/interfaces.md`)
- `rle_engine`: Run-Length Encoding hardware accelerator core (`modules/rle_engine.md`)
- `lz4_engine`: LZ4 streaming compression accelerator core (`modules/lz4_engine.md`)
- `aes_ctr_engine`: AES-128-CTR cryptographic coprocessor core (`modules/aes_ctr_engine.md`)
- `chacha20_engine`: ChaCha20 stream cipher cryptographic coprocessor core (`modules/chacha20_engine.md`)
- `vitis_platform`: Vitis 2026.1 unified bare-metal platform & firmware baseline (`modules/vitis_platform.md`)
- `audit_pre_phase5`: Pre-Phase 5 comprehensive audit report (`audit_pre_phase5.md`)
- `pre_phase5_sanitization`: Pre-Phase 5.1 sanitization & golden verification (`pre_phase5_sanitization.md`)

## Active handoffs

None.

## Last compaction

Never (lessons.md has fewer than 80 lines).
