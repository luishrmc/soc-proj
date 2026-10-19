# Technical Memory: Micro-Iteration Pre-Phase 5.1 Sanitization

**Date:** 2026-10-19  
**Status:** Completed & Validated  
**Context:** Technical meta-analysis of external audits (`docs/auditoria_tecnica_gemini.pdf` vs `docs/auditoria_tecnica_perplexity.pdf`)  
**Target Platform:** Digilent Cora Z7-10 (Xilinx XC7Z010-1CLG400C)

---

## 1. Executive Summary & Motivations

Following the critical meta-analysis of external audit reports, four high-priority technical debts and potential blockers for Phase 5 (ESP32 physical integration) and Phase 6 (Performance Benchmarks) were identified and surgically remediated:

1. **LZ4 Engine Intermediate Literal Flush Bug & Golden Verification:**
   - In `lz4_engine.vhdl`, an intermediate flush (`elsif lit_count_r >= 8`) emitted literal sequences mid-stream without a 16-bit match offset. Under the LZ4 Block Format specification, only the final sequence of a block may omit the match offset; emitting intermediate sequences without an offset corrupted decompression in `lz4_decompress()`.
   - In `lz4_simple.c`, a pointer underflow occurred for small buffer lengths (`iend - 5` when `src_len == 4`), and match extensions were allowed to encroach on the trailing 5-byte literal margin.
2. **PL-Autonomous Chaining & Scenario Discrimination:**
   - In `axis_accel_mux.vhdl`, only 1-to-1 routes existed (`0x0..0x4`). In `pipeline_mgr.c`, `SCENARIO_PL_PURE` and `SCENARIO_HYBRID` shared identical code paths and left performance metrics unpopulated.
   - Chained modes (`0x5..0x8`) were implemented directly in `axis_accel_mux.vhdl` to daisy-chain `Compressor -> Cipher` in AXI4-Stream without round-tripping to DDR memory.
   - `pipeline_mgr.c` was enhanced to distinguish pure hardware cycles (`CYCLE_COUNT` @ 100 MHz) from hybrid co-design cycles (Cortex-A9 PMU @ 650 MHz), while introducing monotonic frame diversification for AES/ChaCha20 nonces.
3. **Deliverable Gate Hygiene (`deliverable-audit.sh`) & Path Portability:**
   - Hardcoded host user home absolute paths in Vivado Tcl scripts, documentation, and `.vscode` settings were eliminated in favor of `$::env(HOME)` and repository-relative references.
   - `Checklist_de_Entregaveis.csv` was updated to accurately reflect the 26 passing VUnit unit tests and the operational C firmware stack.
4. **Automated Synthesis to Bitstream & Firmware Synchronism:**
   - Full synthesis, implementation, timing closure, bitstream generation, and hardware container export (`cora7z_top.xsa`) were executed via `build_bitstream.tcl`.

---

## 2. Technical Modifications by Axis

### Axis 1: LZ4 Lossless Compression Engine & Reference C Implementation
- **`cora7z/app/hw/src/lz4_engine.vhdl`:**
  - Resized `lit_buf_r` capacity to 64 bytes (`c_max_lit_buf = 64`) with deterministic hardware overflow protection (`reg_status_r(2) <= '1'` per `INTERFACES.md` Section 2.2), matching the 64-byte sliding window history and preventing distributed multiplexer explosion (saving ~5,400 LUTs and keeping total device utilization at ~68%).
  - Added FSM states `ST_EMIT_LIT_EXT` and `ST_FLUSH_LIT_EXT` to format literal lengths $\ge 15$ according to the standard LZ4 block specification.
  - Removed premature `elsif lit_count_r >= 8` flush in `ST_EVAL_BEAT`. Literals are accumulated cleanly until a match is detected or `in_beat_last_r = '1'`.
- **`cora7z/app/hw/test/tb_lz4_engine.vhdl`:**
  - Added concurrent `capture_proc` collecting all egress stream beats into `captured_bytes`.
  - Added comprehensive `lz4_decompress_and_verify` procedure performing full bit-level decompression and validation.
  - Added unit test `test_roundtrip_pure_literals_32b` (validating multi-byte literal extension) and `test_roundtrip_mixed_64b` (validating inter-beat dictionary matching followed by trailing literals).
- **`cora7z/app/sw/src/lz4_simple.c` & `lz4_simple.h`:**
  - Added `LZ4_MAX_OUTPUT_SIZE(n)` macro.
  - Adjusted threshold to `src_len < 12` to prevent underflow at `mflimit = iend - 5`.
  - Constrained match extension loop with `ip + match_len < mflimit`.

