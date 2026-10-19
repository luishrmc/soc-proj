# Task 2.2: Núcleo de Compressão RLE e Integração como IP no Block Design

## 1. Resumo da Tarefa e Objetivos

Nesta etapa, implementamos o primeiro núcleo acelerador em hardware da FPGA:
- **Algoritmo**: Compressão Run-Length Encoding (RLE) com empacotamento de tuplas de 16 bits `[count (8 bits), symbol (8 bits)]` sobre barramento AXI4-Stream de 32 bits.
- **Interfaces Padrão**:
  - **AXI4-Lite Slave**: Registradores de Controle e Status (CSR) mapeados no endereço base `0x43C00000` (`CONTROL`, `STATUS`, `SRC_LEN`, `DST_LEN`, `CYCLE_COUNT`).
  - **AXI4-Stream Slave (`s_axis`)**: Ingress de 32 bits a 100 MHz vindo do canal `M_AXIS_MM2S` do AXI DMA.
  - **AXI4-Stream Master (`m_axis`)**: Egress de 32 bits a 100 MHz injetando o fluxo compactado diretamente no canal `S_AXIS_S2MM` do AXI DMA.
  - **Interrupção (`irq_o`)**: Pulso ativo em nível alto sinalizando conclusão da compressão para o ARM GIC via `xlconcat_0/In3`.
- **Integração no Vivado**: O módulo foi instanciado e conectado com sucesso dentro do Block Design `soc_final_bd_1.bd`, eliminando em definitivo o Critical Warning anterior de `S_AXIS_S2MM unconnected`.

---

## 2. Entregáveis Produzidos

1. **RTL Sintetizável em VHDL-2008**:
   - Arquivo: [`cora7z/app/hw/src/rle_engine.vhdl`](cora7z/app/hw/src/rle_engine.vhdl)
   - Segue estritamente as convenções de código e estilo de comentários observadas no diretório modelo (`corez7/hw/src/blink_led.vhdl`).
   - Sem latches inferidos, totalmente síncrono com borda de subida única em 100 MHz (`aclk`), reset ativo baixo (`aresetn`).
2. **Testbench com Autochecagem VUnit**:
   - Arquivo: [`cora7z/app/hw/test/tb_rle_engine.vhdl`](cora7z/app/hw/test/tb_rle_engine.vhdl)
   - Cobre 5 cenários exaustivos:
     - Leitura/escrita dos registradores AXI-Lite (IDLE, START, BUSY, DONE, contadores).
     - Fluxo de alta redundância (64 bytes de `'A'` comprimidos em 2 bytes `[64, 'A']`).
     - Múltiplas corridas alternadas (`AAAAABBBCCCC`).
     - Saturação de contagem (> 255 bytes idênticos gerando múltiplas tuplas `[255, byte] + [rest, byte]`).
     - Backpressure e estol de vazão (`m_axis_tready = '0'` forçando retenção síncrona sem perda de dados).
3. **Documento Teórico e de Arquitetura**:
   - Arquivo: [`docs/RLE_ALGORITHM.md`](docs/RLE_ALGORITHM.md)
   - Explicação detalhada da teoria da informação, limites de entropia de Shannon, cálculo da taxa de compressão ($CR = L_{out}/L_{in}$), formato de tupla little-endian, máquina de estados finitos (FSM de 4 estados), diagrama temporal de handshakes AXI e procedimentos de benchmark de ciclos de clock.
4. **Script de Automação do Vivado Block Design**:
   - Arquivo: [`cora7z/app/hw/scripts/add_rle_to_bd.tcl`](cora7z/app/hw/scripts/add_rle_to_bd.tcl)
   - Adiciona o arquivo fonte ao projeto Vivado, instancia a referência de módulo `rle_engine_0`, realiza todas as conexões de barramentos e valida o design com zero Critical Warnings.

---

## 3. Dual-Mode Co-Development: Trabalho em CLI e Vivado GUI

### 3.1 O que foi executado via CLI (AI Assistant)
- **Compilação e Linting Estático**:
  ```bash
  TASK_ID=2.2 bash .agents/hooks/vhdl-lint.sh
  # Resultado: [gate] 2.2 vhdl-lint PASS (zero avisos)
  ```
- **Simulação Determinística VUnit + GHDL**:
  ```bash
  TASK_ID=2.2 bash .agents/hooks/vhdl-sim-gate.sh
  # Resultado: [gate] 2.2 vhdl-sim PASS (7/7 testes aprovados)
  ```
- **Execução do Script Vivado Batch**:
  ```bash
  vivado -mode batch -notrace -source cora7z/app/hw/scripts/add_rle_to_bd.tcl
  # Resultado: BLOCK DESIGN WITH RLE_ENGINE VALIDATED SUCCESSFULLY (Exit code 0)
  ```

### 3.2 O que o usuário pode conferir e fazer no Vivado GUI
Ao abrir o Vivado (`cora7z/app/hw/vivado/soc-final.xpr`) e navegar até o diagrama `soc_final_bd_1.bd`:
1. **Instância `rle_engine_0`**:
   - O bloco `rle_engine_0` está agora presente no diagrama de blocos.
2. **Conexões do Datapath AXI4-Stream**:
   - `axi_dma_0/M_AXIS_MM2S` está conectado a `rle_engine_0/s_axis`.
   - `rle_engine_0/m_axis` está conectado a `axi_dma_0/S_AXIS_S2MM`.
   - *Consequência direta*: O Critical Warning `S_AXIS_S2MM interface is unconnected` foi totalmente eliminado!
3. **Conexões do Controle AXI4-Lite**:
   - `axi_interconnect_0` agora possui 3 portas mestres (`M00_AXI` -> SPI, `M01_AXI` -> DMA, `M02_AXI` -> `rle_engine_0/s_axi_lite`).
4. **Conexões de Clocks e Resets**:
   - `rle_engine_0/aclk` está conectado a `processing_system7_0/FCLK_CLK1` (100 MHz).
   - `rle_engine_0/aresetn` está conectado a `rst_ps7_100M/peripheral_aresetn`.
5. **Interrupções**:
   - `xlconcat_0` foi expandido para 4 entradas (`In0`=SPI, `In1`=DMA MM2S, `In2`=DMA S2MM, `In3`=`rle_engine_0/irq_o`), conectando todas as interrupções ao `IRQ_F2P` do Cortex-A9.
6. **Mapeamento de Memória (Address Editor)**:
   - Abra a aba **Address Editor** no Vivado:
   - Verifique o segmento `/rle_engine_0/s_axi_lite/reg0` mapeado em `0x43C00000` (Faixa de 64 KB).

---

## 4. Próximos Passos
- Avançar para a Task 2.3 (Núcleo de compressão LZ4) ou dar prosseguimento aos demais módulos da PL conforme o cronograma.
