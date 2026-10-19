# Task 2.1: Receptor SPI Escravo com Sincronização CDC e Buffer FIFO/BRAM

## 1. Resumo da Tarefa e Objetivos

Nesta etapa, implementamos o módulo de ingresso de dados da FPGA na lógica programável (PL):
- **Módulo RTL (`cora7z/app/hw/src/spi_receiver.vhdl`)**:
  - Receptor SPI em modo escravo (Mode 0: CPOL=0, CPHA=0) com suporte a taxas de até 25 MHz.
  - Sincronização estrita de domínio de clock (CDC): todos os sinais externos assíncronos (`spi_sclk_i`, `spi_cs_n_i`, `spi_mosi_i`) passam por sincronizadores de 2 estágios DFF operando no clock do sistema (`clk_i` @ 100 MHz).
  - Detector de bordas para amostragem determinística no meio do bit de dados.
  - Conversor serial-paralelo (deserializador) de 8 bits (MSB first).
  - Buffer FIFO síncrono interno para amortecimento de fluxo antes do despacho.
  - Interface de saída AXI4-Stream Master (`m_axis_tdata`, `m_axis_tvalid`, `m_axis_tready`, `m_axis_tlast`) para conexão direta com os aceleradores (RLE, LZ4) ou AXI DMA.
  - Sinais de status: contador de bytes recebidos (`rx_byte_count_o`), indicador de frame ativo (`frame_active_o`) e detecção de sobrecarga (`overflow_o`).
- **Banco de Testes VUnit (`cora7z/app/hw/test/tb_spi_receiver.vhdl`)**:
  - Simulação com VUnit e GHDL cobrindo múltiplos cenários: reset, frame nominal a 25 MHz, pacotes com preâmbulo, back-pressure (`tready = '0'`) e múltiplos frames consecutivos.
- **Documentação Teórica e Arquitetural (`docs/SPI_RECEIVER_ARCHITECTURE.md`)**:
  - Explicação completa da teoria de recepção SPI assíncrona, sincronização CDC, cálculo de MTBF para amostragem digital a 100 MHz, máquina de estados e diagramas Mermaid.

---

## 2. Entregáveis Produzidos

1. **Código RTL VHDL-2008**:
   - [`cora7z/app/hw/src/spi_receiver.vhdl`](file:///home/luis/ufmg/soc/proj/cora7z/app/hw/src/spi_receiver.vhdl)
2. **Banco de Testes VUnit**:
   - [`cora7z/app/hw/test/tb_spi_receiver.vhdl`](file:///home/luis/ufmg/soc/proj/cora7z/app/hw/test/tb_spi_receiver.vhdl)
3. **Documentação Arquitetural e Teórica**:
   - [`docs/SPI_RECEIVER_ARCHITECTURE.md`](file:///home/luis/ufmg/soc/proj/docs/SPI_RECEIVER_ARCHITECTURE.md)
4. **Digest Técnico de Módulo**:
   - [`utils/memory/modules/spi_receiver.md`](file:///home/luis/ufmg/soc/proj/utils/memory/modules/spi_receiver.md)

---

## 3. Interfaces do Módulo `spi_receiver`

```vhdl
entity spi_receiver is
  generic (
    g_fifo_depth : positive := 32
  );
  port (
    clk_i           : in  std_logic;                    -- System clock (100 MHz)
    rst_n_i         : in  std_logic;                    -- Active-low synchronous reset
    -- External Physical SPI Interface (asynchronous pins)
    spi_sclk_i      : in  std_logic;                    -- SPI serial clock (up to 25 MHz)
    spi_cs_n_i      : in  std_logic;                    -- SPI chip select (active low)
    spi_mosi_i      : in  std_logic;                    -- SPI Master-Out Slave-In
    spi_miso_o      : out std_logic;                    -- SPI Master-In Slave-Out (loopback/status)
    -- Downstream AXI4-Stream Master Interface
    m_axis_tdata_o  : out std_logic_vector(7 downto 0); -- Received data byte
    m_axis_tvalid_o : out std_logic;                    -- Byte valid strobe
    m_axis_tready_i : in  std_logic;                    -- Downstream backpressure
    m_axis_tlast_o  : out std_logic;                    -- Frame boundary marker
    -- Status and Monitoring
    rx_byte_count_o : out unsigned(15 downto 0);        -- Frame byte count
    frame_active_o  : out std_logic;                    -- Asserted during active SPI frame
    overflow_o      : out std_logic                     -- Asserted if FIFO overflows
  );
end entity spi_receiver;
```

---

## 4. Roteiro de Verificação (Inner & Outer Loops)

1. **Inner Loop**:
   - Linting estático: `TASK_ID=2.1 bash .agents/hooks/vhdl-lint.sh` (zero avisos, sem latches, sem `wait for`).
   - Simulação VUnit: `TASK_ID=2.1 bash .agents/hooks/vhdl-sim-gate.sh spi_receiver` (100% dos testes aprovados).
2. **Outer Loop**:
   - Verificação do isolamento: `python3 .agents/hooks/boundary-guard.py check --agent rtl-agent`.
   - Revisão adversária técnica pelo `technical-critic-agent`.
   - Atualização do digest técnico e avanço no cronograma via `plan-sync.py`.
