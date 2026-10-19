# Task 4.2: Implementação de Referência em C/C++ no Cortex-A9 (Cenário 1: PS Puro)

## 1. Resumo da Tarefa e Objetivos

Nesta etapa, implementamos a suíte modular de software de referência em C11 para o processador ARM Cortex-A9 (Core 0 @ 667 MHz) da Digilent Cora Z7-10:
- **Padrões de Engenharia Embarcada**:
  - Padrão C11 (`-std=c11`), compatível com MISRA-C para sistemas de tempo real críticos.
  - Zero alocação dinâmica de memória (`malloc`, `calloc`, `realloc`, `free` estritamente proibidos; buffers estáticos ou alocados pelo chamador).
  - Tipos de largura fixa exclusivos (`<stdint.h>`, `<stddef.h>`).
  - Arquitetura desacoplada: bibliotecas algorítmicas de compressão e criptografia não possuem dependência de headers proprietários da Xilinx, permitindo compilação e teste unitário tanto no hospedeiro (x86_64 GCC) quanto no alvo embarcado (ARM GCC).
- **Módulos Algorítmicos**:
  - `rle.h` / `rle.c`: Run-Length Encoding / Decoding sem perdas (tokens de 2 bytes: `[run_len, symbol]`).
  - `lz4_simple.h` / `lz4_simple.c`: Compressor e descompressor de blocos compatível com LZ4 utilizando tabela hash determinística de 2048 entradas.
  - `aes_ctr.h` / `aes_ctr.c`: Cifragem e decifragem AES-128 em modo CTR (NIST SP 800-38A) com expansão de chave e incremento de contador de 32 bits Big-Endian.
  - `chacha20.h` / `chacha20.c`: Cifra de fluxo ChaCha20 com 20 rodadas (IETF RFC 8439) utilizando chave de 256 bits, nonce de 96 bits e contador de blocos de 32 bits.
- **Harness de Benchmark e Perfilamento PMU (`benchmark_ps.h` / `benchmark_ps.c`)**:
  - Mapeamento estrito das 4 cargas do Cenário 1 (PS puro) da `Matriz_de_Testes_e_Métricas.csv`:
    1. RLE (64 B, Alta Redundância).
    2. LZ4 (1 KB, Pseudoaleatório via gerador determinístico Xorshift32).
    3. AES-128-CTR (64 KB, Telemetria Estruturada).
    4. ChaCha20 (64 B Alta Redundância e 64 KB Telemetria).
  - Instrumentação de precisão por ciclo via ARM Performance Monitor Unit (PMU / CP15 `PMCCNTR`).
  - Execução estatística com 10 repetições (`BENCHMARK_RUNS = 10`), computando média ($\mu$) e desvio padrão ($\sigma$) dos ciclos, latência calculada e vazão (throughput em KB/s e MB/s).
- **Integração com o Firmware Principal (`main.c`)**:
  - Execução do benchmark do Cenário 1 após as rotinas de calibração do PMU e auditoria MMIO da PL.

---

## 2. Estrutura de Arquivos

```text
cora7z/app/sw/
├── src/
│   ├── rle.h / rle.c                     # Compressão/Descompressão RLE
│   ├── lz4_simple.h / lz4_simple.c       # Compressão/Descompressão LZ4
│   ├── aes_ctr.h / aes_ctr.c             # Criptografia AES-128-CTR
│   ├── chacha20.h / chacha20.c           # Cifra de Fluxo ChaCha20
│   ├── benchmark_ps.h / benchmark_ps.c   # Harness de benchmark e PMU
│   └── main.c                            # Ponto de entrada do firmware
└── test/
    └── test_software_algorithms.c        # Suíte de teste host com vetores de ouro
```

---

## 3. Critérios de Aceitação

1. **Host Golden Vector Verification**:
   - `gcc -Wall -Wextra -Werror -std=c11 -O2 -I cora7z/app/sw/src cora7z/app/sw/test/test_software_algorithms.c ... -o out/test_software_algorithms` compila limpo e passa 100% dos testes para todos os quatro algoritmos contra vetores de ouro (NIST SP 800-38A e RFC 8439).
2. **Inner Loop Static Verification**:
   - `TASK_ID=4.2 bash .agents/hooks/c-lint.sh` retorna PASS com 0 violações de alocação dinâmica e sintaxe limpa.
3. **Vitis Unified Build Gate**:
   - `TASK_ID=4.2 bash .agents/hooks/vitis-gate.sh` compila com sucesso o executável ELF standalone `cora7z_firmware.elf` para Cortex-A9 via toolchain ARM GCC.
4. **Governança e Rastreabilidade**:
   - Sincronização do plano via `plan-sync.py set 4.2 "Concluída"`.
