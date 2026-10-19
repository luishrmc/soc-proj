-- ============================================================================
-- Testbench: tb_lz4_engine
-- Description:
--   Self-checking VUnit testbench for lz4_engine.vhdl.
--   Validates AXI4-Lite register access, pure literal emission, dictionary
--   match detection, multiple sequence compression, and stream backpressure.
-- ============================================================================

library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_lz4_engine is
  generic (runner_cfg : string);
end entity tb_lz4_engine;

architecture tb of tb_lz4_engine is

  constant c_clk_period : time := 10 ns; -- 100 MHz clock

  -- Global Clock & Reset
  signal aclk    : std_logic := '0';
  signal aresetn : std_logic := '0';
  signal irq_s   : std_logic;
  signal busy_s  : std_logic;

  -- AXI4-Lite Signals
  signal s_axi_lite_awaddr  : std_logic_vector(11 downto 0) := (others => '0');
  signal s_axi_lite_awvalid : std_logic := '0';
  signal s_axi_lite_awready : std_logic;
  signal s_axi_lite_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axi_lite_wstrb   : std_logic_vector(3 downto 0)  := (others => '1');
  signal s_axi_lite_wvalid  : std_logic := '0';
  signal s_axi_lite_wready  : std_logic;
  signal s_axi_lite_bresp   : std_logic_vector(1 downto 0);
  signal s_axi_lite_bvalid  : std_logic;
  signal s_axi_lite_bready  : std_logic := '0';
  signal s_axi_lite_araddr  : std_logic_vector(11 downto 0) := (others => '0');
  signal s_axi_lite_arvalid : std_logic := '0';
  signal s_axi_lite_arready : std_logic;
  signal s_axi_lite_rdata   : std_logic_vector(31 downto 0);
  signal s_axi_lite_rresp   : std_logic_vector(1 downto 0);
  signal s_axi_lite_rvalid  : std_logic;
  signal s_axi_lite_rready  : std_logic := '0';

  -- AXI4-Stream Ingress
  signal s_axis_tdata  : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axis_tkeep  : std_logic_vector(3 downto 0)  := (others => '1');
  signal s_axis_tvalid : std_logic := '0';
  signal s_axis_tready : std_logic;
  signal s_axis_tlast  : std_logic := '0';

  -- AXI4-Stream Egress
  signal m_axis_tdata  : std_logic_vector(31 downto 0);
  signal m_axis_tkeep  : std_logic_vector(3 downto 0);
  signal m_axis_tvalid : std_logic;
  signal m_axis_tready : std_logic := '1';
  signal m_axis_tlast  : std_logic;

