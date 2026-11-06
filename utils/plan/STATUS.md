# Project Status & Architectural Progress Tracking

> [!NOTE]
> **Engineering Status — Work-in-Progress (WIP: Testbench & Synthetic Data Pipeline):**  
> The 100% metric in the course syllabus table below marks completion of the baseline RTL modules, Vivado block designs, bare-metal C firmware scaffolding, and VUnit simulation suites.
>
> **Active Milestone Focus:**  
> Development of a **Python-based synthetic telemetry generator** that outputs realistic, time-series sensor streams (simulated temperature, 3-axis vibration, supply voltage, status bitmasks, and monotonic timestamps) with variable entropy and repetition profiles. This pipeline will stream benchmark payloads into the ESP32 injector and Cora Z7 platform.
>
> All quantitative benchmark performance metrics (cycle counts, latencies, throughputs, and speedups) are **Pending Measurement / WIP** awaiting systematic physical execution sweeps.

## Progress by Phase (Course Schedule Baseline)

| Phase | Done | Validation | In progress | Blocked | Pending | Total |
|---|---|---|---|---|---|---|
| 1 | 6 | 0 | 0 | 0 | 0 | 6 |
| 2 | 4 | 0 | 0 | 0 | 0 | 4 |
| 3 | 5 | 0 | 0 | 0 | 0 | 5 |
| 4 | 3 | 0 | 0 | 0 | 0 | 3 |
| 5 | 3 | 0 | 0 | 0 | 0 | 3 |

Estimated course schedule effort completed: 50 of 50 days (100% of baseline syllabus milestones).

## In Progress

- Development and integration of the Python synthetic telemetry generator pipeline.
- Preparation for systematic HIL benchmark matrix measurement sweeps.

## Waiting for Validation

None.

## Blocked

None.

## Next Eligible Tasks

- Execution and statistical consolidation of physical benchmark runs using the Python telemetry generator.

## Remaining Critical Path

1.1 (0 days)

## Open Technical Risks & Findings

- **R9** (Task 4.3): PL compression accelerator latency (LZSS) vs. PS software baseline — Architectural hypothesis under evaluation (sequential BRAM lookahead searches at 100 MHz vs. Cortex-A9 667 MHz L1 cache execution). Quantitative validation is pending execution with synthetic telemetry streams.
