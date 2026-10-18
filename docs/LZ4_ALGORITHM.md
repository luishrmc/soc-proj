# LZ4 Compression: Theory, Architecture, and VHDL Hardware Implementation

This document provides a comprehensive theoretical and architectural specification of the simplified LZ4 hardware compression accelerator (`lz4_engine.vhdl`) implemented for the Digilent Cora Z7-10 (Xilinx Zynq-7010). It details the mathematical foundations of dictionary-based compression, the LZ4 byte-aligned framing protocol, hardware sliding window and hash table architectures, finite-state machine (FSM) sequencing, AXI4-Lite control, and AXI4-Stream data movement.

---

## 1. Theoretical Principles of Dictionary-Based Compression

### 1.1 The Lempel-Ziv (LZ77) Paradigm
In 1977, Abraham Lempel and Jacob Ziv published their seminal paper, *"A Universal Algorithm for Sequential Data Compression"* (IEEE Transactions on Information Theory). Unlike entropy coders (e.g., Huffman, arithmetic coding) that operate strictly on individual symbol probabilities, and unlike Run-Length Encoding (RLE) that only exploits adjacent identical bytes, the LZ77 family exploits **temporal and structural redundancy** across arbitrary distances within a stream.

LZ77 maintains a **Sliding Window** over previously processed data, partitioned into:
1. **Search Buffer (History Dictionary)**: The sequence of $W$ bytes immediately preceding the current read position.
2. **Lookahead Buffer**: The sequence of upcoming uncompressed bytes to be encoded.

```
Incoming Stream:  ... [ d a t a _ s t r u c t u r e _ d a t a _ ] ...
                      |◄────── Search Buffer ──────►|◄ Lookahead ►|
                                                     Match: "data_"
                                                     Distance = 17, Length = 5
```

When a sequence of symbols in the lookahead buffer matches a sequence previously observed in the search buffer, the encoder replaces the raw symbols with a backward reference:
$$\text{Reference} = (\text{Offset}, \text{Length})$$
- $\text{Offset} \in [1, W]$: Distance backward from the current read pointer to the beginning of the match.
- $\text{Length} \ge L_{\min}$: Number of consecutive matching bytes ($L_{\min} = 4$ in LZ4).

### 1.2 Comparison with Run-Length Encoding (RLE)

| Characteristic | Run-Length Encoding (RLE) | Lempel-Ziv 4 (LZ4) |
|---|---|---|
| **Redundancy Exploited** | Strictly consecutive identical bytes ($A A A \dots$) | Multi-byte substrings separated by arbitrary distances |
| **Minimum Match Length** | 2 bytes ($k \ge 2$) | 4 bytes ($L_{\min} = 4$) |
| **Memory Requirement** | $\mathcal{O}(1)$ (Single register for current symbol & count) | $\mathcal{O}(W)$ (History buffer BRAM + Hash table indexing) |
| **Best-Case Compression** | Continuous identical bytes ($CR \approx 32:1$) | Repetitive multi-byte phrases & structured records ($CR > 10:1$) |
| **Worst-Case Behavior** | High data expansion on non-repeating data ($-100\%$) | Bounded token overhead on non-compressible data |
| **Ideal Workload** | Solid color raster runs, empty buffers | ASCII logs, JSON/telemetry packets, structured code |

### 1.3 Mathematical Formulation: Entropy and Asymptotic Optimality
Shannon's source coding theorem states that no compression scheme can exceed the entropy rate of the source:
$$H(\mathcal{X}) = \lim_{n \to \infty} \frac{1}{n} H(X_1, X_2, \dots, X_n)$$

Ziv and Lempel proved that as the window size $W \to \infty$ and stream length $N \to \infty$, the compression ratio of LZ77 asymptotically approaches the true entropy rate $H(\mathcal{X})$ of any stationary, ergodic source without requiring prior knowledge of the source's statistical distribution.

In practical embedded systems, window size is bounded by physical Block RAM (BRAM) capacity. For the Zynq-7010 PL (Artix-7 fabric with 60 dual-port 36 Kb BRAM blocks), a window size of $W = 2048$ or $4096$ bytes provides an optimal trade-off between hardware area and compression performance for typical packet sizes (64 B to 4 KB).

---

## 2. LZ4 Framing and Token Format

LZ4, designed by Yann Collet, is specifically engineered for deterministic, high-throughput byte-level processing. Unlike DEFLATE (which applies Huffman coding over LZ77 tokens), LZ4 emits byte-aligned tokens that require zero bit-shifting, enabling single-cycle processing in hardware.

### 2.1 The LZ4 Sequence
An LZ4 compressed block consists of a concatenation of **Sequences**. Each sequence represents zero or more **Literals** (uncompressed raw bytes) followed by a **Match Copy** (backward reference):

