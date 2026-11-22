# Módulo de Hardware: `lzss_accel` (Compressor LZSS / Heatshrink)
## Arquitetura RTL em VHDL-2008 para FPGA AMD Xilinx Artix-7 @ 100 MHz

O arquivo [`lzss_accel.vhdl`](../../cora7z/app/hw/src/compression/lzss_accel.vhdl) implementa o acelerador de hardware para compressão de dados por dicionário baseado no algoritmo LZSS (Lempel-Ziv-Storer-Szymanski), gerando fluxos binários compatíveis com Heatshrink (ADR-012, ADR-017, ADR-019, ADR-020).

---

## 1. Visão Geral e Parâmetros RTL

* **Padrão VHDL:** VHDL-2008 sintetizável (`ieee.numeric_std`), clock único `aclk` (`FCLK_CLK1` @ `100 MHz`), reset síncrono ativo baixo `aresetn`.
* **Janela Deslizante (`c_window_size`):** `256` bytes (offset de 8 bits `dist - 1`).
* **Buffer Lookahead (`c_max_lookahead`):** `16` bytes (`lookahead_r` em 128 FFs; casamentos de 3 a 16 bytes).
* **Casamento Mínimo (`c_min_match`):** **`3` bytes** (literais em 1 byte com flag `'0'`; matches em 2 bytes `(dist-1, len-3)` com flag `'1'`).
* **Cabeçalho e Framing:** Cabeçalho de 16 bits Big-Endian (`src_len`, ex. `0x0400` para `1024 B`) seguido por blocos de 8 tokens prefixados por máscara de 1 byte.
* **Instrumentação em Silício:** Registrador `0x10` (`reg_cycle_count_r`, 32 bits) contando ciclos exatos de `aclk` (`100 MHz`) de `START` até `ST_DONE`.

---

## 2. Interface de Entidade & Mapa CSR (`0x43C00000`)

```text
                           lzss_accel (VHDL-2008)
                     +---------------------------------+
  aclk (100 MHz)  -->| [AXI4-Lite Slave @ 0x43C00000]  |--> irq_o
  aresetn         -->|  0x00: CONTROL (START/RESET/IRQ)|--> busy_o
  s_axi_*        <-->|  0x04: STATUS  (BUSY/DONE/ERR)  |
                     |  0x08: SRC_LEN (Bytes Entrada)  |
                     |  0x0C: DST_LEN (Bytes Saída)    |
                     |  0x10: CYCLE_CNT (Ciclos PL)    |
                     |                                 |
                     | [Interfaces BRAM Porta B]       |
  bram_in_dout    -->|  - bmg_lzss_in  (8 KB, 1-cyc rd)|--> bram_in_{en,we,addr,din}
  bram_out_dout   -->|  - bmg_lzss_out (8 KB)          |--> bram_out_{en,we,addr,din}
                     +---------------------------------+
```

### Mapa de Registradores AXI4-Lite (`c_s_axi_addr_width = 12`)

| Offset | Registrador | Acesso | Descrição |
| :---: | :--- | :---: | :--- |
| `0x00` | `CONTROL` | RW | Bit 0: `START` (pulso), Bit 1: `RESET_CORE`, Bit 2: `IRQ_EN` |
| `0x04` | `STATUS` | RO | Bit 0: `BUSY`, Bit 1: `DONE`, Bit 2: `ERROR` |
| `0x08` | `SRC_LEN` | RW | Tamanho da carga bruta de entrada em bytes (`1..2048 B`) |
| `0x0C` | `DST_LEN` | RO | Comprimento final comprimido em bytes travado em `ST_DONE` |
| `0x10` | `CYCLE_CNT` | RO | Contagem de ciclos de clock @ `100 MHz` entre `START` e `DONE` |

---

## 3. Máquina de Estados Finitos (FSM)

A FSM (`fsm_state_t` em `lzss_accel.vhdl`) opera de forma síncrona com latência de leitura BRAM de 1 ciclo registrada (`bram_wait_r`, ADR-019):

1. **`ST_IDLE`**: Aguarda pulso `start_pulse_s`. Zera ponteiros e contadores.
2. **`ST_WRITE_HDR_0` / `ST_WRITE_HDR_1`**: Grava os 2 bytes Big-Endian do cabeçalho (`src_len`) em `bram_out(0..1)`.
3. **`ST_INIT_LA_REQ` / `ST_INIT_LA_WAIT` / `ST_LOAD_LA_REQ` / `ST_LOAD_LA_WAIT`**: Carrega até 16 bytes do lookahead a partir de `bram_in`.
4. **`ST_START_CHUNK` / `ST_EVAL_TOKEN`**: Reserva byte de máscara `flag_idx_r` e inicia busca caso `la_valid_len_r >= 3`.
5. **`ST_SEARCH_REQ` / `ST_SEARCH_WAIT` / `ST_CMP_REQ` / `ST_CMP_WAIT`**: Varre candidatos `[win_start, in_idx)` em `bram_in` buscando maior casamento (`3..16` bytes).
6. **`ST_EMIT_MATCH_0` / `ST_EMIT_MATCH_1` / `ST_EMIT_LITERAL`**: Escreve token match ou literal com byte-enable lane (`bram_out_we`) e recarrega o lookahead.
7. **`ST_FLUSH_FLAG` / `ST_DONE`**: Grava a máscara de 8 tokens acumulada, trava `reg_dst_len_r`, limpa `BUSY`, ativa `DONE` e gera `irq_o` se habilitado.

---

## 4. Desempenho Empírico (ADR-020, 1024 B) & Utilização (`XC7Z010`)

Medido em silício na Cora Z7-10 (`100 MHz` PL) e verificado bit-a-bit em VUnit/GHDL (`tb_lzss_accel`):

| Perfil de Entropia (`1024 B`) | Saída Comprimida | Space Savings (CR) | Ciclos PL (`100 MHz`) | Tempo PL | Observação (Risco R9) |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Quiescent** | `440–469 B` | `+55.7%` | `193,192–211,667` | `~2.0 ms` | Alta redundância periódica |
| **Dynamic** | `994–1005 B` | `+2.5%` | `570,538–578,440` | `~5.7 ms` | Redundância moderada |
| **Chaotic** | `1152–1154 B` | `-12.6%` | `742,593–746,048` | `~7.4 ms` | Expansão máxima de framing (`<= 2048 B`) |

### Recursos de Silício Consumidos (`lzss_accel_0` pós-implementação Vivado)
* **Slice LUTs:** `667` (`3.79%` dos `17,600` disponíveis no XC7Z010)
* **Slice Registers (FFs):** `457` (`1.30%` dos `35,200` disponíveis)
* **Block RAM:** `0` internas no núcleo (`bmg_lzss_in` + `bmg_lzss_out` externas no Block Design; `9 BRAMs` no sistema completo)
* **DSP48E1:** `0` | **Latches:** `0` | **Fechamento de Timing:** `WNS = +0.551 ns` @ `100 MHz`
