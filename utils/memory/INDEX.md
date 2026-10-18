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

## Active handoffs

None.

## Last compaction

Never (lessons.md has fewer than 80 lines).