```
┌───────────────┬──────────────────────┬──────────────────┬─────────────────┬──────────────────┐
│  Token (1 B)  │ Extra Lit Length (0+B│  Literals (0..N) │ Offset (2 Bytes)│ Extra Match (0+B)│
│ [LitLen|Match]│  (if LitLen == 15)   │  [Raw Bytes]     │  Little-Endian  │ (if Match == 15) │
└───────────────┴──────────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

### 2.2 The Sequence Token Byte
The sequence begins with a mandatory 1-byte **Token** split into two 4-bit nibbles:

```
Bit:   7     6     5     4     3     2     1     0
    ┌───────────────────────┬───────────────────────┐
    │ Literal Length [7:4]  │  Match Length [3:0]   │
    └───────────────────────┴───────────────────────┘
```

1. **Literal Length Nibble (Bits 7:4)**:
   - Encodes the number of uncompressed literal bytes ($0 \le L_{\text{lit}} \le 15$) preceding the match.
   - If $L_{\text{lit}} < 15$, the nibble holds the exact literal count.
   - If $L_{\text{lit}} \ge 15$, the nibble is set to `0xF` (15), and extra length bytes follow immediately.
2. **Match Length Nibble (Bits 3:0)**:
   - Encodes the match length minus the minimum match size:
     $$\text{Token Match Value} = L_{\text{match}} - 4$$
   - Since $L_{\min} = 4$, a nibble value of `0` denotes a 4-byte match, while `14` denotes an 18-byte match.
   - If $L_{\text{match}} - 4 \ge 15$ ($L_{\text{match}} \ge 19$), the nibble is set to `0xF` (15), and extra match length bytes follow the offset.

### 2.3 Extended Length Encoding (Overflow Bytes)
When length fields exceed 14:
- The corresponding token nibble is set to `15` (`0xF`).
- Successive bytes of value `255` (`0xFF`) are appended as long as the remaining length $\ge 255$.
- The final byte holds the remaining value $< 255$.

$$\text{Total Length} = 15 + \sum (\text{Byte}_i)$$

*Example*: A literal run of 275 bytes is encoded as:
- Token Literal Nibble = `15`
- Byte 1 = `255` (Total = $15 + 255 = 270$)
- Byte 2 = `5` (Total = $270 + 5 = 275$)

### 2.4 Match Offset (16-bit Little-Endian)
The match distance is encoded as a 16-bit unsigned integer in Little-Endian byte order:
$$\text{Offset} = \text{Offset}_{\text{LSB}} + (\text{Offset}_{\text{MSB}} \times 256)$$
Valid range: $1 \le \text{Offset} \le 65535$. An offset of `0` is invalid.

### 2.5 End of Block Rule (Trailing Literals)
Per the LZ4 specification:
1. The last sequence in a block contains only literals; it has no match copy (no offset is emitted).
2. The last 5 bytes of an input block are always encoded as literals to prevent lookahead buffer underflow.

---

## 3. Hardware Architecture on Zynq-7010 PL

```
                         ┌────────────────────────────────────────────────────────┐
                         │                     LZ4 Engine Core                    │
                         │                                                        │
                         │   ┌──────────────┐     ┌──────────────┐                │
    s_axis_tdata[31:0]  ─┼──►│ Ingress Beat │────►│ History BRAM │ (4KB Buffer)   │
    s_axis_tvalid        │   │  Unpacker    │     └──────┬───────┘                │
    s_axis_tready       ◄┼───│  (32b -> 8b) │            │ Match Bytes            │
    s_axis_tlast         │   └──────┬───────┘            ▼                        │
                         │          │             ┌──────────────┐                │
                         │          ├────────────►│ 4-Byte Hash  │                │
                         │          │             │ Match Finder │                │
                         │          │             └──────┬───────┘                │
                         │          ▼                    ▼                        │
                         │   ┌──────────────────────────────────┐                 │
                         │   │   Finite State Machine (FSM)     │                 │
                         │   │   - Literal Buffering            │                 │
                         │   │   - Match Length Counter         │                 │
                         │   │   - Token & Offset Generation    │                 │
                         │   └──────────────────┬───────────────┘                 │
                         │                      │                                 │
                         │                      ▼                                 │
                         │             ┌─────────────────┐                        │
                         │             │ Egress Stream   │───► m_axis_tdata[31:0] │
                         │             │ Word Packer     │───► m_axis_tvalid      │
                         │             │ (8b -> 32b)     │◄─── m_axis_tready      │
                         │             └─────────────────┘───► m_axis_tlast       │
                         │                                                        │
  s_axi_lite (0x43C10000)┼───────────────────────────────────► CSR Register Bank   │
  irq_o                  ◄─────────────────────────────────── Completion Pulse    │
                         └────────────────────────────────────────────────────────┘
