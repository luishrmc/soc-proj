# Task 2.1: Diagnóstico e Configuração do Block Design (PS7 + AXI SPI Escravo + AXI DMA)

## 1. Identificação do Projeto Vivado Existente

Durante a auditoria do workspace, identificamos o projeto Vivado iniciado pelo usuário em:
- **Projeto Vivado**: [`cora7z/app/hw/vivado/soc-final.xpr`](file:///home/luis/ufmg/soc/proj/cora7z/app/hw/vivado/soc-final.xpr)
- **Diagrama de Blocos**: `soc_final_bd_1.bd` localizado em `cora7z/app/hw/vivado/soc-final.srcs/sources_1/bd/soc_final_bd_1/soc_final_bd_1.bd`
- **Dispositivo Alvo**: Xilinx Zynq-7010 (`xc7z010clg400-1`), placa Digilent Cora Z7-10 (`digilentinc.com:cora-z7-10:part0:1.1`).

---

## 2. Diagnóstico das Inconsistências Identificadas no Bloco Inicial

Ao inspecionar o Block Design inicial via script Tcl de diagnóstico, identificamos 5 problemas que impediam o funcionamento correto do hardware:

1. **`axi_interconnect_0` com porta M01 flutuante (Erro Crítico de Validação)**:
   - A remoção de um bloco intermediário anterior (`ahblite_axi_bridge_0`) deixou o `axi_interconnect_0` configurado com `NUM_MI = 2`.
   - A porta `M01_AXI` e o sinal de clock `M01_ACLK` ficaram completamente desconectados, causando falha imediata no comando `validate_bd_design`.
2. **`axi_quad_spi_0` instanciado como MESTRE (Master Mode)**:
   - Por padrão, a automação de placa (`shield_spi`) instancia o núcleo SPI em modo Mestre (`C_SPI_MODE = 0`, `Master_mode = 1`).
   - Como o **ESP32 externo é o Mestre** da comunicação, a FPGA Cora Z7-10 **deve operar obrigatoriamente como Escrava (Slave Mode)** para receber o clock `SCK`, o `CS_n` e os dados `MOSI`.
3. **FIFO do SPI subdimensionada (16 palavras)**:
   - O `C_FIFO_DEPTH` estava em 16 palavras, insuficiente para rajadas contínuas de pacotes de dados sem estourar o buffer antes do atendimento da CPU ou DMA.
4. **Ausência de Clock Rápido de Amostragem (`ext_spi_clk`)**:
   - `ext_spi_clk` estava amarrado ao clock de 50 MHz (`FCLK_CLK0`). Pelo guia PG153 da Xilinx, o clock de amostragem no modo escravo deve ser pelo menos 4 vezes maior que o clock do barramento SPI (para suportar até 25 MHz de SPI, `ext_spi_clk` deve ser de no mínimo 100 MHz).
5. **Portas HP0, Interrupções e DMA Inexistentes**:
   - O PS7 estava sem a porta de alta performance (`S_AXI_HP0`) habilitada.
   - As interrupções de hardware da PL para a CPU (`IRQ_F2P`) estavam desabilitadas.
   - O bloco de DMA de hardware (`axi_dma_0`) não havia sido instanciado.

---

## 3. Correções e Configurações Realizadas via Tcl

Criamos e executamos com sucesso o script Tcl de automação em [`cora7z/app/hw/scripts/configure_block_design.tcl`](file:///home/luis/ufmg/soc/proj/cora7z/app/hw/scripts/configure_block_design.tcl). As seguintes ações foram consolidadas no hardware:

### 3.1 Reconfiguração do Processing System 7 (`processing_system7_0`)
- **Eliminação de Critical Warnings**: Eliminamos valores negativos de skew DQS nos canais 2 e 3 do DDR3 (não utilizados no pacote Zynq-7010).
- **Habilitação da Porta HP0**: Ativada a porta escrava AXI de alta performance de 64 bits (`PCW_USE_S_AXI_HP0 = 1`).
- **Geração de Clock de 100 MHz**: Habilitado o segundo clock da PL (`FCLK_CLK1` @ 100 MHz) para alimentar o DMA e a amostragem rápida do SPI.
- **Habilitação de Interrupções**: Ativadas as interrupções de tecido para o processador (`PCW_USE_FABRIC_INTERRUPT = 1`, `PCW_IRQ_F2P_INTR = 1`).

### 3.2 Reconfiguração do AXI Quad SPI (`axi_quad_spi_0`)
- **Modo Escravo**: `Master_mode = 0`.
- **Buffer FIFO**: Ampliado para 256 palavras (`C_FIFO_DEPTH = 256`).
- **Clock de Amostragem**: Desconectado dos 50 MHz e conectado ao `FCLK_CLK1` (100 MHz).
- **Interrupção**: Sinal `ip2intc_irpt` roteado para a entrada `In0` do concentrador de interrupções (`xlconcat_0`).

### 3.3 Adição e Interconexão do AXI DMA (`axi_dma_0`)
- **Modo Direto / Simples**: Desabilitado Scatter-Gather (`c_include_sg = 0`) para máxima eficiência e economia de recursos.
- **Canais Habilitados**:
  - `MM2S` (Leitura de dados do DDR3 -> Envio para stream de 32 bits a 100 MHz).
  - `S2MM` (Recepção de stream de 32 bits a 100 MHz -> Escrita no DDR3).
- **SmartConnect HP0**: Instanciado `smartconnect_hp0` ligando `M_AXI_MM2S` e `M_AXI_S2MM` diretamente à porta `S_AXI_HP0` da DDR3.
- **Controle AXI-Lite**: Conectado `S_AXI_LITE` à porta `M01_AXI` do `axi_interconnect_0` no endereço base `0x40400000`.
- **Interrupções**: `mm2s_introut` e `s2mm_introut` conectadas a `In1` e `In2` do `xlconcat_0`.

### 3.4 Resultado da Validação
```
=== BLOCK DESIGN CONFIGURED AND VALIDATED SUCCESSFULLY ===
```
O único aviso restante é o esperado `S_AXIS_S2MM interface is unconnected`, que será conectado à saída do nosso primeiro núcleo acelerador (RLE na Task 2.2).

---

## 4. Mapa de Endereços Atualizado e Sincronizado

| Periférico no BD | Bloco AXI | Endereço Base | Endereço Final | Tamanho | Função |
|---|---|---|---|---|---|
| `axi_dma_0` | `S_AXI_LITE/Reg` | `0x40400000` | `0x4040FFFF` | 64 KB | Controlador de DMA para DDR3 |
| `axi_quad_spi_0` | `AXI_LITE/Reg` | `0x41E00000` | `0x41E0FFFF` | 64 KB | Interface SPI Escrava conectada ao ESP32 |
| `rle_engine` *(Próxima Task)* | `s_axi_lite` | `0x43C00000` | `0x43C00FFF` | 4 KB | Acelerador de Compressão RLE |
| `lz4_engine` | `s_axi_lite` | `0x43C10000` | `0x43C10FFF` | 4 KB | Acelerador de Compressão LZ4 |
| `aes_ctr_engine` | `s_axi_lite` | `0x43C20000` | `0x43C20FFF` | 4 KB | Coprocessador Criptográfico AES-128-CTR |
| `chacha20_engine` | `s_axi_lite` | `0x43C30000` | `0x43C30FFF` | 4 KB | Coprocessador Criptográfico ChaCha20 |

---

## 5. Como o Usuário Interage no Vivado GUI a Partir de Agora

Ao reabrir o Vivado:
1. Abra o projeto: `cora7z/app/hw/vivado/soc-final.xpr`.
2. Abra o Block Design `soc_final_bd_1.bd`.
3. Você verá o diagrama completamente conectado, com o PS7 (DDR3, clocks 50/100 MHz), o SPI em modo Escravo com FIFO 256, o AXI DMA conectado ao SmartConnect HP0 e o barramento AXI-Lite configurado.
4. Para adicionar os aceleradores nas próximas tarefas:
   - Adicionaremos o arquivo `.vhdl` sintetizável (ex: `rle_engine.vhdl`).
   - Clicaremos com botão direito no Block Design -> **Add Module...** -> `rle_engine`.
   - Conectamos:
     - `s_axi_lite` ao `axi_interconnect_0` (porta `M02_AXI`).
     - `s_axis` ao `axi_dma_0/M_AXIS_MM2S`.
     - `m_axis` ao `axi_dma_0/S_AXIS_S2MM`.
