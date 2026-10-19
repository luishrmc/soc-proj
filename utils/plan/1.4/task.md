# Task 1.4: Setup da Plataforma Vitis e Firmware Bare-Metal de Baseline

## 1. Resumo da Tarefa e Objetivos

Nesta etapa, implementamos a infraestrutura completa de software embarcado para o processador ARM Cortex-A9 do Zynq-7010:
- **Workspace Vitis**: Criado e gerenciado em `cora7z/app/sw/vitis` através do fluxo unificado do Vitis 2026.1 via CLI (`vitis -s`).
- **Plataforma de Hardware (`cora7z_platform`)**:
  - Gerada diretamente a partir do contêiner de abstração de hardware `cora7z/app/hw/vivado/cora7z_top.xsa`.
  - Processador: ARM Cortex-A9 Core 0 (`ps7_cortexa9_0`) operando a 667 MHz.
  - Sistema Operacional: Bare-metal (`standalone`).
  - Geração automática do Board Support Package (BSP) contendo os drivers dos periféricos e o cabeçalho canônico de memória `xparameters.h`.
- **Script de Automação de Build (`cora7z/app/sw/scripts/build_sw.py`)**:
  - Script em Python utilizando a API oficial do Vitis 2026.1 (`vitis.create_client()`) para criação não interativa da plataforma, configuração do toolchain e compilação de código C.
- **Aplicação de Verificação (`cora7z/app/sw/src/main.c`)**:
  - Código C11 bare-metal determinístico (zero alocação dinâmica, flags `-Wall -Wextra -Werror -O2`).
  - Inicialização da UART PS (115200 bps, 8N1).
  - Auditoria em tempo de compilação e leitura de sanidade dos registradores CSR de todos os blocos AXI mapeados (`AXI DMA`, `AXI SPI`, `RLE Engine`, `LZ4 Engine`).
  - Habilitação e calibração do ARM Performance Monitor Unit (PMU) via registrador CP15 (`PMCCNTR`) para contagem precisa de ciclos de clock.

---

## 2. Entregáveis Produzidos

1. **Script de Automação Vitis Python**:
   - Arquivo: [`cora7z/app/sw/scripts/build_sw.py`](file:///home/luis/ufmg/soc/proj/cora7z/app/sw/scripts/build_sw.py)
   - Cria o workspace, configura o componente de plataforma, compila o BSP e constrói o binário executável `.elf`.
2. **Código-Fonte da Aplicação de Verificação**:
   - Arquivo: [`cora7z/app/sw/src/main.c`](file:///home/luis/ufmg/soc/proj/cora7z/app/sw/src/main.c)
   - Implementa a rotina de boot, teste de registradores e instrumentação de ciclos do Cortex-A9.
3. **Plano de Execução e Handoff**:
   - Arquivo: [`utils/plan/1.4/task.md`](file:///home/luis/ufmg/soc/proj/utils/plan/1.4/task.md)
   - Detalha os passos do fluxo CLI e como o usuário pode inspecionar e debugar o software no Vitis GUI.

---

## 3. Dual-Mode Co-Development: Trabalho em CLI e Vitis GUI

### 3.1 Execução Automatizada via CLI (AI Assistant)
- **Geração da Plataforma e Compilação da Aplicação**:
  ```bash
  source .agents/env.sh
  vitis -s cora7z/app/sw/scripts/build_sw.py
  ```
- **Critérios de Aceitação CLI**:
  - Código de retorno `0`.
  - Zero erros e zero avisos de compilação (`-Wall -Wextra -Werror`).
  - Binário executável gerado: `cora7z/app/sw/vitis/cora7z_firmware/build/cora7z_firmware.elf`.

### 3.2 Como o Usuário Valida e Depura no Vitis GUI
1. Conecte a placa Digilent Cora Z7-10 ao computador através do cabo Micro-USB (JTAG / UART).
2. Abra a interface gráfica do Vitis diretamente no workspace criado:
   ```bash
   vitis -w cora7z/app/sw/vitis
   ```
3. O Vitis 2026.1 abrirá exibindo na árvore de componentes:
   - **`cora7z_platform`**: A plataforma com o BSP bare-metal gerado a partir do hardware.
   - **`cora7z_firmware`**: A aplicação de teste de baseline compilada.
4. Abra um terminal serial (ex: `minicom -D /dev/ttyUSB1 -b 115200` ou `picocom`) para visualizar as mensagens de log da UART PS.
5. No Vitis GUI, clique com o botão direito no componente `cora7z_firmware` -> **Debug** -> **Launch Hardware (Single Application Debug)**.
6. O Vitis gravará o `.elf` na memória DDR3 do Cortex-A9 e suspenderá a execução na primeira linha da função `main()`.
7. Clique em **Resume (F8)** para rodar o teste completo e visualizar no terminal serial o relatório de autochecagem dos registradores e os ciclos do ARM PMU.
