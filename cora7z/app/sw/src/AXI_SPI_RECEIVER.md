# Módulo de Software: axi_spi_receiver (Driver de Recepção SPI)
## Ingestão de Quadros de Telemetria sobre AXI Quad SPI (Bare-Metal C11)

Os arquivos [`axi_spi_receiver.c`](axi_spi_receiver.c) e [`axi_spi_receiver.h`](axi_spi_receiver.h) implementam o driver responsável pela recepção, alinhamento de memória e validação criptográfica/estrutural dos pacotes enviados pelo ESP32 via barramento SPI.

---

## 1. Visão Geral e Responsabilidades

1. **Drenagem da FIFO de Hardware:** Lê palavras da FIFO de 256 bytes do núcleo `axi_quad_spi_0` (`0x41E00000`) operando em modo escravo.
2. **Sincronização de Preâmbulo:** Detecta a sequência inicial constante `0xA55A`.
3. **Validação de Integridade por CRC-16:** Calcula o CRC-16 CCITT sobre o cabeçalho e a carga útil, comparando com o valor transmitido.
4. **Verificação de Fim de Quadro:** Confirma a presença do byte delimitador de encerramento `0x5A`.
5. **Estatísticas de Enlace:** Contabiliza quadros válidos, erros de CRC e erros de enquadramento para exibição no console UART.

---

## 2. Assinatura das Funções Principais

```c
#include "axi_spi_receiver.h"

// Inicializa o periférico AXI Quad SPI na lógica programável em modo escravo
void axi_spi_receiver_init(void);

// Aguarda e realiza a leitura de um quadro completo de telemetria
int axi_spi_receiver_poll_frame(spi_telemetry_frame_t *frame_out, uint32_t timeout_cycles);

// Retorna as estatísticas acumuladas do enlace SPI
void axi_spi_receiver_get_stats(uint32_t *valid_cnt, uint32_t *crc_err_cnt, uint32_t *frame_err_cnt);
```

---

## 3. Resolução de Timeout e Tratamento de Fluxos Densos

Durante a auditoria adversarial do sistema (revisão pelo `technical-critic-agent`), foi identificado e corrigido um comportamento crítico:
* **Problema:** O temporizador de timeout acumulava ciclos entre a leitura de múltiplos bytes, abortando prematuramente quadros longos de 1024 bytes.
* **Correção:** A cada byte lido com sucesso da FIFO de recepção do periférico, o contador de timeout é explicitamente reinicializado para zero (`cycles = 0`), garantindo recepção estável de quadros de 64, 256, 512 e 1024 bytes sem interrupções espúrias.
