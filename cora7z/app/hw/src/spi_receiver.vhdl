--------------------------------------------------------------------------------
-- Project: High-Performance PS/PL Acceleration on Zynq-7010
-- File:    spi_receiver.vhdl
-- Entity:  spi_receiver
-- Author:  Antigravity AI / Luis H. R. M. C.
-- Standard: VHDL-2008 (IEEE 1076-2008)
--
-- Description:
--   Synchronous SPI Slave Receiver with Clock Domain Crossing (CDC) synchronizers,
--   edge-detection sampling, and an internal synchronous FIFO buffer providing an
--   AXI4-Stream Master output interface.
--
-- Operational Parameters:
--   - Mode: SPI Mode 0 (CPOL=0, CPHA=0)
--   - SCLK Frequency: Up to 25 MHz (sampled by clk_i @ 100 MHz)
--   - Framing: Active-low chip select (spi_cs_n_i). Each deassertion marks packet end.
--   - FIFO: Configurable depth ring-buffer absorbing AXI4-Stream handshaking latency.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_receiver is
  generic (
    g_fifo_depth : positive := 32
  );
  port (
    -- System Clock and Reset
    clk_i           : in  std_logic;
    rst_n_i         : in  std_logic;

    -- External Physical SPI Interface (Asynchronous Pins from ESP32)
    spi_sclk_i      : in  std_logic;
    spi_cs_n_i      : in  std_logic;
    spi_mosi_i      : in  std_logic;
    spi_miso_o      : out std_logic;

    -- Downstream AXI4-Stream Master Interface
    m_axis_tdata_o  : out std_logic_vector(7 downto 0);
    m_axis_tvalid_o : out std_logic;
    m_axis_tready_i : in  std_logic;
    m_axis_tlast_o  : out std_logic;

    -- Status and Telemetry Registers
    rx_byte_count_o : out unsigned(15 downto 0);
    frame_active_o  : out std_logic;
    overflow_o      : out std_logic
  );
end entity spi_receiver;

architecture rtl of spi_receiver is

  -- CDC Double-Register Synchronizers
  signal sclk_sync_r   : std_logic_vector(2 downto 0) := (others => '0');
  signal cs_n_sync_r   : std_logic_vector(2 downto 0) := (others => '1');
  signal mosi_sync_r   : std_logic_vector(2 downto 0) := (others => '0');

  -- Edge Detection
  signal sclk_rising_s : std_logic;
  signal cs_assert_s   : std_logic;
  signal cs_deassert_s : std_logic;

  -- Deserializer Signals
  signal rx_shreg_r    : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_cnt_r     : unsigned(2 downto 0) := (others => '0');
  signal rx_byte_s     : std_logic_vector(7 downto 0);
  signal rx_valid_s    : std_logic;
  signal byte_count_r  : unsigned(15 downto 0) := (others => '0');
  signal overflow_r    : std_logic := '0';

  -- Internal FIFO Storage
  type fifo_data_t is array (0 to g_fifo_depth - 1) of std_logic_vector(7 downto 0);
  type fifo_last_t is array (0 to g_fifo_depth - 1) of std_logic;

  signal fifo_data_mem_r : fifo_data_t := (others => (others => '0'));
  signal fifo_last_mem_r : fifo_last_t := (others => '0');

  signal wr_ptr_r        : natural range 0 to g_fifo_depth - 1 := 0;
  signal rd_ptr_r        : natural range 0 to g_fifo_depth - 1 := 0;
  signal fifo_count_r    : natural range 0 to g_fifo_depth := 0;

  -- Pending frame completion tracking
  signal frame_ended_r   : std_logic := '0';

