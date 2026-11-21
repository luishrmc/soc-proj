# Standardized 1024-Byte Payload Sizing for HIL Benchmarking

**Status**: accepted

To simplify hardware buffer sizing, BRAM alignment, and execution sweeps during physical Hardware-in-the-Loop (HIL) benchmarking between the ESP32 injector and Cora Z7, the payload size is strictly standardized to **1024 bytes** across all evaluation runs. Previous multi-size sweep targets (64 B, 256 B, and 512 B) are eliminated from the test matrix.

### Context & Trade-offs

Earlier planning documents and initial simulation testbenches evaluated four discrete payload lengths: 64 B, 256 B, 512 B, and 1024 B. In practice:
1. Smaller payloads (64 B, 256 B) do not saturate the 1024-byte True Dual-Port Block RAM buffers instantiated for the hardware accelerators (`lzss_accel` and `aes_accel`).
2. Sizing exclusively at 1024 bytes aligns directly to exactly 64 packed 16-byte `Telemetry Record` structures and 256 32-bit words, eliminating non-aligned BRAM tail logic and variable-length DMA/FIFO boundary edge cases.
3. Multi-size sweeps add substantial benchmarking overhead without yielding new architectural insights regarding peak hardware acceleration throughput or coprocessor cycle efficiency.

### Consequences

- All SPI `Telemetry Frame` transmissions enforce a payload length field of `0x0400` (1024 bytes), yielding a fixed 1035-byte on-wire frame ($8\text{ byte header} + 1024\text{ byte payload} + 2\text{ byte CRC-16} + 1\text{ byte EOF}$).
- Variations in algorithm performance and throughput are driven entirely by the three `Entropy Profile` regimes (`Quiescent`, `Dynamic`, `Chaotic`) rather than payload length variations.
