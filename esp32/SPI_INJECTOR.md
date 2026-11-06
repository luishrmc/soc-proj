# SPI Telemetry Injector Module (`spi_injector_master`)
## Autonomous Transmission Firmware for ESP32-WROOM (ESP-IDF v6.1 @ 240 MHz)

The files [`esp32/main/spi_injector_master.c`](main/spi_injector_master.c) and [`esp32/main/spi_injector_master.h`](main/spi_injector_master.h) implement the SPI master telemetry injector operating on the ESP32-WROOM microcontroller.

> [!NOTE]
> **Engineering Status — Work-in-Progress (WIP: Testbench & Synthetic Data Pipeline):**  
> Active work centers on coupling the firmware with a **Python-based synthetic telemetry generator**. The generator models time-series physical phenomena (simulated temperature, 3-axis vibration, supply voltage, status bitmasks, and timestamps) with configurable entropy and repetition characteristics. These streams feed the ESP32 transmission pipeline to validate the Cora Z7 AXI Quad SPI receiver and downstream accelerators. Real-world benchmark performance measurements are pending systematic HIL execution.

---

## 1. Operational Overview & Pipeline Capabilities

* **Synthetic Data Ingestion:** Formats and transmits variable-length telemetry frames (**64 B, 256 B, 512 B, and 1024 B**) sourced from the Python synthetic data pipeline, exercising compression (RLE, LZ4) and encryption (AES-CTR, ChaCha20) engines under varied entropy profiles.
* **SPI Master Bus Link:** Operates hardware SPI (`SPI3_HOST` / VSPI) in **Mode 0** (CPOL=0, CPHA=0, MSB-First) at 2.0 MHz for initial bring-up, scalable up to **25 MHz**.
* **Dynamic Frame Construction:** Computes exact frame transaction lengths as $8\text{ (Header)} + \text{len} + 3\text{ (Trailer)}$ and inserts CRC-16 CCITT at dynamic offset $8 + \text{len}$.
* **Hardware Handshake / Pacing:** Monitors **GPIO 32** with pull-up for active-low trigger pulses emitted by the Cora Z7 Processing System on PMOD JA1 (Pin Y18), while supporting autonomous periodic pacing via FreeRTOS `vTaskDelay`.

---

## 2. Physical Pinout Mapping to Digilent Cora Z7-10

| SPI Signal | ESP32 GPIO | Cora Z7 Header / Pin | Function |
| :--- | :---: | :---: | :--- |
| **SCLK** | **GPIO 18** | **Header J7.3 (Pin H15)** | SPI Bus Clock (Mode 0) |
| **MOSI** | **GPIO 23** | **Header J7.4 (Pin T12)** | Master-Out Slave-In serial data |
| **MISO** | **GPIO 19** | **Header J7.1 (Pin W15)** | Master-In Slave-Out ACK / echo response |
| **SS_N** | **GPIO 5** | **Header J7.5 (Pin F16)** | Active-low hardware slave select |
| **TRIGGER** | **GPIO 32** | **PMOD JA1 (Pin Y18)** | Handshake trigger input from Cora Z7 PS |
| **GND** | **GND** | **Header J7.6 (GND)** | Common ground reference |

---

## 3. Dynamic Frame Construction (`spi_injector_build_frame`)

The packet framing adheres directly to the implementation in [`main/spi_injector_master.c`](main/spi_injector_master.c):

```c
void spi_injector_build_frame(TelemetryFrame *frame, uint8_t pkt_type, uint16_t seq_id, const uint8_t *payload, uint16_t len) {
    if (frame == NULL) return;
    if (len > SPI_MAX_PAYLOAD_LEN) len = SPI_MAX_PAYLOAD_LEN;

    uint8_t *raw = (uint8_t *)frame;

    /* 1. 8-byte Header */
    frame->preamble       = SPI_FRAME_PREAMBLE;  /* 0xA5 */
    frame->pkt_type       = pkt_type;            /* 0x01: Echo, 0x02: Telemetry */
    frame->seq_id         = htons(seq_id);       /* Big-Endian sequence counter */
    frame->payload_len    = htons(len);          /* Big-Endian payload length */
    frame->reserved_align = 0;                   /* 32-bit word alignment padding */

    /* 2. Payload population at byte offset 8 (32-bit aligned) */
    if (payload != NULL) {
        memcpy(frame->payload, payload, len);
    } else {
        /* Synthetic incremental pattern fallback */
        for (uint16_t i = 0; i < len; i++) {
            frame->payload[i] = (uint8_t)(i & 0xFFU);
        }
    }

    /* 3. CRC-16 CCITT calculation over Header (8 B) + Payload (len B) */
    uint16_t crc = compute_crc16_ccitt((const uint8_t *)frame, 8U + (size_t)len);

    /* 4. Dynamic wire placement for CRC-16 and EOF delimiter */
    raw[8U + (size_t)len]      = (uint8_t)((crc >> 8) & 0xFFU);
    raw[8U + (size_t)len + 1U] = (uint8_t)(crc & 0xFFU);
    raw[8U + (size_t)len + 2U] = SPI_FRAME_EOF_DELIM; /* 0x5A */

    /* 5. Synchronize static struct members for debug inspection */
    frame->crc16     = htons(crc);
    frame->eof_delim = SPI_FRAME_EOF_DELIM;
}
```
