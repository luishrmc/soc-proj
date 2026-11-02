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

- `interfaces`: SPI ingest framing, AXI4-Lite CSR map, Dual-Port BRAM memory layout (`modules/interfaces.md`)
- `lzss_accel`: LZSS sliding-window compression coprocessor with BRAM interface (`modules/lzss_accel.md`)
- `aes_accel`: AES-128-CTR cryptographic coprocessor with BRAM interface (`modules/aes_accel.md`)
- `vitis_platform`: Vitis 2026.1 unified bare-metal platform & firmware baseline (`modules/vitis_platform.md`)
- `esp32_injector`: ESP32 autonomous SPI synthetic data injector & telemetry logger (`modules/esp32_injector.md`)
- `pipeline_mgr`: Hybrid co-design driver & 4-scenario execution pipeline (`modules/pipeline_mgr.md`)


## Active handoffs

None.

## Last compaction

Never (lessons.md has fewer than 80 lines).