begin

  ------------------------------------------------------------------------------
  -- 1. Clock Domain Crossing (CDC) Double-Register Synchronizers
  ------------------------------------------------------------------------------
  p_cdc_sync : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        sclk_sync_r <= (others => '0');
        cs_n_sync_r <= (others => '1');
        mosi_sync_r <= (others => '0');
      else
        sclk_sync_r <= sclk_sync_r(1 downto 0) & spi_sclk_i;
        cs_n_sync_r <= cs_n_sync_r(1 downto 0) & spi_cs_n_i;
        mosi_sync_r <= mosi_sync_r(1 downto 0) & spi_mosi_i;
      end if;
    end if;
  end process p_cdc_sync;

  -- Detect rising edge on synchronized SCLK (sampled at 100 MHz)
  sclk_rising_s <= '1' when (sclk_sync_r(2) = '0' and sclk_sync_r(1) = '1') else '0';

  -- Detect assertion and deassertion of active-low Chip Select
  cs_assert_s   <= '1' when (cs_n_sync_r(2) = '1' and cs_n_sync_r(1) = '0') else '0';
  cs_deassert_s <= '1' when (cs_n_sync_r(2) = '0' and cs_n_sync_r(1) = '1') else '0';

  -- Status outputs
  frame_active_o  <= not cs_n_sync_r(1);
  rx_byte_count_o <= byte_count_r;
  overflow_o      <= overflow_r;

  -- Simple loopback for SPI MISO (echoes synchronized MOSI or fixed handshake)
  spi_miso_o      <= mosi_sync_r(2);

  ------------------------------------------------------------------------------
  -- 2. SPI Serial-to-Parallel Deserializer (Mode 0: sample on rising edge)
  ------------------------------------------------------------------------------
  p_deserializer : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        rx_shreg_r   <= (others => '0');
        bit_cnt_r    <= (others => '0');
        rx_valid_s   <= '0';
        rx_byte_s    <= (others => '0');
        byte_count_r <= (others => '0');
      else
        rx_valid_s <= '0';

        if cs_assert_s = '1' then
          -- Reset bit counter and frame byte counter when a new frame begins
          bit_cnt_r    <= (others => '0');
          rx_shreg_r   <= (others => '0');
          byte_count_r <= (others => '0');
        elsif cs_n_sync_r(1) = '0' then
          -- Active transaction: sample MOSI on rising edge of SCLK
          if sclk_rising_s = '1' then
            rx_shreg_r <= rx_shreg_r(6 downto 0) & mosi_sync_r(1);

            if bit_cnt_r = 7 then
              bit_cnt_r    <= (others => '0');
              rx_byte_s    <= rx_shreg_r(6 downto 0) & mosi_sync_r(1);
              rx_valid_s   <= '1';
              byte_count_r <= byte_count_r + 1;
            else
              bit_cnt_r    <= bit_cnt_r + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process p_deserializer;

  ------------------------------------------------------------------------------
  -- 3. Synchronous FIFO Storage and AXI4-Stream Master Driver
  ------------------------------------------------------------------------------
  p_fifo_ctrl : process(clk_i)
    variable v_write : boolean;
    variable v_read  : boolean;
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        wr_ptr_r      <= 0;
        rd_ptr_r      <= 0;
        fifo_count_r  <= 0;
        overflow_r    <= '0';
        frame_ended_r <= '0';
      else
        v_write := false;
        v_read  := false;

        -- Latch frame ending signal
        if cs_deassert_s = '1' then
          frame_ended_r <= '1';
        end if;

        -- Determine if read is granted on AXI4-Stream
        if (fifo_count_r > 0) and (m_axis_tready_i = '1') then
          v_read := true;
        end if;

        -- Determine if write to FIFO occurs
        if rx_valid_s = '1' then
          if fifo_count_r < g_fifo_depth then
            v_write := true;
            fifo_data_mem_r(wr_ptr_r) <= rx_byte_s;
            fifo_last_mem_r(wr_ptr_r) <= '0';
          else
            overflow_r <= '1';
          end if;
        end if;

        -- If frame ended, tag the most recently queued byte with tlast
        if (frame_ended_r = '1' or cs_deassert_s = '1') and (fifo_count_r > 0) then
          if wr_ptr_r = 0 then
            fifo_last_mem_r(g_fifo_depth - 1) <= '1';
          else
            fifo_last_mem_r(wr_ptr_r - 1) <= '1';
          end if;
          frame_ended_r <= '0';
        end if;

        -- Update Write Pointer
        if v_write then
          if wr_ptr_r = g_fifo_depth - 1 then
            wr_ptr_r <= 0;
          else
            wr_ptr_r <= wr_ptr_r + 1;
          end if;
        end if;

        -- Update Read Pointer
        if v_read then
          if rd_ptr_r = g_fifo_depth - 1 then
            rd_ptr_r <= 0;
          else
            rd_ptr_r <= rd_ptr_r + 1;
          end if;
        end if;

        -- Update FIFO Count
        if v_write and not v_read then
          fifo_count_r <= fifo_count_r + 1;
        elsif v_read and not v_write then
          fifo_count_r <= fifo_count_r - 1;
        end if;

      end if;
    end if;
  end process p_fifo_ctrl;

  -- AXI4-Stream Master Output Driving
  m_axis_tvalid_o <= '1' when (fifo_count_r > 0) else '0';
  m_axis_tdata_o  <= fifo_data_mem_r(rd_ptr_r);
  m_axis_tlast_o  <= fifo_last_mem_r(rd_ptr_r);

end architecture rtl;
