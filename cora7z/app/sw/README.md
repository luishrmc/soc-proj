# Cora Z7-10 Bare-Metal Software Architecture (Processing System)

This directory houses the standalone C bare-metal firmware executing on the **ARM Cortex-A9 Core 0 @ 667 MHz** of the Xilinx Zynq-7010 SoC (Digilent Cora Z7-10).

---

## 1. Architectural Overview & Execution Flow

The software architecture operates in a **Compress-then-Encrypt** pipeline designed for IoT telemetry reduction and confidentiality. It ingests frames from an external **ESP32-WROOM** master over SPI, executes pure-software baseline algorithms, instruments cycle-accurate hardware metrics via the ARM PMU (CP15 `PMCCNTR`), and preloads acknowledgement (ACK) frames.

```
       +-----------------------------------------------------------+
       |                  ESP32-WROOM (SPI Master)                 |
       +-----------------------------------------------------------+
                                     |
                         SPI Mode 0 @ 2 MHz (J7)
                                     v
       +-----------------------------------------------------------+
       |               Zynq-7010 PL: AXI Quad SPI Core             |
       |                (Base Address: 0x41E00000)                 |
       +-----------------------------------------------------------+
                                     |
                         M_AXI_GP0 Slave Ingestion
                                     v
+-------------------------------------------------------------------------+
|                  Zynq-7010 PS: ARM Cortex-A9 @ 667 MHz                  |
|                                                                         |
|  1. Ingestion: axi_spi_read_frame() -> 64 B Payload + CRC16 Validation  |
|  2. ACK Staging: axi_spi_stage_ack() -> Preload 0x81 ACK into TX FIFO   |
|  3. Compression: lzss_compress() -> Sliding-Window LZSS (74 B Stream)  |
|  4. Encryption: aes_128_ctr_crypt() -> NIST SP 800-38A Stream Cipher    |
|  5. Profiling: pmu_read_cycles() -> PMU CP15 Cycle Count & Throughput   |
+-------------------------------------------------------------------------+
```

---

## 2. Software Modules & Interface Specifications

### 2.1 Sliding-Window LZSS Compression (`lzss_sw.h` / `lzss_sw.c`)
- **Algorithm**: Fixed-window LZSS with 8-token flag chunks.
- **Window Size**: 256 bytes ($W=256$, 8-bit back-reference distance).
- **Match Lengths**: 3 to 258 bytes ($\text{MIN\_MATCH}=3$, $\text{MAX\_MATCH}=258$).
- **Memory Footprint**: **Zero dynamic memory allocation** (`malloc`-free). Operates in-place with a pre-allocated, 32-bit aligned static workspace structure (`lzss_workspace_t`).
- **Header**: Encodes uncompressed stream length as a 16-bit Big-Endian header.
- **Key Functions**:
  ```c
  int lzss_compress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t *dst_len, lzss_workspace_t *ws);
  int lzss_decompress(const uint8_t *src, size_t src_len, uint8_t *dst, size_t *dst_len);
  ```

### 2.2 Cryptographic Engine (`aes_ctr_sw.h` / `aes_ctr_sw.c`)
- **Algorithm**: NIST FIPS-197 AES-128 in Counter Mode (CTR) per NIST SP 800-38A.
- **Counter Invariant**: Full 128-bit Big-Endian counter incrementation per Section B.2.
- **Stream Cipher Properties**: Arbitrary payload length support with **zero padding overhead**.
- **Self-Test**: Built-in verification against all 4 official 16-byte blocks of NIST SP 800-38A Section F.5.1:
  - Block 1: `874d6191 b620e326 1bef6864 990db6ce`
  - Block 2: `9806f66b 7970fdff 8617187b b9fffdff`
  - Block 3: `5ae4df3e dbd5d35e 5b4f0902 0db03eab`
  - Block 4: `1e031dda 2fbe03d1 792170a0 f3009cee`
- **Key Functions**:
  ```c
  int aes_128_ctr_crypt(const uint8_t key[16], const uint8_t nonce[16], const uint8_t *src, uint8_t *dst, size_t len);
  int aes_128_ctr_self_test(void);
  ```

