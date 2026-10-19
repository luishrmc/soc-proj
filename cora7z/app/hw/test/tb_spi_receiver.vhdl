--------------------------------------------------------------------------------
-- Project: High-Performance PS/PL Acceleration on Zynq-7010
-- File:    tb_spi_receiver.vhdl
-- Entity:  tb_spi_receiver
-- Author:  Antigravity AI / Luis H. R. M. C.
-- Standard: VHDL-2008 (IEEE 1076-2008)
--
-- Description:
--   Self-checking VUnit testbench for spi_receiver.vhdl.
--   Validates:
--     1. Power-on reset behavior and initial state.
--     2. SPI Mode 0 reception of single byte at 25 MHz SCLK.
--     3. Full frame reception with packet preamble and tlast assertion.
--     4. Internal FIFO buffering and downstream AXI4-Stream backpressure.
--     5. FIFO capacity saturation and overflow detection.
--------------------------------------------------------------------------------

library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_receiver is
  generic (runner_cfg : string);
end entity tb_spi_receiver;

architecture tb of tb_spi_receiver is

  constant c_clk_period : time := 10 ns;  -- 100 MHz system clock
  constant c_sclk_semi  : time := 20 ns;  -- 25 MHz SPI SCLK (half-period = 20 ns)

  -- System Clock & Reset
  signal clk_i           : std_logic := '0';
  signal rst_n_i         : std_logic := '0';

  -- SPI Interface
  signal spi_sclk_i      : std_logic := '0';
  signal spi_cs_n_i      : std_logic := '1';
  signal spi_mosi_i      : std_logic := '0';
  signal spi_miso_o      : std_logic;

  -- AXI4-Stream Interface
  signal m_axis_tdata_o  : std_logic_vector(7 downto 0);
  signal m_axis_tvalid_o : std_logic;
  signal m_axis_tready_i : std_logic := '1';
  signal m_axis_tlast_o  : std_logic;

  -- Status
  signal rx_byte_count_o : unsigned(15 downto 0);
  signal frame_active_o  : std_logic;
  signal overflow_o      : std_logic;

