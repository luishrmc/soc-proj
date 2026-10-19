# Task 2.4: Coprocessador Criptográfico AES-128-CTR com Interface AXI4 e Buffer no Block Design

## 1. Resumo da Tarefa e Objetivos

Nesta etapa, implementamos o coprocessador criptográfico simétrico **AES-128 em Modo Contador (AES-CTR)**:
- **Padrões de Criptografia**: NIST FIPS-197 (Advanced Encryption Standard) e NIST SP 800-38A (Recommendation for Block Cipher Modes of Operation: Methods and Techniques).
- **Entidade RTL (`cora7z/app/hw/src/aes_ctr_engine.vhdl`)**:
  - Cifra de bloco de 128 bits com chave de 128 bits (10 rodadas de transformação).
  - Transformações diretas: `SubBytes` (S-Box direta), `ShiftRows`, `MixColumns`, `AddRoundKey`.
  - Operação em modo CTR (Counter): Cifra o bloco de contador composto por $\text{Nonce/IV (96 bits)} \parallel \text{Counter (32 bits)}$ para produzir o keystream, que é aplicado por operação XOR bit-a-bit sobre o fluxo de dados em AXI4-Stream.
  - Como a cifragem e decifragem em modo CTR são idênticas (ambas executam a cifra direta $E_K$ do contador e fazem XOR com o fluxo), não é necessário implementar a S-Box inversa, poupando metade da área lógica na FPGA.
  - Mapeamento AXI4-Lite completo conforme [`cora7z/app/hw/src/INTERFACES.md`](file:///home/luis/ufmg/soc/proj/cora7z/app/hw/src/INTERFACES.md) em `0x43C20000` (CSRs comuns + registradores específicos `KEY_0..3`, `IV_0..2`, `COUNTER_INIT`).
- **Arquitetura de Memória no Block Design (ADR-012)**:
  - Não infere buffers gigantes em RTL. A entidade expõe interfaces AXI4-Stream de 32 bits padronizadas (`S_AXIS`, `M_AXIS`) prontas para conexão com blocos `axis_data_fifo` na tela do Block Design do Vivado.
- **Banco de Testes VUnit (`cora7z/app/hw/test/tb_aes_ctr_engine.vhdl`)**:
  - Validação estrita contra os vetores oficiais do NIST SP 800-38A (chaves conhecidas, IVs conhecidos e textos planos oficiais).
  - Teste de backpressure AXI-Stream (`tready = '0'`), controle de registradores AXI-Lite e integridade de contagem de ciclos PMU/Hardware.
- **Documentação Teórica (`docs/AES_CTR_ALGORITHM.md`)**:
  - Fundamentos do algoritmo AES, matemática do corpo de Galois $GF(2^8)$, matriz de MixColumns e diagramas Mermaid do pipeline.
- **Integração no Block Design e Bitstream**:
  - Script Tcl [`cora7z/app/hw/scripts/add_aes_to_bd.tcl`](file:///home/luis/ufmg/soc/proj/cora7z/app/hw/scripts/add_aes_to_bd.tcl) para instanciar o IP e conectá-lo ao AXI Interconnect (`M03_AXI`) e AXI DMA.
  - Execução do loop de síntese e bitstream automatizado (`build_bitstream.tcl`).

---

## 2. Mapa de Registradores AXI4-Lite (`0x43C20000`)

| Offset | Nome | Tipo | Reset | Descrição |
|---|---|---|---|---|
| `0x00` | `CONTROL` | R/W | `0x00000000` | Bit 0: START, Bit 1: RESET_CORE, Bit 2: IRQ_EN |
| `0x04` | `STATUS` | RO | `0x00000000` | Bit 0: BUSY, Bit 1: DONE, Bit 2: ERR |
| `0x08` | `SRC_LEN` | R/W | `0x00000000` | Comprimento do bloco de entrada em bytes |
| `0x0C` | `DST_LEN` | RO | `0x00000000` | Comprimento do bloco processado em bytes |
| `0x10` | `CYCLE_COUNT` | RO | `0x00000000` | Contador de ciclos de clock ativos na rodada |
| `0x14` | `KEY_0` | R/W | `0x00000000` | Chave AES bits [31:0] (Little-Endian) |
| `0x18` | `KEY_1` | R/W | `0x00000000` | Chave AES bits [63:32] |
| `0x1C` | `KEY_2` | R/W | `0x00000000` | Chave AES bits [95:64] |
| `0x20` | `KEY_3` | R/W | `0x00000000` | Chave AES bits [127:96] |
| `0x24` | `IV_0` | R/W | `0x00000000` | Nonce/IV bits [31:0] |
| `0x28` | `IV_1` | R/W | `0x00000000` | Nonce/IV bits [63:32] |
| `0x2C` | `IV_2` | R/W | `0x00000000` | Nonce/IV bits [95:64] |
| `0x30` | `COUNTER_INIT` | R/W | `0x00000001` | Valor inicial do contador (bits [127:96] do bloco CTR) |

---

## 3. Critérios de Aceitação

1. **Inner Loop**:
   - `TASK_ID=2.4 bash .agents/hooks/vhdl-lint.sh` retorna PASS com 0 erros e 0 warnings.
   - `TASK_ID=2.4 bash .agents/hooks/vhdl-sim-gate.sh aes_ctr_engine` retorna PASS cobrindo vetores do NIST.
2. **Outer Loop**:
   - `add_aes_to_bd.tcl` integra o IP no Block Design do Vivado em `0x43C20000`.
   - `build_bitstream.tcl` executa síntese, implementação e geração de bitstream com utilização dentro do orçamento do Zynq-7010 (< 17,6k LUTs) e 0 erros de DRC.
   - Atualização do contêiner `cora7z_top.xsa` contendo o bitstream embutido.
