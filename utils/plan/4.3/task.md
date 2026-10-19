# Task 4.3: Drivers de Comunicação AXI para Controle dos Aceleradores (AXI DMA, Quad SPI e Coprocessadores)

## 1. Resumo da Tarefa e Objetivos

Nesta etapa, desenvolvemos a camada completa de drivers bare-metal em C11 para comunicação com os periféricos mapeados em barramento AXI na Programmable Logic (PL) da Digilent Cora Z7-10 (Zynq-7010):
- **Alinhamento às Recomendações dos Fabricantes (Xilinx / AMD)**:
  - **AXI DMA v7.1 (LogiCORE IP PG021)**:
    - Controle em modo *Simple DMA* para transferências de alta taxa entre memória DDR3 e os aceleradores em stream (MM2S e S2MM).
    - Procedimento de reset determinístico (`DMACR.Reset = 1`, polling até zerar).
    - Gerenciamento de coerência de cache L1/L2 (`Xil_DCacheFlushRange` para TX antes do início de MM2S, e `Xil_DCacheInvalidateRange` para RX antes e após S2MM).
    - Decodificação de erros de barramento (`DMASR`: `Err_Int`, `Err_Slave`, `Err_Decode`, `Halted`, `Idle`).
  - **AXI Quad SPI v3.2 (LogiCORE IP PG153)**:
    - Operação como escravo SPI de alta velocidade conectado aos pinos `G20` (SCLK), `T10` (MOSI), `V15` (MISO), `F16` (CS#) da Cora Z7.
    - Reset por software via registrador `SRR` (chave `0x0A`), configuração do registrador `CR` (habilitação do sistema SPI, inibição de transmissão do mestre, limpeza de FIFOs de 256 bytes).
    - Drenagem e leitura de pacotes recebidos pela FIFO `DRR` e monitoramento de `SR` (`Rx_Empty`, `Rx_Full`).
    - Validação e desempacotamento de quadros conforme [`INTERFACES.md`](cora7z/app/hw/src/INTERFACES.md) (preâmbulo `0xAA55`, flags de compressão/cifra, tamanho de 32 bits Big-Endian, payload e CRC-16-CCITT).
  - **Controlador de Aceleradores AXI4-Lite (`axi_accel_ctrl`)**:
    - Abstração padronizada para os 4 módulos de aceleração da PL:
      - RLE Compression Engine (`0x43C00000`)
      - LZ4 Compression Engine (`0x43C10000`)
      - AES-128-CTR Engine (`0x43C20000`)
      - ChaCha20 Engine (`0x43C30000`)
    - Configuração dos CSRs comuns (`CONTROL`, `STATUS`, `SRC_LEN`, `DST_LEN`, `CYCLE_COUNT`).
    - Configuração de chaves e vetores de inicialização:
      - AES-CTR: Registradores `KEY_0..3`, `IV_0..2`, `COUNTER_INIT`.
      - ChaCha20: Registradores `KEY_0..7`, `NONCE_0..2`, `BLOCK_COUNTER`.
    - Polling com timeout seguro e contagem precisa de ciclos de hardware.
  - **Gerenciador de Pipeline e Enlace SPI-PL-PS (`pipeline_mgr`)**:
    - Coordena a recepção de dados via SPI pelo AXI Quad SPI.
    - Encaminha os blocos recebidos para os aceleradores na PL via AXI DMA (ou para os algoritmos de software no PS para o Cenário 1).
    - Monitora a integridade dos dados e computa métricas de latência e taxa de transferência.
  - **Prevenção de Falhas de Barramento (ADR-012)**:
    - Verificação de `is_pl_programmed()` via DEVCFG (`0xF800700C`, bit 2 `PCFG_DONE`) antes de qualquer acesso MMIO aos periféricos na PL para prevenir congelamentos irreversíveis do Cortex-A9.

---

## 2. Estrutura Modular dos Drivers

```text
cora7z/app/sw/
├── src/
│   ├── axi_accel_ctrl.h / axi_accel_ctrl.c   # Driver para os 4 aceleradores da PL
│   ├── axi_dma_driver.h / axi_dma_driver.c   # Driver AXI DMA Simple Mode (PG021)
│   ├── axi_spi_receiver.h / axi_spi_receiver.c # Driver AXI Quad SPI (PG153) e parser de quadros
│   ├── pipeline_mgr.h / pipeline_mgr.c       # Orquestrador SPI <-> PL <-> PS
│   └── main.c                                # Baseline firmware com auto-teste dos drivers
└── test/
    └── test_axi_drivers.c                    # Suíte de teste unitário host com mocks MMIO
```

---

## 3. Critérios de Aceitação

1. **Host Mock Unit Verification**:
   - Compilação e execução da suíte de teste [`test_axi_drivers.c`](cora7z/app/sw/test/test_axi_drivers.c) no hospedeiro com `gcc -Wall -Wextra -Werror -std=c11 -O2`.
   - 100% de aprovação nos testes de registradores, sequências de reset do AXI DMA, leitura/escrita de chaves e desempacotamento de quadros SPI com validação de CRC-16.
2. **Inner Loop Static Verification**:
   - `TASK_ID=4.3 bash .agents/hooks/c-lint.sh` retorna PASS com 0 erros de compilação, 0 warnings e conformidade com zero alocação dinâmica.
3. **Vitis Unified Build Gate**:
   - `TASK_ID=4.3 bash .agents/hooks/vitis-gate.sh` compila limpo com ARM GCC gerando `cora7z_firmware.elf` com todos os símbolos e drivers AXI vinculados.
4. **Governança e Sincronização do Plano**:
   - Atualização do cronograma via `plan-sync.py set 4.3 "Concluída"`.
