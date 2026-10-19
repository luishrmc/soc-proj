# Task 2.3: Núcleo de Compressão LZ4 e Integração como IP no Block Design

## 1. Resumo da Tarefa e Objetivos

Nesta etapa, implementamos o segundo núcleo acelerador em hardware da FPGA:
- **Algoritmo**: Compressão LZ4 simplificada baseada no paradigma de janela deslizante LZ77 (Lempel-Ziv 1977), com tabela hash em hardware para busca de casamento de prefixos de 4 bytes e emissão de sequências alinhadas em bytes.
- **Interfaces Padronizadas**:
  - **AXI4-Lite Slave**: Registradores de Controle e Status (CSR) mapeados no endereço base `0x43C10000` (`CONTROL`, `STATUS`, `SRC_LEN`, `DST_LEN`, `CYCLE_COUNT`).
  - **AXI4-Stream Slave (`s_axis`)**: Ingress de 32 bits a 100 MHz vindo do canal `M_AXIS_MM2S` do AXI DMA / Switch de roteamento.
  - **AXI4-Stream Master (`m_axis`)**: Egress de 32 bits a 100 MHz injetando o fluxo compactado em formato de sequências LZ4.
  - **Interrupção (`irq_o`)**: Pulso ativo em nível alto sinalizando conclusão da compressão para o ARM GIC via `xlconcat_0/In4`.
- **Padronização e Organização dos Logs do Vivado**:
  - Implementação do script unificado `cora7z/app/hw/scripts/run_vivado.sh`, que organiza automaticamente todos os logs (`vivado.log`), diários (`vivado.jou`) e relatórios de execução em pastas estruturadas sob `out/vivado/<context_ou_task_id>/`.
- **Integração no Vivado**: O módulo foi instanciado e conectado com sucesso dentro do Block Design `soc_final_bd_1.bd`.

---

## 2. Entregáveis Produzidos

1. **RTL Sintetizável em VHDL-2008**:
   - Arquivo: [`cora7z/app/hw/src/lz4_engine.vhdl`](cora7z/app/hw/src/lz4_engine.vhdl)
   - Segue estritamente as convenções de código e estilo de comentários observadas no diretório modelo (`corez7/hw/src/blink_led.vhdl`).
   - Implementa buffer circular de histórico (2048 bytes), tabela hash de 1024 entradas com função de dispersão rápida de 4 bytes e empacotador de palavras de 32 bits.
2. **Testbench com Autochecagem VUnit**:
   - Arquivo: [`cora7z/app/hw/test/tb_lz4_engine.vhdl`](cora7z/app/hw/test/tb_lz4_engine.vhdl)
   - Cobre 5 cenários exaustivos:
     - Leitura/escrita dos registradores AXI-Lite (IDLE, START, BUSY, DONE, contadores).
     - Emissão de literais puros (dados não repetitivos sem casamentos).
     - Detecção de casamento no dicionário (frases repetitivas gerando sequências com offset e token).
     - Fluxo estruturado (simulação de registros de telemetria).
     - Backpressure e estol de vazão (`m_axis_tready = '0'` forçando retenção síncrona sem perda de dados).
3. **Documento Teórico e de Arquitetura**:
   - Arquivo: [`docs/LZ4_ALGORITHM.md`](docs/LZ4_ALGORITHM.md)
   - Explicação detalhada da teoria de Lempel-Ziv (LZ77), limites assintóticos de Shannon, formato de sequências e tokens LZ4 (nibble de literal e nibble de casamento), codificação de extensões de comprimento, arquitetura de hardware em FPGA e referências bibliográficas formais.
4. **Script de Automação de Execução e Logs**:
   - Arquivo: [`cora7z/app/hw/scripts/run_vivado.sh`](cora7z/app/hw/scripts/run_vivado.sh)
   - Executa scripts Tcl em lote garantindo isolamento de diretórios de saída e relatórios em `out/vivado/<context>/`.
5. **Script de Automação do Vivado Block Design**:
   - Arquivo: [`cora7z/app/hw/scripts/add_lz4_to_bd.tcl`](cora7z/app/hw/scripts/add_lz4_to_bd.tcl)
   - Adiciona o arquivo fonte ao projeto Vivado, instancia a referência de módulo `lz4_engine_0`, realiza todas as conexões de barramentos, gera o relatório de mapa de endereços e valida o design com zero Critical Warnings.

---

## 3. Dual-Mode Co-Development: Trabalho em CLI e Vivado GUI

### 3.1 O que foi executado via CLI (AI Assistant)
- **Compilação e Linting Estático**:
  ```bash
  TASK_ID=2.3 bash .agents/hooks/vhdl-lint.sh
  # Resultado: [gate] 2.3 vhdl-lint PASS (zero avisos em GHDL)
  ```
- **Simulação Determinística VUnit + GHDL**:
  ```bash
  TASK_ID=2.3 bash .agents/hooks/vhdl-sim-gate.sh
  # Resultado: [gate] 2.3 vhdl-sim PASS (12/12 testes aprovados)
  ```
- **Execução do Script Vivado Batch com Logs Estruturados**:
  ```bash
  bash cora7z/app/hw/scripts/run_vivado.sh cora7z/app/hw/scripts/add_lz4_to_bd.tcl task_2.3
  # Logs salvos em: out/vivado/task_2.3/vivado.log
  # Resultado: BLOCK DESIGN WITH LZ4_ENGINE VALIDATED SUCCESSFULLY (Exit code 0)
  ```

### 3.2 O que o usuário pode conferir e fazer no Vivado GUI
Ao abrir o Vivado GUI em [`cora7z/app/hw/vivado/soc-final.xpr`](cora7z/app/hw/vivado/soc-final.xpr) e navegar até o diagrama `soc_final_bd_1.bd`:
1. **Instância `lz4_engine_0`**:
   - O bloco `lz4_engine_0` está presente no diagrama ao lado de `rle_engine_0`.
2. **Conexões do Controle AXI4-Lite**:
   - `axi_interconnect_0` agora possui 4 portas mestres:
     - `M00_AXI` $\rightarrow$ `axi_quad_spi_0` (`0x41E00000`)
     - `M01_AXI` $\rightarrow$ `axi_dma_0` (`0x40400000`)
     - `M02_AXI` $\rightarrow$ `rle_engine_0` (`0x43C00000`)
     - `M03_AXI` $\rightarrow$ `lz4_engine_0` (`0x43C10000`)
3. **Conexões de Clocks e Resets**:
   - `lz4_engine_0/aclk` está conectado a `processing_system7_0/FCLK_CLK1` (100 MHz).
   - `lz4_engine_0/aresetn` está conectado a `rst_ps7_100M/peripheral_aresetn`.
4. **Interrupções**:
   - `xlconcat_0` foi expandido para 5 entradas (`In0`=SPI, `In1`=DMA MM2S, `In2`=DMA S2MM, `In3`=RLE, `In4`=`lz4_engine_0/irq_o`).
5. **Mapeamento de Memória (Address Editor)**:
   - Abra a aba **Address Editor** no Vivado:
   - Verifique o segmento `/lz4_engine_0/s_axi_lite/reg0` mapeado em `0x43C10000` (Faixa de 64 KB).
