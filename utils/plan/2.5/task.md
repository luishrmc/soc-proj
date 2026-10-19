# Task 2.5: Coprocessador Criptográfico ChaCha20 com Interface AXI4 e Buffer no Block Design

## 1. Resumo da Tarefa e Objetivos

Nesta etapa, implementamos o coprocessador criptográfico simétrico **ChaCha20 Stream Cipher**:
- **Padrão Criptográfico**: IETF RFC 8439 (ChaCha20 and Poly1305 for IETF Protocols).
- **Entidade RTL (`cora7z/app/hw/src/chacha20_engine.vhdl`)**:
  - Matriz de estado de 512 bits (16 palavras de 32 bits):
    - Palavras 0..3: Constantes "expand 32-byte k" (`0x61707865`, `0x3320646e`, `0x79622d32`, `0x6b206574`).
    - Palavras 4..11: Chave de 256 bits (8 palavras de 32 bits Little-Endian).
    - Palavra 12: Contador de blocos de 32 bits (inicia em 1 ou no valor programado).
    - Palavras 13..15: Nonce de 96 bits (3 palavras de 32 bits Little-Endian).
  - Pipeline de 20 rodadas (10 rodadas duplas):
    - Cada rodada dupla consiste em 1 rodada de colunas (4 Quarter-Rounds em paralelo) e 1 rodada de diagonais (4 Quarter-Rounds em paralelo).
    - Operação Quarter-Round: ARX (Add-Rotate-XOR) em 32 bits com rotações à esquerda por 16, 12, 8 e 7 bits.
    - Acumulação final: soma modular $\pmod{2^{32}}$ do estado final de 20 rodadas com o estado inicial para gerar 64 bytes de keystream (16 palavras de 32 bits).
  - Cifragem por fluxo: aplicação de XOR bit-a-bit entre o fluxo de entrada AXI4-Stream e o keystream de 64 bytes gerado.
  - Auto-incremento do contador de blocos para fluxos contínuos multi-bloco.
  - CSRs AXI4-Lite mapeados em `0x43C30000` conforme [`cora7z/app/hw/src/INTERFACES.md`](cora7z/app/hw/src/INTERFACES.md).
- **Arquitetura de Memória no Block Design (ADR-012)**:
  - Não infere buffers de dados em RTL; expõe interfaces AXI4-Stream padronizadas de 32 bits conectadas visualmente a blocos `axis_data_fifo` no canvas do Block Design.
- **Banco de Testes VUnit (`cora7z/app/hw/test/tb_chacha20_engine.vhdl`)**:
  - Validação estrita contra os vetores de ouro oficiais da RFC 8439 (Seção 2.1.1, Seção 2.2.1, Seção 2.3.2 e Seção 2.4.2).
  - Testes de backpressure em AXI-Stream, reset suave e auditoria de registradores MMIO.
- **Integração no Block Design e Bitstream (ADR-011)**:
  - Script Tcl [`cora7z/app/hw/scripts/add_chacha_to_bd.tcl`](cora7z/app/hw/scripts/add_chacha_to_bd.tcl) para instanciar o IP e FIFOs de 32 bits.
  - Execução da automação de síntese e implementação (`build_bitstream.tcl`), gerando o bitstream final consolidado da Fase 2.

---

## 2. Mapa de Registradores AXI4-Lite (`0x43C30000`)

| Offset | Nome | Tipo | Reset | Descrição |
|---|---|---|---|---|
| `0x00` | `CONTROL` | R/W | `0x00000000` | Bit 0: START, Bit 1: RESET_CORE, Bit 2: IRQ_EN |
| `0x04` | `STATUS` | RO | `0x00000000` | Bit 0: BUSY, Bit 1: DONE, Bit 2: ERR |
| `0x08` | `SRC_LEN` | R/W | `0x00000000` | Comprimento do bloco de entrada em bytes |
| `0x0C` | `DST_LEN` | RO | `0x00000000` | Comprimento do bloco de saída em bytes |
| `0x10` | `CYCLE_COUNT` | RO | `0x00000000` | Hardware latency: ciclos de clock ativos na rodada |
| `0x14` | `KEY_0` | R/W | `0x00000000` | Chave de 256 bits palavra 0 (bits [31:0]) |
| `0x18` | `KEY_1` | R/W | `0x00000000` | Chave palavra 1 (bits [63:32]) |
| `0x1C` | `KEY_2` | R/W | `0x00000000` | Chave palavra 2 (bits [95:64]) |
| `0x20` | `KEY_3` | R/W | `0x00000000` | Chave palavra 3 (bits [127:96]) |
| `0x24` | `KEY_4` | R/W | `0x00000000` | Chave palavra 4 (bits [159:128]) |
| `0x28` | `KEY_5` | R/W | `0x00000000` | Chave palavra 5 (bits [191:160]) |
| `0x2C` | `KEY_6` | R/W | `0x00000000` | Chave palavra 6 (bits [223:192]) |
| `0x30` | `KEY_7` | R/W | `0x00000000` | Chave palavra 7 (bits [255:224]) |
| `0x34` | `NONCE_0` | R/W | `0x00000000` | Nonce de 96 bits palavra 0 (bits [31:0]) |
| `0x38` | `NONCE_1` | R/W | `0x00000000` | Nonce palavra 1 (bits [63:32]) |
| `0x3C` | `NONCE_2` | R/W | `0x00000000` | Nonce palavra 2 (bits [95:64]) |
| `0x40` | `BLOCK_COUNTER` | R/W | `0x00000001` | Contador inicial de blocos (padrão 1 na RFC 8439) |

---

## 3. Critérios de Aceitação

1. **Inner Loop**:
   - `TASK_ID=2.5 bash .agents/hooks/vhdl-lint.sh` retorna PASS com 0 erros e 0 warnings.
   - `TASK_ID=2.5 bash .agents/hooks/vhdl-sim-gate.sh chacha20_engine` retorna PASS cobrindo vetores da RFC 8439.
2. **Outer Loop**:
   - `add_chacha_to_bd.tcl` integra `chacha20_engine_0` no Block Design do Vivado em `0x43C30000` com 0 avisos críticos.
   - `build_bitstream.tcl` sintetiza e implementa o design completo da Fase 2 (RLE + LZ4 + AES-CTR + ChaCha20) respeitando o orçamento do Zynq-7010 (< 17,6k LUTs, 0 erros DRC).
   - Atualização da plataforma de hardware `cora7z_top.xsa` com bitstream embutido e sincronização do firmware bare-metal.
