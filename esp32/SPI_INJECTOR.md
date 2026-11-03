# Módulo ESP32: spi_injector_master (Injetor de Telemetria SPI)
## Firmware de Transmissão Autônoma para ESP32-WROOM (ESP-IDF v6.1 @ 240 MHz)

Os arquivos [`esp32/main/spi_injector_master.c`](main/spi_injector_master.c) e [`esp32/main/spi_injector_master.h`](main/spi_injector_master.h) contêm a implementação do transmissor mestre de telemetria operando no microcontrolador ESP32-WROOM.

---

## 1. Visão Geral e Responsabilidades

O módulo funciona como uma bancada de testes autônoma:
* **Geração de Cargas Sintéticas:** Alterna ciclicamente entre quadros de **64 B, 256 B, 512 B e 1024 B**, preenchidos com leituras sintéticas de sensores (temperatura, vibração, tensão e status).
* **Enlace SPI Master:** Configura o barramento VSPI/HSPI no **Modo 0** com relógio de até **25 MHz**.
* **Cálculo Dinâmico de Comprimento e CRC:** Determina dinamicamente o número exato de bits da transação como `(8 + len + 3) * 8` e insere o CRC-16 CCITT no offset correto.
* **Gatilho Autônomo por Interrupção de Hardware:** Monitora o pino **GPIO 32** com interrupção externa na borda de descida, aguardando o pulso de 30 ms emitido pelo pino PMOD JA1 da Cora Z7 para disparar novas rajadas de dados.

---

## 2. Pinagem Física de Conexão com a Cora Z7

| Sinal SPI | Pino ESP32 | Pino Cora Z7 (Header J7 / PMOD) | Descrição |
| :--- | :---: | :---: | :--- |
| **SCLK** | **GPIO 18** | **Header J7.3 (Pino H15)** | Relógio de sincronismo do barramento |
| **MOSI** | **GPIO 23** | **Header J7.4 (Pino T12)** | Linha de dados: Mestre (ESP32) $\to$ Escravo (Cora Z7) |
| **MISO** | **GPIO 19** | **Header J7.1 (Pino W15)** | Linha de retorno: Escravo (Cora Z7) $\to$ Mestre (ESP32) |
| **SS_N** | **GPIO 5** | **Header J7.5 (Pino F16)** | Seleção de escravo (ativo em nível baixo) |
| **TRIGGER** | **GPIO 32** | **PMOD JA1 (Pino Y18)** | Sinal de disparo emitido pela CPU da Cora Z7 |
| **GND** | **GND** | **Header J7.6 (GND)** | Referência comum de aterramento |

---

## 3. Estruturação Dinâmica do Quadro no Código

```c
// Montagem do quadro de telemetria no firmware do ESP32
void spi_injector_build_frame(uint8_t *buffer, uint32_t seq_id, uint16_t payload_len) {
    // 1. Preâmbulo de sincronismo (0xA55A)
    buffer[0] = 0xA5;
    buffer[1] = 0x5A;
    
    // 2. Número monotônico de sequência (32 bits, little-endian)
    memcpy(&buffer[2], &seq_id, 4);
    
    // 3. Comprimento da carga útil (16 bits)
    memcpy(&buffer[6], &payload_len, 2);
    
    // 4. Preenchimento de alinhamento para palavras de 32 bits (offset 8)
    buffer[8] = 0x00;
    buffer[9] = 0x00;
    
    // 5. Carga útil de dados sintéticos (offset 10)
    for (uint16_t i = 0; i < payload_len; i++) {
        buffer[10 + i] = (uint8_t)((seq_id + i) & 0xFF);
    }
    
    // 6. Cálculo do CRC-16 CCITT sobre cabeçalho e carga útil
    uint16_t crc = calculate_crc16(buffer, 10 + payload_len);
    buffer[10 + payload_len]     = (uint8_t)(crc & 0xFF);
    buffer[10 + payload_len + 1] = (uint8_t)((crc >> 8) & 0xFF);
    
    // 7. Delimitador de encerramento do pacote
    buffer[10 + payload_len + 2] = 0x5A;
}
```
