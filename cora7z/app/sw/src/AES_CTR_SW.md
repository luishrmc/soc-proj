# Módulo de Software: aes_ctr_sw (Cifragem AES-128-CTR em C11)
## Modelo de Referência NIST SP 800-38A para ARM Cortex-A9 @ 667 MHz

Os arquivos [`aes_ctr_sw.c`](aes_ctr_sw.c) e [`aes_ctr_sw.h`](aes_ctr_sw.h) fornecem a implementação em C11 da cifra simétrica de bloco AES-128 operando no Modo Contador (CTR), servindo como padrão de referência funcional (*golden model*) e como componente de software do Cenário 1 e Cenário 2.

---

## 1. Visão Geral e Propósito no Sistema

O módulo implementa rigorosamente a especificação do **NIST FIPS-197** e **NIST SP 800-38A**:
1. **Linha de Base Criptográfica:** Permite mensurar com precisão o custo computacional imposto à CPU quando ela é obrigada a executar transformações de matriz de Galois, tabelas S-Box e expansão de chaves sequencialmente por software.
2. **Validação de Vetores de Ouro:** Valida bit-a-bit a saída do acelerador de hardware na FPGA (`aes_accel.vhdl`) contra vetores conhecidos do NIST.
3. **Simetria de Cifragem/Decifragem:** No modo CTR, a decifragem é idêntica à cifragem (basta aplicar a mesma chave e o mesmo IV com a operação XOR).

---

## 2. Assinatura das Funções e Interface de Chamada

```c
#include "aes_ctr_sw.h"

// Inicializa o contexto criptográfico com chave de 128 bits e IV
void aes_ctr_sw_init(aes_ctr_ctx_t *ctx, const uint8_t *key, const uint8_t *iv);

// Cifra ou decifra um bloco de texto plano/cifrado de comprimento arbitrário
void aes_ctr_sw_crypt(aes_ctr_ctx_t *ctx, const uint8_t *in, uint8_t *out, uint32_t len);
```

### Estrutura de Contexto (`aes_ctr_ctx_t`)
```c
typedef struct {
    uint32_t round_keys[44]; // 10 rodadas * 4 palavras + 4 palavras chave original
    uint8_t  counter_block[16]; // Vetor IV de 128 bits com contador big-endian
    uint8_t  keystream[16];     // Bloco ativo de keystream para operação XOR
    uint32_t keystream_pos;     // Deslocamento de byte dentro do bloco
} aes_ctr_ctx_t;
```

---

## 3. Custo Computacional na CPU (O Porquê do Offload)

A execução em software puro do AES exige uma extensa quantidade de instruções para cada bloco de 16 bytes:
* 10 chamadas sucessivas à função de rodada, cada uma contendo 16 acessos a tabelas de substituição na memória, permutações de bytes e cálculos aritméticos em $\text{GF}(2^8)$ com a função `xtime`.
* **Custo em Ciclos de Clock:** Um bloco de 1024 bytes (64 blocos AES) consome cerca de **360.000 ciclos de CPU** no Cortex-A9 a 667 MHz (~540 µs).
* **Vantagem do Offload para a PL:** O acelerador de hardware [`aes_accel.vhdl`](../../hw/src/AES_ACCEL.md) executa o mesmo processamento em apenas **829 ciclos de clock a 100 MHz (8,29 µs)**, resultando em um ganho de velocidade de mais de **40 vezes** na etapa de cifragem isolada e **1,56x no pipeline completo de ponta a ponta**.
