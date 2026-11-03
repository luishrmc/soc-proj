# Módulo de Software: lzss_sw (Compressão LZSS / Heatshrink em C11)
## Referência em Software e Descompressor para ARM Cortex-A9 @ 667 MHz

Os arquivos [`lzss_sw.c`](lzss_sw.c) e [`lzss_sw.h`](lzss_sw.h) implementam o algoritmo de compressão e descompressão LZSS (Lempel-Ziv-Storer-Szymanski) em linguagem C11 bare-metal, servindo como modelo de ouro funcional (*golden model*) e mecanismo de descompressão para validação *round-trip*.

---

## 1. Visão Geral e Propósito no Sistema

O módulo tem três finalidades essenciais no projeto:
1. **Linha de Base de Software (Cenário 1 e Cenário 3):** Fornece a rotina de compressão executada puramente pelo processador Cortex-A9 a 667 MHz.
2. **Validação Cruzada de Fidelidade:** Permite comprovar que a saída comprimida pelo acelerador em hardware (`lzss_accel.vhdl`) é descompactada com perfeição pelo software em C, garantindo interoperabilidade entre silício e software.
3. **Avaliação Microarquitetural (Risco R9):** Demonstra como algoritmos de busca em memória beneficiam-se da memória cache L1 de dados (32 KB) e predição de desvios da CPU quando comparados à busca linear sequencial em FPGA a 100 MHz.

---

## 2. Assinatura das Funções Principais

```c
#include "lzss_sw.h"

// Comprime um bloco de dados brutos utilizando janela deslizante Heatshrink
int lzss_sw_compress(const uint8_t *in_buf, uint32_t in_len, uint8_t *out_buf, uint32_t *out_len);

// Descomprime um fluxo codificado restaurando a sequência de bytes original
int lzss_sw_decompress(const uint8_t *in_buf, uint32_t in_len, uint8_t *out_buf, uint32_t *out_len);
```

### Parâmetros e Tipos
* `in_buf`: Ponteiro constante para o buffer de dados de entrada na memória DDR3.
* `in_len`: Comprimento em bytes do bloco a ser processado (até 1024 bytes).
* `out_buf`: Ponteiro para o buffer de saída onde o resultado será armazenado.
* `out_len`: Ponteiro de retorno preenchido com a contagem exata de bytes gerados.
* **Retorno:** Código de status inteiro (`0` para sucesso, negativo para falha de limites).

---

## 3. Mecânica do Algoritmo e Empacotamento de Bits

O codificador percorre o fluxo de entrada mantendo uma janela circular de histórico de 256 bytes ($W=8$) e um buffer de casamento de 16 bytes ($L=4$):

```text
Fluxo de Bits Gerado:
[Tag Bit = 1] -> [Byte Literal de 8 bits]
[Tag Bit = 0] -> [Deslocamento: 8 bits] -> [Comprimento - 2: 4 bits]
```

* **Bit de Tag `'1'` (Literal):** Indica que não foi localizado casamento $\ge 2$ bytes no histórico. O byte original é emitido diretamente.
* **Bit de Tag `'0'` (Back-Reference):** Sinaliza uma tupla de repetição. O deslocamento no dicionário indica a distância no passado onde a sequência se repetiu, e o campo de comprimento (codificado em 4 bits para representar comprimentos de 2 a 16) instrui o descompressor a duplicar os bytes correspondentes.

---

## 4. Comportamento em Cache e Comparativo com a FPGA

Durante os testes na Cora Z7, o algoritmo em C demonstrou alta eficiência no Cortex-A9:
* O buffer de trabalho de 256 bytes e os ponteiros de busca residem inteiramente na **cache L1 de dados de 32 KB**, resultando em acessos com latência de **1 único ciclo de CPU** a 667 MHz.
* As instruções de salto e laço de busca beneficiam-se do previsor dinâmico de desvios do Cortex-A9.
* Essa característica microarquitetural explica por que a compressão em C a 667 MHz supera a FSM sequencial da FPGA a 100 MHz, justificando a escolha do **Cenário 3 (SW LZSS + PL AES)** como a configuração de maior vazão do sistema.
