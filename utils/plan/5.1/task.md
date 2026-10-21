# Task 5.1: Montagem física do enlace SPI entre ESP32 e Cora Z7

## 1. Resumo da Tarefa e Objetivos

O objetivo da Tarefa 5.1 é estabelecer e validar a comunicação serial síncrona ponto a ponto via SPI (Modo 0, até 25 MHz) entre o injetor de dados sintéticos baseado em ESP32 e o SoC Zynq-7010 (Digilent Cora Z7-10). O enlace transporta os quatro perfis de carga sintética do projeto:
1. **RLE**: 64 bytes (dados repetitivos com alto fator de compressão).
2. **LZ4**: 1.024 bytes (janela mista de texto/código com padrões recorrentes).
3. **AES-128-CTR**: 65.536 bytes (dados pseudo-aleatórios de alta entropia para cifragem).
4. **ChaCha20**: 65.536 bytes (dados pseudo-aleatórios de alta entropia para cifragem em fluxo).

Cada quadro segue o protocolo rígido documentado em `cora7z/app/hw/src/INTERFACES.md`: preâmbulo (`0xAA55`), tipo de payload (1 byte), flags de controle (1 byte), tamanho do payload em formato Big-Endian (4 bytes), payload e CRC-16-CCITT final (2 bytes, polinômio `0x1021`).

---

## 2. Diagnóstico de Falhas e Análise de Causa-Raiz (Root-Cause Analysis)

Durante a integração física inicial na branch `fix/spi-esp32-integration`, os quadros transmitidos pelo ESP32 não eram computados pelo receptor AXI Quad SPI na Cora Z7. Uma auditoria técnica em 4 camadas identificou e corrigiu três causas-raiz fundamentais:

### 2.1 Causa-Raiz 1: Deseleção Permanente do Escravo SPI pelo Vivado Board Flow (`spisel => '1'`)
- **Sintoma**: O registrador de status `SPISR` (offset `0x64`) mantinha o bit 5 (`SLAVE_MODE_SELECT`) em `0` e o registrador de ocupação de FIFO de recepção (`RX_FIFO_OCY`, offset `0x94`) permanecia zerado, mesmo com sinais de clock e dados comprovadamente ativos no barramento.
- **Causa**: Ao utilizar a interface de placa predefinida da Digilent (`shield_spi`) no Vivado Block Design, a ferramenta conectou apenas `ss_i(0)` e amarrou o sinal ativo em nível baixo `spisel` internamente a `'1'` (`VCC`). De acordo com o manual Xilinx LogiCORE IP PG153 (pág. 24), o escravo SPI só inicializa suas máquinas de estado internas de amostragem quando a entrada `spisel` é levada a nível baixo `'0'`.
- **Solução**: Desacoplou-se a interface de placa `shield_spi`, expondo portas discretas no BD (`spi_sck_i`, `spi_mosi_i`, `spi_miso_o`, `spi_ss_i`). Conectou-se o sinal externo `spi_ss_i` simultaneamente a `ss_i(0)` e a `spisel`, com restrição `PULLUP true` no arquivo XDC.

### 2.2 Causa-Raiz 2: Violação de Setup/Hold de Chip Select no Master ESP32
- **Sintoma**: O primeiro byte do cabeçalho SPI (`0xAA`) sofria corrupção de amostragem no primeiro bit (aparecendo como `0x55` ou deslocado).
- **Causa**: No Zynq PL, o IP `axi_quad_spi` utiliza um sincronizador de 2 estágios de flip-flops no domínio `ext_spi_clk` (100 MHz) para amostrar os sinais assíncronos de entrada. Como o driver padrão do ESP32 ativava o sinal CS quase simultaneamente com a primeira borda de subida do SCK, o atraso de sincronização (~20 ns) fazia o escravo perder o início do primeiro ciclo de clock.
- **Solução**: Configurou-se o dispositivo SPI no ESP-IDF v6.1 com flag `SPI_DEVICE_HALFDUPLEX` e parâmetros de temporização explícitos:
  - `.cs_ena_pretrans = 2`: CS desce para nível baixo exatamente 2 ciclos de clock antes do primeiro chaveamento de SCK.
  - `.cs_ena_posttrans = 2`: CS permanece baixo por 2 ciclos de clock após a conclusão do último bit antes de subir para nível alto.
  - Alocação de buffer estático `DMA_ATTR uint8_t s_dma_tx_buf[]` eliminando qualquer overhead de `malloc`/`free` no caminho crítico.

