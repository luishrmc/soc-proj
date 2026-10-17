---
name: bare-metal-c-author
description: Bare-metal C11/C++17 authoring standards for Cortex-A9 on Zynq-7000, enforcing MISRA-aligned deterministic constructs, zero dynamic allocation, and host-verifiable algorithms.
---

# Bare-Metal C Author Skill

Guidelines for developing robust, deterministic firmware in C11 for the ARM Cortex-A9 Processing System.

## 1. When to Use
- Implementing compression algorithms (RLE, LZ4) in software.
- Implementing encryption algorithms (AES-CTR, ChaCha20) in software.
- Writing low-level hardware drivers for AXI-mapped accelerators.
- Authoring host-based unit tests to validate C algorithms against RFC/NIST test vectors.

## 2. Coding Standards & Invariants

- **Standard**: C11 (`-std=c11`) or C++17 (`-std=c++17`).
- **Compiler Flags**: `-Wall -Wextra -Werror -O2`. Warnings are strictly treated as build failures.
- **Fixed-Width Types**: Always use `<stdint.h>` and `<stddef.h>` (`uint8_t`, `uint16_t`, `uint32_t`, `uint64_t`, `size_t`). Never use raw `int` or `long` for binary protocols.
- **Memory Allocation**: **NO DYNAMIC ALLOCATION**. `malloc`, `calloc`, `realloc`, and `free` are forbidden in bare-metal paths. Use static or caller-allocated buffers.
- **Memory-Mapped I/O (MMIO)**:
  - Always use `volatile` pointers or Xilinx accessors (`Xil_In32`, `Xil_Out32`).
  - Never allow compiler reordering across MMIO writes; use memory barrier instructions (`dmb`, `dsb`) where required.
- **Decoupled Architecture**:
  - Keep core algorithm routines (`rle.c`, `lz4_simple.c`, `aes_ctr.c`, `chacha20.c`) free from hardware-specific headers (`xil_io.h`, `xparameters.h`).
  - This allows the exact same C implementation to be compiled and validated on the host machine using standard `gcc`.

## 3. Golden Vector Verification
All software algorithms must be verified against identical golden vectors used for VHDL:
- ChaCha20: RFC 8439 Section 2.4.2 test vectors.
- AES-CTR: NIST SP 800-38A test vectors.
- RLE / LZ4: Synthetic payloads (high redundancy, pseudo-random, sequential telemetry).

Host verification command:
```bash
gcc -Wall -Wextra -Werror -std=c11 -O2 -I cora7z/app/sw/src tests/test_crypto.c cora7z/app/sw/src/chacha20.c -o out/test_chacha20 && ./out/test_chacha20
```
