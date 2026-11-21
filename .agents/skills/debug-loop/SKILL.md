---
name: debug-loop
description: Diagnose hard bugs, flaky failures, and performance regressions through a gated 6-phase red feedback loop. Use when the user asks to "diagnose" or "debug" an issue, or reports broken, throwing, failing, or slow behavior.
---

# Disciplined Bug Diagnosis Loop

Diagnose and resolve complex bugs and regressions through six sequentially gated phases. Read `GLOSSARY.md` and relevant `docs/adr/` records first, and replace any credentials or tokens in command outputs with `<REDACTED>`.

## Phase 1: Construct a Tight Red Feedback Loop

**This phase is the core discipline.** Build a reproducible, fast, automated pass/fail command that goes **red** on the exact bug before theorizing about causes or editing production code.

Select the tightest reproduction mechanism from [references/feedback-loops.md](./references/feedback-loops.md) (Failing Seam Test -> HTTP/CLI Script -> Headless Browser -> Trace Replay -> Minimal Harness -> Property/Fuzz Loop -> `git bisect run` -> Differential Loop -> HITL Script `scripts/hitl-loop.template.sh`).

### Tighten the Loop

Once a reproduction exists, tighten it: cache setup, narrow scope to seconds, pin time/RNG/network for determinism, and for flaky bugs loop the trigger under concurrency until the reproduction rate is high enough to debug reliably.

**Phase 1 Completion Criterion**: Name **one executable command** you have already run that is:

- [ ] **Red-capable**: exercises the bug path and asserts the exact reported symptom.
- [ ] **Deterministic** (or high-frequency pinned reproduction for flakes) and **Fast** (seconds, not minutes).

If no automated loop can be constructed, halt and ask the user for environment access, a redacted artifact (HAR/log dump), or permission for temporary instrumentation before forming hypotheses.

## Phase 2: Reproduce and Minimize

1. Execute the Phase 1 command and verify the failure matches the user's exact symptom.
2. **Minimize**: Strip away inputs, config, callers, and data one element at a time, re-running the loop after each cut.
3. **Done when**: Every remaining element in the reproduction is load-bearing (removing any single piece turns the loop green).

## Phase 3: Formulate Ranked Falsifiable Hypotheses

Generate **3 to 5 ranked hypotheses** before testing any single theory:

> **Format**: *"If `<root cause X>` is responsible, then `<probe or change Y>` will make the symptom disappear (or shift to `<Z>`)."*

Share the ranked list with the user if interactive, or proceed directly down the ranked order if running autonomously.

## Phase 4: Targeted Instrumentation

Test one hypothesis and one variable at a time:

1. Prefer debugger/REPL inspection or boundary assertions over broad logging.
2. Prefix every temporary diagnostic log with a unique tag (`[DEBUG-a4f2]`) for one-command cleanup.
3. For performance regressions, capture a baseline timing or profiler measurement before bisecting.

## Phase 5: Seam Regression Test and Fix

1. Convert the minimized Phase 2 reproduction into a permanent failing test at the appropriate public **seam** (`dev-tdd`). If the codebase lacks a clean seam capable of exercising the bug path, report the missing seam explicitly as an architectural finding for `/arch-survey`.
2. Apply the minimal fix and verify both the new seam regression test and the original un-minimized Phase 1 loop turn **green**.

## Phase 6: Cleanup Verification

- [ ] Original Phase 1 loop and new seam regression test pass.
- [ ] Zero `[DEBUG-...]` instrumentation or throwaway harness files remain (`git status` / `grep` verified).
- [ ] Confirmed root cause is recorded clearly in the commit or PR summary.
