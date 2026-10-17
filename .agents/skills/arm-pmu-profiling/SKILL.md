---
name: arm-pmu-profiling
description: Cycle-accurate benchmark instrumentation on ARM Cortex-A9 using the Performance Monitor Unit (PMCCNTR/CP15), harness calibration, and statistical reporting.
---

# ARM PMU Profiling Skill

Enables cycle-accurate execution timing directly on the ARM Cortex-A9 cores using the hardware Performance Monitoring Unit (PMU).

## 1. When to Use
- Measuring CPU cycle consumption of RLE, LZ4, AES-CTR, and ChaCha20 in Scenario 1 (PS Pure).
- Measuring driver overhead and AXI descriptor management in Scenario 3 (Hybrid Co-Design).
- Calibrating measurement harness overhead.

## 2. Cortex-A9 CP15 PMU Access Routines

In bare-metal standalone ARM GCC, access to PMCCNTR is performed via inline assembly:

```c
#include <stdint.h>

// Enable the Performance Monitor Unit
static inline void pmu_enable(void) {
    uint32_t val = 1 | (1 << 2); // Enable counter + reset cycle counter
    __asm__ volatile("mcr p15, 0, %0, c9, c12, 0" :: "r"(val));
    // Enable cycle count register specifically
    uint32_t enable_cc = (1 << 31);
    __asm__ volatile("mcr p15, 0, %0, c9, c12, 1" :: "r"(enable_cc));
}

// Read the 32-bit Performance Monitor Cycle Counter (PMCCNTR)
static inline uint32_t pmu_read_cycles(void) {
    uint32_t cycles;
    __asm__ volatile("mrc p15, 0, %0, c9, c13, 0" : "=r"(cycles));
    return cycles;
}
```

## 3. Overhead Calibration & Measurement Protocol

1. **Harness Overhead Calibration**:
   Measure back-to-back reads of `pmu_read_cycles()` 100 times to determine baseline harness overhead ($C_{overhead}$) and subtract it from raw benchmark readings:
   $$\text{Cycles}_{actual} = \text{Cycles}_{raw} - C_{overhead}$$
2. **Warm-up**:
   Execute one discarded trial before taking official measurements to prime the L1 instruction and data caches.
3. **Statistical Validity**:
   Execute at least 10 independent trials for every block size (64 B to 64 KB). Compute and record both the arithmetic mean ($\mu$) and standard deviation ($\sigma$). If $\sigma / \mu > 5\%$, investigate background interrupts or cache thrashing.
4. **Latency Derivation**:
   At 667 MHz:
   $$\text{Latency (ms)} = \frac{\text{Cycles}}{667{,}000}$$