begin

  -- System Clock Generator: 100 MHz
  clk_i <= not clk_i after (c_clk_period / 2);

  -- Device Under Test (DUT)
  dut : entity work.spi_receiver
    generic map (
      g_fifo_depth => 8
    )
    port map (
      clk_i           => clk_i,
      rst_n_i         => rst_n_i,
      spi_sclk_i      => spi_sclk_i,
      spi_cs_n_i      => spi_cs_n_i,
      spi_mosi_i      => spi_mosi_i,
      spi_miso_o      => spi_miso_o,
      m_axis_tdata_o  => m_axis_tdata_o,
      m_axis_tvalid_o => m_axis_tvalid_o,
      m_axis_tready_i => m_axis_tready_i,
      m_axis_tlast_o  => m_axis_tlast_o,
      rx_byte_count_o => rx_byte_count_o,
      frame_active_o  => frame_active_o,
      overflow_o      => overflow_o
    );

  -- Main Test Sequence
  main : process

    -- Helper procedure: Transmit 1 byte via SPI Mode 0 (MSB first)
    procedure spi_send_byte(b : in std_logic_vector(7 downto 0)) is
    begin
      for i in 7 downto 0 loop
        spi_mosi_i <= b(i);
        wait for c_sclk_semi;
        spi_sclk_i <= '1';
        wait for c_sclk_semi;
        spi_sclk_i <= '0';
      end loop;
    end procedure;

    -- Helper procedure: Assert CS, send N bytes, deassert CS
    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

    procedure spi_send_packet(bytes : in byte_array_t) is
    begin
      wait for 50 ns;
      spi_cs_n_i <= '0';
      wait for 100 ns;

      for i in bytes'range loop
        spi_send_byte(bytes(i));
        wait for 20 ns;
      end loop;

      wait for 100 ns;
      spi_cs_n_i <= '1';
      wait for 100 ns;
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset Sequence
      rst_n_i         <= '0';
      spi_sclk_i      <= '0';
      spi_cs_n_i      <= '1';
      spi_mosi_i      <= '0';
      m_axis_tready_i <= '1';
      wait for 100 ns;
      rst_n_i         <= '1';
      wait for 50 ns;

      --------------------------------------------------------------------------
      -- Test 1: Reset Defaults
      --------------------------------------------------------------------------
      if run("test_reset_defaults") then
        check_equal(m_axis_tvalid_o, '0', "tvalid must be 0 after reset");
        check_equal(frame_active_o, '0', "frame_active must be 0 after reset");
        check_equal(overflow_o, '0', "overflow must be 0 after reset");
        check_equal(to_integer(rx_byte_count_o), 0, "byte count must be 0 after reset");

      --------------------------------------------------------------------------
      -- Test 2: Single Byte Reception at 25 MHz
      --------------------------------------------------------------------------
      elsif run("test_spi_single_byte") then
        m_axis_tready_i <= '0';
        spi_cs_n_i      <= '0';
        wait for 100 ns;
        check_equal(frame_active_o, '1', "frame_active must be 1 when CS_n is low");

        spi_send_byte(x"A5");
        wait for 50 ns;

        -- Verify byte received in FIFO and presented on AXI4-Stream
        check_equal(m_axis_tvalid_o, '1', "tvalid must assert when byte is in FIFO");
        check_equal(m_axis_tdata_o, std_logic_vector'(x"A5"), "tdata must match sent byte 0xA5");
        check_equal(to_integer(rx_byte_count_o), 1, "rx_byte_count must be 1");

        -- Consume byte with tready
        m_axis_tready_i <= '1';
        wait until rising_edge(clk_i);
        wait for 20 ns;
        check_equal(m_axis_tvalid_o, '0', "tvalid must deassert once byte is popped");

        -- Deassert CS
        spi_cs_n_i <= '1';
        wait for 100 ns;
        check_equal(frame_active_o, '0', "frame_active must clear after CS_n high");

      --------------------------------------------------------------------------
      -- Test 3: Multi-Byte Packet Reception and TLAST
      --------------------------------------------------------------------------
      elsif run("test_spi_packet_reception") then
        -- Send a 4-byte frame: 0xAA, 0x55, 0x12, 0x34
        m_axis_tready_i <= '0'; -- Hold reading to collect frame
        spi_send_packet((x"AA", x"55", x"12", x"34"));

        wait for 100 ns;
        check_equal(to_integer(rx_byte_count_o), 4, "all 4 bytes received");

        -- Now read out with tready = '1'
        m_axis_tready_i <= '1';
        wait until rising_edge(clk_i) and m_axis_tvalid_o = '1';
        check_equal(m_axis_tdata_o, std_logic_vector'(x"AA"), "Byte 0 must be 0xAA");
        check_equal(m_axis_tlast_o, '0', "Byte 0 tlast must be 0");

        wait until rising_edge(clk_i) and m_axis_tvalid_o = '1';
        check_equal(m_axis_tdata_o, std_logic_vector'(x"55"), "Byte 1 must be 0x55");
        check_equal(m_axis_tlast_o, '0', "Byte 1 tlast must be 0");

        wait until rising_edge(clk_i) and m_axis_tvalid_o = '1';
        check_equal(m_axis_tdata_o, std_logic_vector'(x"12"), "Byte 2 must be 0x12");
        check_equal(m_axis_tlast_o, '0', "Byte 2 tlast must be 0");

        wait until rising_edge(clk_i) and m_axis_tvalid_o = '1';
        check_equal(m_axis_tdata_o, std_logic_vector'(x"34"), "Byte 3 must be 0x34");
        check_equal(m_axis_tlast_o, '1', "Last byte (Byte 3) must have tlast = 1");

      --------------------------------------------------------------------------
      -- Test 4: Backpressure and FIFO Buffering
      --------------------------------------------------------------------------
      elsif run("test_fifo_buffering_and_backpressure") then
        -- Send 3 bytes with tready held low
        m_axis_tready_i <= '0';
        spi_send_packet((x"DE", x"AD", x"BE"));

        wait for 100 ns;
        check_equal(overflow_o, '0', "FIFO must not overflow on 3 bytes (depth=8)");
        check_equal(m_axis_tvalid_o, '1', "tvalid must be high with buffered data");

        -- Consume 1 byte
        m_axis_tready_i <= '1';
        wait until rising_edge(clk_i) and m_axis_tvalid_o = '1';
        check_equal(m_axis_tdata_o, std_logic_vector'(x"DE"), "first byte must be 0xDE");

        -- Pause consumption
        m_axis_tready_i <= '0';
        wait for 50 ns;
        check_equal(m_axis_tdata_o, std_logic_vector'(x"AD"), "next byte must be 0xAD");

        -- Consume remaining
        m_axis_tready_i <= '1';
        wait until rising_edge(clk_i) and m_axis_tvalid_o = '1';
        check_equal(m_axis_tdata_o, std_logic_vector'(x"AD"), "read second byte 0xAD");

        wait until rising_edge(clk_i) and m_axis_tvalid_o = '1';
        check_equal(m_axis_tdata_o, std_logic_vector'(x"BE"), "read third byte 0xBE");
        check_equal(m_axis_tlast_o, '1', "third byte must have tlast = 1");

      --------------------------------------------------------------------------
      -- Test 5: Overflow Detection on Capacity Saturation
      --------------------------------------------------------------------------
      elsif run("test_overflow_detection") then
        -- With g_fifo_depth = 8 and tready = '0', send 10 bytes to trigger overflow
        m_axis_tready_i <= '0';
        spi_send_packet((x"01", x"02", x"03", x"04", x"05", x"06", x"07", x"08", x"09", x"0A"));

        wait for 100 ns;
        check_equal(overflow_o, '1', "overflow flag must assert when FIFO capacity is exceeded");

      end if;

    end loop;

    test_runner_cleanup(runner);
  end process main;

end architecture tb;
