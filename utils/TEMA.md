# Resumo

Sistemas embarcados em nós de borda frequentemente transmitem telemetria por enlaces de baixa largura de banda, o que exige compressão e criptografia prévia dos dados para garantir eficiência e confidencialidade. Contudo, executar essas duas rotinas pesadas de forma sequencial na CPU sobrecarrega o processador principal, eleva a latência e reduz os ciclos disponíveis para tarefas críticas de controle. Este trabalho investiga o particionamento dessas etapas entre o sistema de processamento (PS, ARM Cortex-A9) e a lógica programável (PL, FPGA Artix-7) utilizando o SoC Zynq-7010 na placa Digilent Cora Z7-10. Para simular um fluxo operacional contínuo, um microcontrolador ESP32 injeta pacotes de dados sintéticos na placa por meio de uma interface SPI rápida. A avaliação compara três configurações operacionais: execução exclusiva em software no PS, pipeline dedicado inteiramente em hardware na PL e uma arquitetura hibrida de co-projeto. Os experimentos mensuram a latência de ponta a ponta, a ocupação de recursos da FPGA e a sobrecarga de transferência no barramento AXI, determinando a partir de qual volume de dados a aceleração em hardware supera o custo de comunicação entre os dominios do chip.

---

# Plano de Desenvolvimento da Aplicação

## 1. Objetivo e Requisitos do Projeto

O objetivo do projeto é implementar, comparar e caracterizar o desempenho de algoritmos de compressão e criptografia executados de forma autônoma no PS, de forma isolada na PL e por meio de uma arquitetura híbrida no SoC Zynq-7010.

Requisitos funcionais e técnicos:
* Interface serial sincrona escrava (SPI) com suporte a taxas de até 25 MHz para recepção dos pacotes de teste.
* Implementação dos algoritmos selecionados em código C/C++ bare-metal para execução no processador ARM Cortex-A9.
* Implementação dos mesmos algoritmos descritos puramente em VHDL com máquinas de estado e registradores de dados na FPGA.
* Barramento de interconexão AXI4 para comunicação entre a memória DDR3, o processador e os blocos de aceleração da PL.
* Instrumentação de contagem de ciclos de clock através do ARM Performance Monitor Unit (PMU) e de contadores temporais em hardware na PL.
* Geração de arquivos-fonte em VHDL acompanhados de bancos de teste funcionais (`tb_*.vhd`) para simulação de cada bloco lógico.
* Geração do código-fonte em C/C++ para o PS e de um diagrama de blocos em formato de imagem que documente os módulos do sistema.

## 2. Propostas de Solução

* **Proposta 1 (Solução baseada em software no PS):** Todas as etapas de recepção de dados, compressão, criptografia e despacho de rede são processadas integralmente pelo núcleo ARM. Embora simplifique o desenvolvimento ao dispensar a síntese de lógica na FPGA, a abordagem satura o processador e cria gargalos em taxas elevadas de entrada.
* **Proposta 2 (Plataforma comparativa multi-cenário PS/PL e híbrida, selecionada):** O sistema implementa o fluxo completo tanto no processador quanto na lógica programável, integrando também um arranjo híbrido no qual o PS controla o fluxo de dados e a PL processa os cálculos matemáticos intensivos.

## 3. Metodologia dos Testes e Algoritmos Avaliados

A bancada avalia o comportamento de ponta a ponta nas etapas de recepção, compressão, cifragem e transmissão por meio de três cenários de execução:

1. **Cenário PS Autônomo (Software puro):** O processador ARM recebe os bytes do periférico SPI, armazena o bloco bruto na memória, executa o algoritmo de compressão em software, criptografa a carga resultante e transmite os pacotes.
2. **Cenário PL Autônomo (Hardware puro):** Uma máquina de estados em VHDL recebe os dados da interface SPI externa, alimenta um pipeline sincrono que comprime o fluxo em tempo real, encaminha os blocos ao núcleo criptográfico em hardware e despacha os dados cifrados sem intervenção do processador.
3. **Cenário Híbrido (Co-projeto com canal AXI):** O processador gerencia os descritores de transferência e os buffers na memória DDR3, despachando blocos brutos para os aceleradores na PL via barramento AXI. A lógica programável executa as transformações e devolve o pacote finalizado para transmissão.

### Algoritmos Avaliados

* **Compressão:**
  * *Run-Length Encoding (RLE):* algoritmo de baixa complexidade lógica e consumo reduzido de área em silicio. Avalia o desempenho em fluxos com sequências repetitivas contínuas.
  * *LZ4 (ou LZSS simplificado com janela deslizante):* algoritmo baseado em dicionário que exige o uso de Block RAMs na FPGA para indexação de padrões. Oferece taxas superiores de compressão em dados estruturados e de telemetria textual.
* **Criptografia:**
  * *AES em modo Contador (AES-CTR):* cifra de bloco de alta segurança. O modo CTR transforma o algoritmo em uma cifra de fluxo paralelizável, permitindo preencher pipelines em hardware com tabelas de substituição (S-Box) em BRAM ou lógica combinacional.
  * *ChaCha20:* cifra de fluxo baseada em operações simples de adição, rotação e ou-exclusivo (ARX). Opera com elevada eficiência nativa em instruções de 32 bits no processador ARM, servindo de contraponto ao AES.

### Tipos de Cargas de Teste

O microcontrolador ESP32 gera três perfis sintéticos de dados transmitidos via SPI em blocos de 64 bytes até 64 kilobytes:
* **Dados com alta redundância:** sequências periódicas e repetitivas para medição do melhor caso de taxa de compressão.
* **Dados pseudoaleatórios de alta entropia:** blocos sem padrões óbvios para testar a sobrecarga dos algoritmos no pior caso de compressão.
* **Registros sintéticos de telemetria:** dados estruturados com carimbos de tempo e leituras numéricas graduais, simulando condições industriais reais.

### Resultados Esperados

* Para blocos intermediários e grandes (acima de 4 kilobytes), a PL autônoma e a arquitetura hibrida devem superar o software em taxa de transferência por ordens de grandeza, mantendo a latência estável a cada byte recebido.
* O algoritmo ChaCha20 deve apresentar desempenho competitivo no processador ARM devido à compatibilidade da estrutura ARX com o conjunto de instruções do Cortex-A9, enquanto o AES em modo CTR deve atingir vazão superior quando instanciado no pipeline da lógica programável.

## 4. Materiais e Custos

* Placa Digilent Cora Z7-10 (SoC Zynq-7010 com dual-core Cortex-A9 e FPGA Artix-7): disponível no laboratório.
* Placa de desenvolvimento ESP32 para injeção de dados sintéticos via SPI: do aluno.
* Jumpers de conexão e protoboard para montagem do barramento físico: do aluno.
* Cabo de comunicação e alimentação Micro-USB: do aluno.

## 5. Ferramentas de Projeto, Gestão e Versionamento

O controle de versão de todo o projeto será realizado em um repositório aberto hospedado no GitHub. O repositório conterá um documento README detalhado descrevendo os objetivos, os diagramas de blocos, a especificação das interfaces de hardware e os procedimentos para replicação dos testes em bancada. O fluxo de desenvolvimento manterá pastas estruturadas para arquivos VHDL, bancos de teste, códigos em C/C++ e scripts de apoio.