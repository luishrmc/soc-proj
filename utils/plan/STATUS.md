# Project Status & Architectural Progress Tracking

> [!NOTE]
> **Engineering Status — HIL Verification Complete (ADR-020: 4 Scenarios × 3 Profiles @ 1024 B):**
> Physical Hardware-in-the-Loop (HIL) execution between the ESP32 SPI injector (`2 MHz`, `GPIO 32` trigger, `seed=42`) and the Digilent Cora Z7-10 (`650 MHz` ARM Cortex-A9 PS / `100 MHz` Artix-7 PL) has completed cleanly across zero-drop `30/30` frame bursts (`N = 20` balanced samples per Entropy Profile: `Quiescent`, `Dynamic`, `Chaotic`), with calibrated ARM PMU (`28`-cycle overhead subtraction) and zero CRC/frame/length errors.

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

- Final technical report formatting and archival packaging (`Checklist_de_Entregaveis.csv`).

## Waiting for Validation

None.

## Blocked

None.

## Next Eligible Tasks

- Isolated standalone synthesis utilization characterization for Scenario 2 (`lzss_accel` only) and Scenario 3 (`aes_accel` only) to replace `"Pending"` resource cells in `Matriz_de_Testes_e_Métricas.csv`.

## Remaining Critical Path

1.1 (0 days)

## Open Technical Risks & Findings

- **R9** (Task 4.3): **Empirically Confirmed.** Sequential Port-B BRAM lookahead searches at `100 MHz` (`200,972–744,661` PL cycles) plus AXI MMIO BRAM transfer overhead make PL LZSS (`Scenario 2`: `0.63x`, `Scenario 4`: `0.69x–0.72x`) slower than Cortex-A9 L1/L2 cache execution at `650 MHz`. Conversely, **Scenario 3 (`SW LZSS + PL AES-CTR`)** achieves **1.17x–1.24x** end-to-end speedup across all entropy regimes (`668–1,679` PL cycles).