### 2.3 Pipeline Manager & Profiler (`pipeline_mgr.h` / `pipeline_mgr.c`)
- **Responsibility**: Orchestrates the sequential Compress-then-Encrypt transformation and instruments cycle counts.
- **Instrumentation**: Uses ARM PMU cycle counter (`PMCCNTR` via CP15) at full 667 MHz resolution.
- **Key Metrics Tracked**:
  - Raw length, compressed length, ciphertext length.
  - Stage cycles ($T_{\text{COMP}}$, $T_{\text{CRYPT}}$, $T_{\text{TOTAL}}$).
  - Stage latency in microseconds ($\mu\text{s} = \text{cycles} / 667$).
  - Compression ratio: $CR = 1.0 - \left(\frac{\text{Compressed Size}}{\text{Raw Size}}\right)$.
  - Throughput (MB/s).
- **Key Functions**:
  ```c
  int pipeline_init(void);
  int pipeline_process_frame(const uint8_t *raw_in, size_t raw_len, uint8_t *cipher_out, size_t max_out_len, size_t *final_len, pipeline_metrics_t *metrics);
  int pipeline_reverse_frame(const uint8_t *cipher_in, size_t cipher_len, uint8_t *raw_out, size_t max_out_len, size_t *recovered_len);
  ```

### 2.4 SPI Slave Receiver (`axi_spi_receiver.h` / `axi_spi_receiver.c`)
- **Peripheral**: Xilinx LogiCORE AXI Quad SPI v3.2 at `0x41E00000` (Slave Mode 0).
- **Physical Pins**: SCLK (`H15`), MOSI (`T12`), MISO (`W15`), SS (`F16`, with `spisel`).
- **Hardware Bus Protection**: Queries DEVCFG `PCFG_DONE` (`0xF800700C[2]`) prior to issuing MMIO reads.
- **Key Functions**:
  ```c
  int axi_spi_init(uintptr_t base_addr);
  int axi_spi_read_frame(uintptr_t base_addr, TelemetryFrame *frame_out, uint32_t max_poll_cycles);
  int axi_spi_stage_ack(uintptr_t base_addr, uint16_t seq_id, uint8_t status_code);
  ```

---

## 3. Empirical Hardware Profiling Results (Cora Z7 @ 667 MHz)

Measurements captured directly from physical hardware console:

| Telemetry Frame Size | Stage | CPU Cycles (PMCCNTR) | Latency ($\mu\text{s}$) | Compression Ratio ($CR$) | Throughput |
|---|---|:---:|:---:|:---:|:---:|
| **64 Bytes (Incremental)** | LZSS Compress | $\approx 60,300$ | $90\ \mu\text{s}$ | $-15\%$ (Expansion) | - |
| | AES-128-CTR Crypt | $\approx 106,800$ | $160\ \mu\text{s}$ | - | - |
| | **Total Pipeline** | **$\approx 167,100$** | **$250\ \mu\text{s}$** | **$-15\%$** | **$0.24\text{ MB/s}$** |
| **512 Bytes (Synthetic Sensor)** | LZSS Compress | $\approx 112,000$ | $168\ \mu\text{s}$ | $+54\%$ (231 B) | - |
| | AES-128-CTR Crypt | $\approx 330,000$ | $495\ \mu\text{s}$ | - | - |
| | **Total Pipeline** | **$\approx 442,000$** | **$663\ \mu\text{s}$** | **$+54\%$** | **$0.74\text{ MB/s}$** |

---

## 4. Build, Flash, and Verification Instructions

### 4.1 Build Bare-Metal Firmware (Vitis CLI)
```bash
source .agents/env.sh
vitis -s cora7z/app/sw/scripts/build_sw.py latest
```

### 4.2 Program Bitstream & Run on Cora Z7
```bash
source .agents/env.sh
vitis -s cora7z/app/sw/scripts/launch_app.py
```

### 4.3 Serial Telemetry Monitoring
```bash
picocom -b 115200 /dev/ttyUSB1
```
