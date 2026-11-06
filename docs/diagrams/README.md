# Visual Architectural Diagrams & Schematics
## Heterogeneous SoC PS/PL Acceleration Platform (Digilent Cora Z7-10)

This directory houses high-resolution architectural diagrams, system topology schematics, and generation scripts for the Zynq-7010 heterogeneous co-design project.

> [!NOTE]
> **Engineering Status — Work-in-Progress (WIP: Testbench & Synthetic Data Pipeline):**  
> The architectural diagrams illustrate the co-design block design on the Digilent Cora Z7-10 and its physical interface with the ESP32 SPI injector. Active development centers on a **Python synthetic telemetry generator** that produces realistic, time-series sensor streams to drive the HIL testbed. All empirical benchmark figures and resource utilization metrics are **Pending Measurement / WIP**.

---

## 1. Directory Artifacts

| File Name | Format | Dimensions / Size | Description |
| :--- | :---: | :---: | :--- |
| [`cora7z_top.png`](cora7z_top.png) | PNG (24-bit RGB) | **3200 $\times$ 1800** (658 KB) | **Master Architectural Diagram:** SoC layout showing ESP32 synthetic injector, PS Cortex-A9, PL crossbar, BRAM memory hierarchy, accelerator RTL engines, and 12-row benchmark evaluation matrix. |
| [`cora7z_top.jpg`](cora7z_top.jpg) | JPEG (95% Qual) | **3200 $\times$ 1800** (1.2 MB) | High-resolution raster image formatted for presentations and web view. |
| [`cora7z_soc_architecture.pdf`](cora7z_soc_architecture.pdf) | Vector PDF | Infinite vector scale | Vector PDF for publication printing and documentation. |
| [`generate_soc_diagram.py`](generate_soc_diagram.py) | Python (PyCairo) | 815 lines | Automated script producing the 3200 $\times$ 1800 diagram programmatically using the `pycairo` vector 2D engine. |

---

## 2. Master System Interconnect Layout

The diagram visually details four interconnected domains:

1. **External Stimulus (ESP32-WROOM):** SPI Master, framing protocol, pinout to Cora Z7 Header J7, and GPIO 32 trigger handshake for synthetic test vectors generated via the Python telemetry pipeline.
2. **Processing System (PS - Cortex-A9 @ 667 MHz):** Core 0, DDR3 memory controller, DEVCFG safety interlock (`PCFG_DONE`), EMIO GPIO, and `M_AXI_GP0` master bus.
3. **Programmable Logic (PL - Artix-7 @ 100 MHz):**
   - **Ingress AXI Quad SPI (`0x41E00000`):** Slave Mode 0 with 256 B FIFO.
   - **LZSS Compressor (`0x43C00000`):** 8 KB Input BRAM (`0x40000000`) and 8 KB Output BRAM (`0x40002000`).
   - **AES-128-CTR Encryptor (`0x43C10000`):** 8 KB Input BRAM (`0x40010000`) and 8 KB Output BRAM (`0x40012000`).
4. **Benchmark Evaluation Framework & Resource Allocation:** The planned 12-row experimental evaluation matrix (Scenarios 1–4 across 256 B, 512 B, and 1024 B payloads) and XC7Z010 device resource budgets (performance values designated as `Pending Measurement / WIP`).

```text
[Python Telemetry Gen] ---> [ESP32 Master] --(SPI Header J7)--> [AXI Quad SPI] --(AXI4)--> [DDR3 RAM]
                                                                                              |
[Cortex-A9 PS] <====================(M_AXI_GP0 Port A Staging)================================+
      |
      +---> [LZSS In BRAM] ---> [lzss_accel (PL)] ---> [LZSS Out BRAM]
      |
      +---> [AES In BRAM]  ---> [aes_accel (PL)]  ---> [AES Out BRAM]
```

---

## 3. Re-Generating Diagram Artifacts

To re-render all diagram formats from source using `pycairo`:
```bash
python3 docs/diagrams/generate_soc_diagram.py
```
Outputs are written directly to this directory (`cora7z_top.png`, `cora7z_top.jpg`, and `cora7z_soc_architecture.pdf`).
