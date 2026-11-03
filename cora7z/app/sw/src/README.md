# Processing System Bare-Metal Firmware & Drivers (PS)
## ARM Cortex-A9 MPCore @ 667 MHz (Digilent Cora Z7-10)

This directory contains the C11 bare-metal firmware, AXI MMIO drivers, ARM Performance Monitor Unit (PMU) profiling routines, and self-testing verification suites for the Zynq-7000 Processing System (PS).

---

## 1. Module Overview & Architectural Role

The Cortex-A9 processor operates as the centralized supervisor of the heterogeneous SoC:
1. **Hardware Interlock & Safety (`main.c`):** Polls DEVCFG register `0xF800700C` bit 2 (`PCFG_DONE`) before issuing MMIO operations, preventing CPU bus lockups.
2. **Cycle-Accurate Profiling (`main.c`):** Accesses CP15 register `PMCCNTR` directly via inline assembly, subtracting calibrated measurement overhead (29 CPU cycles).
3. **Hybrid Offload Driver (`pipeline_mgr.c`):** Implements the 5-stage store-and-forward BRAM protocol, staging data into Port A and polling completion flags.
4. **Software Golden Models (`lzss_sw.c`, `aes_ctr_sw.c`):** Provides pure C11 reference implementations of Heatshrink and NIST SP 800-38A AES-128-CTR for baseline benchmarking and bit-exact hardware validation.
5. **SPI Ingress Service (`axi_spi_receiver.c`):** Drains the 256-byte FIFO of the LogiCORE `axi_quad_spi_0` core into DDR3 staging buffers, checking preamble, sequence numbers, and CRC-16 CCITT.

---

## 2. File Organization

| Source File | Header File | Primary Responsibility |
| :--- | :--- | :--- |
| `main.c` | --- | Boot banner, PMU calibration, DEVCFG check, test suite execution, continuous SPI loop |
| `pipeline_mgr.c` | `pipeline_mgr.h` | 4-scenario driver (Cases 1, 2, 3, 4), BRAM staging, CSR polling, watchdog timers |
| `test_sw_pipeline.c` | `test_sw_pipeline.h`| 5/5 self-test regression suite, 12-combination benchmark matrix sweep |
| `aes_ctr_sw.c` | `aes_ctr_sw.h` | Software AES-128-CTR reference implementation (NIST SP 800-38A) |
| `lzss_sw.c` | `lzss_sw.h` | Software LZSS/Heatshrink reference compressor |
| `axi_spi_receiver.c`| `axi_spi_receiver.h`| AXI Quad SPI driver, packet parser, CRC-16 verifier |
| `spi_frame.h` | --- | Shared frame structure definition with 32-bit word alignment padding |
| `axi_io.h` | --- | Low-level volatile MMIO read/write macros |

---

## 3. The 4 Pipeline Scenarios

The driver evaluates four distinct operational configurations:

```c
typedef enum {
    SCENARIO_CASE1_SW_SW = 1, // Pure Software Baseline (Cortex-A9 @ 667 MHz)
    SCENARIO_CASE2_HW_SW = 2, // PL LZSS Compression + SW AES-CTR Encryption
    SCENARIO_CASE3_SW_HW = 3, // SW LZSS Compression + PL AES-CTR Encryption (1.56x Speedup)
    SCENARIO_CASE4_HW_HW = 4  // Full Hardware Acceleration (PL LZSS + PL AES-CTR)
} pipeline_scenario_t;
```

---

## 4. Hardware Safety & Cryptographic Nonce Security

### 4.1 DEVCFG Interlock
```c
static inline bool is_pl_programmed(void) {
    // DEVCFG status register at 0xF800700C, bit 2 is PCFG_DONE
    return (Xil_In32(0xF800700C) & (1U << 2)) != 0;
}
```

### 4.2 Dynamic Nonce / IV Generation (SEC-01)
To prevent catastrophic keystream reuse across multiple packets:
```c
void pipeline_generate_frame_iv(uint32_t seq_id, uint8_t *iv_out) {
    // Upper 64 bits = Monotonic packet sequence ID
    iv_out[0] = (uint8_t)(seq_id >> 24);
    iv_out[1] = (uint8_t)(seq_id >> 16);
    iv_out[2] = (uint8_t)(seq_id >> 8);
    iv_out[3] = (uint8_t)(seq_id);
    memset(&iv_out[4], 0xAA, 4);
    // Lower 64 bits = Counter block (big-endian increment)
    memset(&iv_out[8], 0x00, 8);
}
```

---

## 5. Compilation & Execution

```bash
# Build standalone BSP and application ELF via Vitis Unified CLI
vitis -s cora7z/app/sw/scripts/build_sw.py

# Program bitstream and launch application on Cora Z7
python3 out/capture_boot.py
```
