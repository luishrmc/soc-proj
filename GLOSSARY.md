# Zynq-7010 Compression and Cryptographic Benchmark Platform

Domain vocabulary for the embedded telemetry processing, hardware acceleration, and verification pipeline across the Zynq-7010 SoC and ESP32 injector.

## Language

**Telemetry Record**:
A single, fixed-width 16-byte packed binary sample containing synchronized physical sensor channels (timestamp, temperature, 3-axis vibration, supply voltage, and status bitmask).
_Avoid_: Sensor packet, reading, sample row, data point

**Telemetry Frame**:
The complete physical SPI transmission unit comprising an 8-byte framing header, a fixed 1024-byte payload (64 Telemetry Records), and a 3-byte trailer with CRC-16 CCITT and end-of-frame markers.
_Avoid_: SPI packet, message, buffer, transfer block

**Entropy Profile**:
The statistical regime governing redundancy and byte variance within a Telemetry Frame payload, categorized into Quiescent (low entropy), Dynamic (medium entropy), and Chaotic (high entropy).
_Avoid_: Compression preset, data mode, pattern type

**Embedded Dataset**:
A pre-compiled, static array of Telemetry Frames stored in immutable non-volatile flash memory on the injector microcontroller for zero-jitter line-rate transmission.
_Avoid_: Test vector file, mock blob, firmware payload