### 2.3 Inovação: Gatilho Autônomo de Disparo via PS EMIO GPIO (Cora Z7 -> ESP32)
- **Problema de Usabilidade**: O início da transmissão dependia do acionamento manual do botão na protoboard (`GPIO 32`), inviabilizando testes automatizados e reprodutíveis em regime contínuo.
- **Implementação**:
  - Habilitou-se o controlador de GPIO EMIO no PS7 (`PCW_EN_EMIO_GPIO = 1`).
  - Utilizou-se uma fatia de 1 bit (`xlslice`) conectada a `processing_system7_0/GPIO_O[0]` e mapeada para a porta de saída discreta `esp32_trigger_o[0]`.
  - No XDC (`cora_z7_io.xdc`), mapeou-se a saída para o pino `Y18` (PMOD JA Pino 1, 3.3V LVCMOS).
  - No firmware bare-metal (`cora7z/app/sw/src/main.c`), implementou-se `esp32_trigger_init()` e `trigger_esp32_burst()` (pulso de 30 ms em nível baixo), permitindo ao Cortex-A9 disparar o ESP32 sob demanda programática.

---

## 3. Matriz de Conexão Física (Pinout do Enlace)

| Sinal | Direção | Pino Cora Z7 (FPGA) | Conector Cora Z7 | Pino ESP32 | Descrição Funcional |
|---|---|---|---|---|---|
| **SCK** | ESP32 -> Zynq | `H15` | **Header J7 Pino 3** | `GPIO 18` | Clock SPI (Modo 0, amostragem na borda de subida) |
| **MOSI** | ESP32 -> Zynq | `T12` | **Header J7 Pino 4** | `GPIO 23` | Master-Out Slave-In (dados seriais do injetor) |
| **MISO** | Zynq -> ESP32 | `W15` | **Header J7 Pino 1** | `GPIO 19` | Master-In Slave-Out (dados seriais do escravo) |
| **CS / SS** | ESP32 -> Zynq | `F16` | **Header J7 Pino 5** | `GPIO 5` | Slave Select ativo em nível baixo (PULLUP interno) |
| **TRIGGER**| Zynq -> ESP32 | `Y18` | **PMOD JA Pino 1** | `GPIO 32` | Disparo autônomo ativo em nível baixo (pulso de 30 ms) |
| **GND** | Bidirecional | `GND` | **Header J7 Pino 6** | `GND` | Referência comum de terra (obrigatório) |

---

## 4. Roteiro de Scripts e Modificações

1. **Automação Vivado**:
   - `cora7z/app/hw/scripts/apply_spi_and_trigger_fix.tcl`: Script Tcl idempotente que abre o Block Design, configura o PS EMIO com `xlslice`, substitui a interface `shield_spi` pelas portas discretas e conecta `spisel`.
   - `cora7z/app/hw/scripts/build_bitstream.tcl`: Atualizado para forçar `-top -force` na geração do wrapper HDL e síntese do bitstream.
   - `cora7z/app/hw/utils/cora_z7_io.xdc`: Atualizado com restrições dos pinos discretos de SPI e do pino `Y18` de trigger.
2. **Firmware Zynq (Cortex-A9)**:
   - `cora7z/app/sw/src/main.c`: Adição do driver de trigger EMIO (`0xE000A048`), loop contínuo de recepção de pacotes SPI com validação de CRC-16 e emissão de telemetria serial em `/dev/ttyUSB1`.
3. **Firmware ESP32**:
   - `esp32/main/spi_injector_master.c`: Configuração de `SPI_DEVICE_HALFDUPLEX`, `.cs_ena_pretrans = 2`, `.cs_ena_posttrans = 2`, eliminação de heap com `s_dma_tx_buf`.
   - `esp32/README.md`: Documentação completa da nova fiação e do modo de disparo autônomo.
4. **Memória Técnica e Decisões**:
   - Registro de ADR-016 em `utils/memory/decisions.md`.
   - Atualização de lições aprendidas em `utils/memory/lessons.md`.
   - Sincronização dos digests de módulos (`esp32_injector.md`, `interfaces.md`, `vitis_platform.md`).

---

## 5. Critérios de Aceitação e Evidências On-Target (DoD)

1. **Síntese e Bitstream Fechados**:
   - `cora7z_top.bit` e `cora7z_top.xsa` gerados sem violações de DRC ou timing ($WNS > 0$).
2. **Recepção Confiável On-Target**:
   - Validação em hardware real via `/dev/ttyUSB1` com recepção contínua e sequencial dos 4 tipos de payloads:
     - `0x01` (RLE - 64 bytes): CRC OK.
     - `0x02` (LZ4 - 1024 bytes): CRC OK.
     - `0x03` (AES-128-CTR - 65536 bytes): CRC OK.
     - `0x04` (ChaCha20 - 65536 bytes): CRC OK.
   - 0 pacotes descartados, 0 erros de CRC, 100% de integridade de enquadramento.
3. **Disparo Autônomo Validado**:
   - Pulso emitido pelo Cortex-A9 aciona perfeitamente o ESP32 sem toque físico na placa.
4. **Conclusão Formal no Plano**:
   - Tarefa 5.1 marcada como `Concluída` no cronograma via `plan-sync.py`.
