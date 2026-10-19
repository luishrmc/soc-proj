# Task 5.0: Firmware ESP32: UI Autônoma (Botões/LEDs), Testes On-Target e Validação Sintética

## 1. Resumo da Tarefa e Motivação

### Restrição Física Crítica de Bancada (Cabo Único)
O laboratório dispõe de apenas **um único cabo micro-USB**. Isso impõe a multiplexação temporal da conexão com o computador hospedeiro:
1. **Fase 1 (Desenvolvimento e Validação do ESP32)**: O cabo USB conecta o ESP32 ao PC via `/dev/ttyACM0` (porta USB-Serial/JTAG CDC nativa). Aqui realizamos a gravação do firmware, calibração e captura dos logs de auto-teste.
2. **Fase 2 (Integração e Benchmarks Físicos com Cora Z7)**: O cabo USB é conectado à Cora Z7 (para carregamento do bitstream, execução do firmware PS e captura de dados pelo console serial / ARM PMU). O ESP32 passará a ser alimentado de forma autônoma na bancada (via conector de alimentação ou fonte externa), **sem conexão serial ativa com o computador**.

Para garantir observabilidade e controle total durante os ensaios das Fases 5 e 6 sem depender do PC, o firmware do ESP32 precisa de uma interface de usuário (UI) autônoma e determinística:
- **Botões de Controle**:
  - `BTN_TRIGGER` (GPIO 4): Dispara uma rajada (burst) de injeção de pacotes SPI com base no perfil ativo.
  - `BTN_SELECT` (GPIO 16): Cicla entre os 3 perfis de dados da Matriz de Testes (`64 B Alta Redundância`, `1 KB Pseudoaleatório`, `64 KB Telemetria`).
- **Sinalização Visual por LEDs**:
  - `LED_READY` (GPIO 2, LED Onboard): Pulso lento (1 Hz) indicando firmware operacional e pronto para disparo.
  - `LED_TX` (GPIO 21): Aceso durante a montagem e transmissão de quadros SPI; desliga ao término.
  - `LED_STATUS` (GPIO 22): Código de piscadas curtas indicando o perfil ativo selecionado (1 blink = 64B, 2 blinks = 1KB, 3 blinks = 64KB AES, 4 blinks = 64KB ChaCha, 5 blinks = Sequência Completa), ou aceso fixo em caso de falha crítica.

---

## 2. Arquitetura Modular (Padrão `weather_system_esp`)

Seguindo as boas práticas do repositório de referência (`https://github.com/luishrmc/weather_system_esp`), o código é estruturado de forma desacoplada com tarefas FreeRTOS, filas de eventos (`QueueHandle_t`) e zero alocação dinâmica no laço quente:

```text
esp32/
├── CMakeLists.txt
├── sdkconfig.defaults
├── components/
│   └── ui_controller/
│       ├── CMakeLists.txt
│       ├── ui_controller.h
│       └── ui_controller.c    # Drivers de GPIO, debounce e FSM visual dos LEDs
└── main/
    ├── CMakeLists.txt
    ├── spi_injector_master.h  # Driver SPI Master DMA Mode 0
    ├── spi_injector_master.c
    ├── main.h
    └── main.c                 # Orquestrador FreeRTOS e rotina de auto-teste
```

---

## 3. Critérios de Aceitação (DoD)

1. **Compilação Limpa no ESP-IDF v6.1**:
   - `idf.py build` executa sem erros ou warnings com zero alocação dinâmica nos laços de transmissão.
2. **Auto-Teste On-Target via `/dev/ttyACM0`**:
   - Gravação bem-sucedida via `esptool` / `idf.py flash`.
   - Execução determinística do auto-teste de hardware:
     - Teste dos pinos de GPIO de botões e transição de estados dos LEDs.
     - Geração estática dos 3 vetores de payload (`s_buf_64b`, `s_buf_1kb`, `s_buf_64kb`).
     - Validação matemática do CRC-16-CCITT (0x1021) contra os vetores de ouro do PS/PL.
     - Simulação de transmissão SPI em modo dry-run com medição precisa de tempo (`esp_timer_get_time()`).
3. **Persistência de Evidências**:
   - Registro completo da saída do console do ESP32 salvo em `out/esp32_selftest.log`.
   - Sincronização do plano via `plan-sync.py` e atualização da memória técnica em `utils/memory/`.
