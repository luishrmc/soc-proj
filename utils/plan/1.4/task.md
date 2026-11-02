# Task 1.4: Definição dos Vetores de Ouro e Estrutura dos Quadros de Telemetria

## 1. Resumo da Tarefa e Objetivos

Nesta etapa (última atividade da Fase 1 - Planejamento e Sincronização), estabelecemos os vetores de ouro e a especificação dos quadros de dados sintéticos de telemetria que nortearão toda a verificação funcional do projeto nas Fases 2 (RTL/Simulação), 3 (Integração BD), 4 (Firmware PS) e 5 (Validação Ponta a Ponta):

- **Estrutura dos Quadros de Telemetria Sintética**:
  - Dimensões padronizadas: 256 B, 512 B e 1024 B (1 KB).
  - Conteúdo realista de telemetria de IoT: registros com carimbo de tempo UNIX, identificador de sensor (ASCII), variáveis contínuas (temperatura, pressão, vibração), e flags de alarme.
  - O perfil combina porções repetitivas (ideais para compressão LZSS/Heatshrink) com campos dinâmicos.

- **Modelo de Ouro de Compressão (LZSS / Heatshrink)**:
  - Algoritmo baseado em janela deslizante com dicionário circular.
  - Parâmetros canônicos: Janela $2^W = 256$ bytes ($W=8$), Lookahead $2^L = 16$ bytes ($L=4$).
  - Formato do bitstream: bit de tag (`1` = byte literal de 8 bits; `0` = back-reference codificada em offset e comprimento).
  - Golden vectors para validação cruzada entre modelo C de referência e testbench VHDL `tb_lzss_accel.vhdl`.

- **Modelo de Ouro de Criptografia (AES-128-CTR)**:
  - Cifra simétrica em modo Contador conforme NIST FIPS-197 e NIST SP 800-38A (Seção F.5.1).
  - Chave de 128 bits e IV/Nonce de 96 bits com contador de 32 bits iniciado em `0x00000001`.
  - Keystream gerado por $E_K(IV \parallel Ctr)$ com operação XOR bit-a-bit sobre o fluxo de dados comprimidos.

---

## 2. Critérios de Aceitação

1. **Definição dos Pacotes de Teste**:
   - Criação de payloads sintéticos reproduzíveis de 256 B, 512 B e 1024 B.
2. **Vetores NIST SP 800-38A Validados**:
   - Chave, IV, contadores e blocos cifrados correspondentes documentados e prontos para uso em VUnit e firmware bare-metal.
3. **Vetores Heatshrink Validados**:
   - Strings de teste de referência com saídas comprimidas documentadas bit-a-bit.
4. **Alinhamento Arquitetural**:
   - Garantir ordenação de bytes (endianness) e delimitação de final de bloco sem ambiguidade.