```

### 3.1 Datapath Components

1. **Ingress Beat Unpacker**:
   - Accepts 32-bit AXI4-Stream beats from DMA (`s_axis_tdata[31:0]`, `s_axis_tkeep[3:0]`).
   - Unpacks incoming beats into a byte-stream pipeline at 100 MHz.
   - Detects `s_axis_tlast` on the final beat to trigger literal flushing.
2. **Circular History Buffer (BRAM)**:
   - Configured as a dual-port synchronous RAM of size 2048 bytes (or 4096 bytes).
   - Port A: Writes incoming raw bytes at address $\text{write\_ptr} = \text{byte\_idx} \pmod{W}$.
   - Port B: Reads candidate match bytes at address $\text{read\_ptr} = (\text{curr\_pos} - \text{offset}) \pmod{W}$.
3. **Hardware Hash Table (Match Finder)**:
   - An array of 1024 entries storing 12-bit position pointers.
   - Computes a hardware-efficient 10-bit hash over 4 consecutive bytes:
     $$h = ((B_0 \oplus (B_1 \ll 2)) \oplus ((B_2 \ll 4) \oplus (B_3 \ll 6))) \pmod{1024}$$
   - In a single clock cycle, looks up the previous occurrence of this 4-byte signature.
   - If candidate distance $\le W$ and history bytes equal lookahead bytes $\implies$ **Match Hit**.
4. **Token and Egress Word Packer**:
   - Formats LZ4 sequence tokens: `[LitLen | MatchLen-4]`, literal bytes, and 16-bit little-endian offsets.
   - Accumulates emitted bytes into a 32-bit shift register.
   - Asserts `m_axis_tvalid` whenever a full 32-bit word is packed or upon `tlast` flush.

### 3.2 Finite-State Machine (FSM)

The compression core transitions across five synchronous states:

```
       ┌───────────┐
       │  ST_IDLE  │◄───────────────────────────┐
       └─────┬─────┘                            │
             │ START = '1' or TVALID = '1'      │
             ▼                                  │
       ┌───────────┐                            │
       │ ST_INGEST │◄───────────┐               │
       └─────┬─────┘            │               │
             │ 4-byte check     │ Next byte     │ Beat ACK
             ▼                  │ (no match)    │
       ┌───────────┐            │               │
       │ ST_MATCH  │────────────┘               │
       └─────┬─────┘                            │
             │ Match found or TLAST flush       │
             ▼                                  │
       ┌───────────┐                            │
       │  ST_EMIT  │                            │
       └─────┬─────┘                            │
             │ Sequence transmitted             │
             ▼                                  │
       ┌───────────┐                            │
       │ ST_FINISH │────────────────────────────┘
       └───────────┘
```

- **`ST_IDLE`**: Resets history pointers, clears hash table, waits for software `START` bit or streaming `s_axis_tvalid`.
- **`ST_INGEST`**: Reads incoming bytes, computes 4-byte hash, updates history BRAM.
- **`ST_MATCH`**: Evaluates hash table candidate. If match occurs, counts match length. If no match, accumulates current byte as a pending literal.
- **`ST_EMIT`**: Emits LZ4 token `[LitLen, MatchLen]`, flushes pending literal bytes, and emits 16-bit match offset.
- **`ST_FINISH`**: Emits trailing literals with `m_axis_tlast = '1'`, asserts `irq_o` pulse, updates `DST_LEN` and `CYCLE_COUNT`, and sets `STATUS.DONE = 1`.

---

## 4. AXI4-Lite Control & Status Registers (CSR)

Base Address: **`0x43C10000`** (Mapped on `axi_interconnect_0/M03_AXI`).

| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00` | `CONTROL` | R/W | `0x00000000` | Bit 0: `START` (self-clearing), Bit 1: `RESET_CORE`, Bit 2: `IRQ_EN` |
| `0x04` | `STATUS` | RO | `0x00000000` | Bit 0: `BUSY`, Bit 1: `DONE`, Bit 2: `ERR` |
| `0x08` | `SRC_LEN` | R/W | `0x00000000` | Total uncompressed block length in bytes |
| `0x0C` | `DST_LEN` | RO | `0x00000000` | Total compressed block length in bytes |
| `0x10` | `CYCLE_COUNT` | RO | `0x00000000` | Hardware latency: clock cycles active in current run |

---

## 5. Timing and Benchmark Metrics

1. **Clock Frequency**: $f_{\text{accel}} = 100 \text{ MHz}$ ($T_{\text{clk}} = 10 \text{ ns}$).
2. **Throughput Formulation**:
   $$\text{Throughput} = \frac{L_{\text{raw}} \times 8 \text{ bits}}{\text{CYCLE\_COUNT} \times 10^{-8} \text{ s}} \quad \text{[Mbps]}$$
3. **Compression Ratio ($CR$)**:
   $$CR = \frac{L_{\text{raw}}}{L_{\text{comp}}} = \frac{\text{SRC\_LEN}}{\text{DST\_LEN}}$$

---

## 6. Formal References

1. **Ziv, J., & Lempel, A.** (1977). *"A Universal Algorithm for Sequential Data Compression."* IEEE Transactions on Information Theory, 23(3), 337–343.
2. **Collet, Y.** (2019). *"LZ4 Block Format Description."* [GitHub Reference Repository](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md).
3. **Shannon, C. E.** (1948). *"A Mathematical Theory of Communication."* Bell System Technical Journal, 27(3), 379–423.
4. **Xilinx Inc.** (2021). *"Vivado Design Suite User Guide: Designing with IP Subsystems (UG994)."*
