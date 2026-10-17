---
name: doc-lookup
description: Targeted lookup inside technical datasheets and manuals in docs/ (UG585, DS187, Cora Z7 Reference, Schematic) using pdftotext without loading massive PDF files into context.
---

# Doc Lookup Skill

Extract targeted hardware specifications, pin mappings, register descriptions, and timing parameters from official documentation in `docs/` using local tools.

## 1. When to Use
- Determining pin assignments, package constraints, or pull-up configurations on Cora Z7.
- Checking Zynq-7000 processing system clock configurations, MIO multiplexing, and PS-PL interfaces in UG585.
- Looking up Artix-7 electrical characteristics, BRAM/DSP slice limits in DS187.

## 2. Available Documents in `docs/`

- `docs/cora7z/Cora Z7 Reference Manual - Digilent Reference.pdf`:
  Board-level manual describing power rails, 125 MHz clock on H16, Arduino shield pins, PMOD pinout, LEDs, buttons.
- `docs/cora7z/Cora+Z7_sch-public.pdf`:
  Full schematic of Cora Z7 (pin-to-FPGA connections, series resistors, pull-ups).
- `docs/cora7z/UG585.pdf`:
  Zynq-7000 Technical Reference Manual (TRM) for Cortex-A9, AXI interfaces, timers, PMU, interrupts.
- `docs/cora7z/ds187-XC7Z010-XC7Z020-Data-Sheet.pdf`:
  DC and AC switching characteristics for Zynq-7010.

## 3. Recommended Query Flow

Do not read entire PDFs into the model prompt. Use `pdftotext` with targeted page ranges or keywords.

```bash
# 1. Search for a specific keyword in a document
pdftotext docs/cora7z/Cora\ Z7\ Reference\ Manual\ -\ Digilent\ Reference.pdf - | grep -i -C 3 "H16"

# 2. Extract a specific page range (e.g. pages 12 to 14)
pdftotext -f 12 -l 14 docs/cora7z/Cora\ Z7\ Reference\ Manual\ -\ Digilent\ Reference.pdf out/page12_14.txt

# 3. View the extracted text
head -n 40 out/page12_14.txt
```

## 4. Citation Requirement
Whenever citing technical details derived from these documents, always cite:
- Document filename
- Section title or Page number
- Exact parameter or pin name (e.g. "Pin H16, Bank 35, 125 MHz reference clock from Ethernet PHY").