begin

  -- Clock Generator: 100 MHz
  aclk <= not aclk after c_clk_period / 2;

  -- Device Under Test
  dut : entity work.lz4_engine
    generic map (
      c_s_axi_addr_width => 12,
      c_s_axi_data_width => 32,
      c_axis_data_width  => 32,
      c_window_size      => 2048,
      c_hash_size        => 1024
    )
    port map (
      aclk               => aclk,
      aresetn            => aresetn,
      irq_o              => irq_s,
      busy_o             => busy_s,
      s_axi_lite_awaddr  => s_axi_lite_awaddr,
      s_axi_lite_awvalid => s_axi_lite_awvalid,
      s_axi_lite_awready => s_axi_lite_awready,
      s_axi_lite_wdata   => s_axi_lite_wdata,
      s_axi_lite_wstrb   => s_axi_lite_wstrb,
      s_axi_lite_wvalid  => s_axi_lite_wvalid,
      s_axi_lite_wready  => s_axi_lite_wready,
      s_axi_lite_bresp   => s_axi_lite_bresp,
      s_axi_lite_bvalid  => s_axi_lite_bvalid,
      s_axi_lite_bready  => s_axi_lite_bready,
      s_axi_lite_araddr  => s_axi_lite_araddr,
      s_axi_lite_arvalid => s_axi_lite_arvalid,
      s_axi_lite_arready => s_axi_lite_arready,
      s_axi_lite_rdata   => s_axi_lite_rdata,
      s_axi_lite_rresp   => s_axi_lite_rresp,
      s_axi_lite_rvalid  => s_axi_lite_rvalid,
      s_axi_lite_rready  => s_axi_lite_rready,
      s_axis_tdata       => s_axis_tdata,
      s_axis_tkeep       => s_axis_tkeep,
      s_axis_tvalid      => s_axis_tvalid,
      s_axis_tready      => s_axis_tready,
      s_axis_tlast       => s_axis_tlast,
      m_axis_tdata       => m_axis_tdata,
      m_axis_tkeep       => m_axis_tkeep,
      m_axis_tvalid      => m_axis_tvalid,
      m_axis_tready      => m_axis_tready,
      m_axis_tlast       => m_axis_tlast
    );

  -- Main Test Sequence
  main : process
    -- Helper procedure: AXI-Lite Write
    procedure axi_write(addr : in integer; data : in std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(aclk);
      s_axi_lite_awaddr  <= std_logic_vector(to_unsigned(addr, 12));
      s_axi_lite_awvalid <= '1';
      s_axi_lite_wdata   <= data;
      s_axi_lite_wvalid  <= '1';
      s_axi_lite_bready  <= '1';
      loop
        wait until rising_edge(aclk);
        if s_axi_lite_awready = '1' then
          s_axi_lite_awvalid <= '0';
        end if;
        if s_axi_lite_wready = '1' then
          s_axi_lite_wvalid <= '0';
        end if;
        if s_axi_lite_bvalid = '1' then
          s_axi_lite_bready <= '0';
          exit;
        end if;
      end loop;
    end procedure;

    -- Helper procedure: AXI-Lite Read
    procedure axi_read(addr : in integer; data : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(aclk);
      s_axi_lite_araddr  <= std_logic_vector(to_unsigned(addr, 12));
      s_axi_lite_arvalid <= '1';
      s_axi_lite_rready  <= '1';
      loop
        wait until rising_edge(aclk);
        if s_axi_lite_arready = '1' then
          s_axi_lite_arvalid <= '0';
        end if;
        if s_axi_lite_rvalid = '1' then
          data := s_axi_lite_rdata;
          s_axi_lite_rready <= '0';
          exit;
        end if;
      end loop;
    end procedure;

    -- Helper procedure: Send 32-bit beat
    procedure send_beat(data : in std_logic_vector(31 downto 0); is_last : in std_logic) is
    begin
      wait until rising_edge(aclk);
      s_axis_tdata  <= data;
      s_axis_tkeep  <= "1111";
      s_axis_tvalid <= '1';
      s_axis_tlast  <= is_last;
      loop
        wait until rising_edge(aclk);
        if s_axis_tready = '1' then
          s_axis_tvalid <= '0';
          s_axis_tlast  <= '0';
          exit;
        end if;
      end loop;
    end procedure;

    variable v_read_val : std_logic_vector(31 downto 0);

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset DUT before each test case
      aresetn       <= '0';
      s_axis_tvalid <= '0';
      m_axis_tready <= '1';
      wait for 5 * c_clk_period;
      aresetn       <= '1';
      wait for 5 * c_clk_period;

      -- ----------------------------------------------------------------------
      -- Test 1: AXI4-Lite CSR Access
      -- ----------------------------------------------------------------------
      if run("test_csr_access") then
        -- Read default STATUS register (should be 0x00000000)
        axi_read(4, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000000"), "Initial status register should be zero");

        -- Enable interrupt via CONTROL (0x00, bit 2)
        axi_write(0, x"00000004");
        axi_read(0, v_read_val);
        check_equal(v_read_val(2), '1', "IRQ_EN bit should be set in CONTROL");

      -- ----------------------------------------------------------------------
      -- Test 2: Pure Literals Compression (Non-repeating bytes)
      -- ----------------------------------------------------------------------
      elsif run("test_pure_literals") then
        -- Trigger START bit
        axi_write(0, x"00000005"); -- START=1, IRQ_EN=1

        -- Send 8 bytes of non-repeating data:
        -- Beat 0: 0x04030201 (bytes: 1, 2, 3, 4)
        -- Beat 1: 0x08070605 (bytes: 5, 6, 7, 8) with tlast=1
        send_beat(x"04030201", '0');
        send_beat(x"08070605", '1');

        -- Wait for completion (DONE = 1 or IRQ)
        loop
          axi_read(4, v_read_val);
          if v_read_val(1) = '1' then -- DONE bit
            exit;
          end if;
          wait for c_clk_period;
        end loop;

        -- Verify input counter: 8 bytes
        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000008"), "SRC_LEN should record 8 processed input bytes");

        -- Verify output length > 0
        axi_read(12, v_read_val);
        check(to_integer(unsigned(v_read_val)) > 0, "DST_LEN should be non-zero");

        -- Verify cycle counter > 0
        axi_read(16, v_read_val);
        check(to_integer(unsigned(v_read_val)) > 0, "CYCLE_COUNT should record active processing cycles");

      -- ----------------------------------------------------------------------
      -- Test 3: Dictionary Match Detection (Repeating 4-byte sequence)
      -- ----------------------------------------------------------------------
      elsif run("test_match_compression") then
        axi_write(0, x"00000005"); -- START=1, IRQ_EN=1

        -- Send pattern:
        -- Beat 0: 0x44434241 ("ABCD")
        -- Beat 1: 0x44434241 ("ABCD" repeated -> should match at offset 4!)
        -- Beat 2: 0x34333231 ("1234" trailing) with tlast=1
        send_beat(x"44434241", '0');
        send_beat(x"44434241", '0');
        send_beat(x"34333231", '1');

        -- Wait for DONE
        loop
          axi_read(4, v_read_val);
          if v_read_val(1) = '1' then
            exit;
          end if;
          wait for c_clk_period;
        end loop;

        -- Verify SRC_LEN is 12 bytes
        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"0000000C"), "SRC_LEN should record 12 input bytes");

        -- Verify DST_LEN is recorded
        axi_read(12, v_read_val);
        check(to_integer(unsigned(v_read_val)) > 0, "DST_LEN should reflect compressed sequence bytes");

      -- ----------------------------------------------------------------------
      -- Test 4: Structured Sequence Compression
      -- ----------------------------------------------------------------------
      elsif run("test_structured_stream") then
        axi_write(0, x"00000005");

        -- Send 4 beats:
        -- "TEST" (0x54534554), "TEST" (0x54534554), "TEST" (0x54534554), "DONE" (0x454E4F44)
        send_beat(x"54534554", '0');
        send_beat(x"54534554", '0');
        send_beat(x"54534554", '0');
        send_beat(x"454E4F44", '1');

        loop
          axi_read(4, v_read_val);
          if v_read_val(1) = '1' then
            exit;
          end if;
          wait for c_clk_period;
        end loop;

        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000010"), "SRC_LEN should record 16 input bytes");

      -- ----------------------------------------------------------------------
      -- Test 5: Stream Backpressure (m_axis_tready = '0')
      -- ----------------------------------------------------------------------
      elsif run("test_backpressure") then
        -- Initially deassert m_axis_tready to simulate downstream stall
        m_axis_tready <= '0';
        axi_write(0, x"00000005");

        -- Send 2 beats while backpressured
        send_beat(x"AABBCCDD", '0');
        send_beat(x"11223344", '1');

        -- Wait 10 cycles during stall
        wait for 10 * c_clk_period;

        -- Release backpressure
        m_axis_tready <= '1';

        -- Wait for DONE
        loop
          axi_read(4, v_read_val);
          if v_read_val(1) = '1' then
            exit;
          end if;
          wait for c_clk_period;
        end loop;

        -- Verify input counter
        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000008"), "SRC_LEN should record 8 input bytes despite backpressure");

      -- ----------------------------------------------------------------------
      -- Test 6: Soft Reset via CONTROL (bit 1)
      -- ----------------------------------------------------------------------
      elsif run("test_soft_reset") then
        -- Start an operation
        axi_write(0, x"00000001");
        send_beat(x"01020304", '0');
        wait for 2 * c_clk_period;

        -- Trigger soft reset
        axi_write(0, x"00000002");
        wait for 3 * c_clk_period;

        -- Verify status BUSY is cleared and STATUS is 0
        axi_read(4, v_read_val);
        check_equal(v_read_val(0), '0', "BUSY bit should be cleared after soft reset");
        check_equal(busy_s, '0', "busy_o should be deasserted after soft reset");
      end if;

    end loop;

    test_runner_cleanup(runner);
  end process;

end architecture tb;