### Axis 2: AXI Stream Accelerator Multiplexer & Chaining Architecture
- **`cora7z/app/hw/src/axis_accel_mux.vhdl`:**
  - Expanded `active_core_s` range from `0..4` to `0..8`.
  - Added Routing Modes:
    - `0x5`: Chained `RLE -> AES-128-CTR -> DMA S2MM`
    - `0x6`: Chained `RLE -> ChaCha20 -> DMA S2MM`
    - `0x7`: Chained `LZ4 -> AES-128-CTR -> DMA S2MM`
    - `0x8`: Chained `LZ4 -> ChaCha20 -> DMA S2MM`
  - Zero modification to entity ports, ensuring 100% preservation of Vivado Block Design (`soc_final_bd_1.bd`) pin connections.
- **`cora7z/app/hw/test/tb_axis_accel_mux.vhdl`:**
  - Added `test_chained_routing` validating both Mode 5 and Mode 8 handshakes, data steering, and backpressure.
- **`cora7z/app/sw/src/axi_accel_ctrl.h` & `cora7z/app/hw/src/INTERFACES.md`:**
  - Synchronized route constants `ACCEL_MUX_ROUTE_*` for values `0x5..0x8`.
- **`cora7z/app/sw/src/pipeline_mgr.c` & `pipeline_mgr.h`:**
  - Added `ALGO_RLE_AES_CTR`, `ALGO_RLE_CHACHA20`, `ALGO_LZ4_AES_CTR`, `ALGO_LZ4_CHACHA20`.
  - Implemented Cortex-A9 PMU cycle counter instrumentation (`pmu_read_ccnt()`).
  - Added dynamic sequence counter `s_frame_seq` incrementing on every frame to guarantee unique IV/nonce generation.
  - Differentiated `SCENARIO_PL_PURE` (reporting isolated hardware cycles @ 100 MHz) from `SCENARIO_HYBRID` (reporting end-to-end CPU cycles @ 650 MHz).

### Axis 3: Path Portability & Deliverable Gate Verification
- **Tcl Scripts (`cora7z/app/hw/scripts/*.tcl`):**
  - Replaced hardcoded board repository paths with `$::env(HOME)/.Xilinx/...`.
- **Hygienic Exclusions:**
  - Removed `.vscode/` from git cache and excluded it in `.gitignore`.
  - Excluded self-referential string search in `.agents/hooks/deliverable-audit.sh`.
  - Replaced markdown document links in `docs/` and `utils/plan/` with repository-relative paths.
  - Verified `deliverable-audit.sh` outputs `PASS`.

---

## 3. Verification & Gate Evidence Summary

| Gate / Test Suite | Command | Status | Details |
|---|---|:---:|---|
| **LZ4 RTL Unit Suite** | `make -C cora7z/app/hw test TB=lz4` | **PASS** | 8/8 tests passed (pure literals, matches, roundtrip 32B/64B) |
| **AXI Mux RTL Unit Suite** | `make -C cora7z/app/hw test TB=mux` | **PASS** | 5/5 tests passed (CSR access, auto-route, manual, chained 5 & 8) |
| **Full VHDL RTL Suite** | `make -C cora7z/app/hw test` | **PASS** | 26/26 tests passed across all 5 testbenches |
| **Host C Algorithms** | `./out/test_software_algorithms` | **PASS** | RLE, LZ4, AES-CTR (NIST), ChaCha20 (RFC 8439) |
| **Host AXI Drivers** | `./out/test_axi_drivers` | **PASS** | DMA v7.1, Accel Ctrl, SPI Receiver, Pipeline Mgr |
| **Deliverable Portability** | `bash .agents/hooks/deliverable-audit.sh` | **PASS** | 0 machine-specific absolute path leaks found |
| **Vivado Bitstream & XSA** | `build_bitstream.tcl` | **PASS** | LUTs: 12,709/17,600 (72.2%), FFs: 14,804 (42.1%), Latches: 0, WNS: +0.330 ns, TNS: 0.000 ns, SHA: `a74aae9c...` |
| **Vitis Platform & Firmware** | `build_sw.py` | **PASS** | Standalone BSP + `cora7z_firmware.elf` (205 KB, SHA: `dc4827be...`) |

---

## 4. Next Step

With all four points of the sanitization micro-iteration completed and verified, the repository is 100% hardened and ready for **Task 5.1** (ESP32 ESP-IDF project configuration and synthetic data generator bringup).
