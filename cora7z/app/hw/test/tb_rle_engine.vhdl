-- ============================================================================
-- Testbench: tb_rle_engine
-- Description:
--   Self-checking VUnit testbench for rle_engine.vhdl.
--   Validates AXI4-Lite register access, high-redundancy compression, multiple
--   run sequences, run length saturation (> 255 bytes), and backpressure handling.
-- ============================================================================

library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rle_engine is
  generic (runner_cfg : string);
end entity tb_rle_engine;

architecture tb of tb_rle_engine is

  constant c_clk_period : time := 10 ns; -- 100 MHz clock

  -- Global Clock & Reset
  signal aclk    : std_logic := '0';
  signal aresetn : std_logic := '0';
  signal irq_s   : std_logic;

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
  dut : entity work.rle_engine
    generic map (
      c_s_axi_addr_width => 12,
      c_s_axi_data_width => 32,
      c_axis_data_width  => 32
    )
    port map (
      aclk               => aclk,
      aresetn            => aresetn,
      irq_o              => irq_s,
      busy_o             => open,
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

        -- Write SRC_LEN (0x08)
        axi_write(8, x"00000100");
        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000000"), "SRC_LEN reflects processed input bytes (0 before run)");

      -- ----------------------------------------------------------------------
      -- Test 2: High Redundancy (64 identical bytes 0xAA)
      -- ----------------------------------------------------------------------
      elsif run("test_high_redundancy_64b") then
        -- Arm core via START and IRQ enable: CONTROL = 0x05
        axi_write(0, x"00000005");

        -- Stream 16 beats of 32-bit x"AAAAAAAA" (64 bytes of 0xAA)
        for i in 0 to 15 loop
          wait until rising_edge(aclk);
          s_axis_tdata  <= x"AAAAAAAA";
          s_axis_tkeep  <= "1111";
          s_axis_tvalid <= '1';
          if i = 15 then
            s_axis_tlast <= '1';
          else
            s_axis_tlast <= '0';
          end if;

          loop
            wait until rising_edge(aclk);
            exit when s_axis_tready = '1';
          end loop;
        end loop;

        wait until rising_edge(aclk);
        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';

        -- Await output beat from m_axis
        loop
          wait until rising_edge(aclk);
          if m_axis_tvalid = '1' then
            -- Expected token: [count=64 (0x40), symbol=0xAA] -> 16-bit word 0xAA40
            -- Since only 1 token was generated, bits [15:0] = 0xAA40, tkeep = "0011", tlast = '1'
            check_equal(m_axis_tdata(15 downto 0), std_logic_vector'(x"AA40"), "Compressed token must be [64, 0xAA]");
            check_equal(m_axis_tkeep, std_logic_vector'("0011"), "TKeep must qualify 2 bytes");
            check_equal(m_axis_tlast, '1', "TLast must be asserted on final beat");
            exit;
          end if;
        end loop;

        -- Wait for DONE
        wait for 5 * c_clk_period;
        axi_read(4, v_read_val);
        check_equal(v_read_val(1), '1', "DONE status bit must be asserted");

        -- Check total input and output byte counters
        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000040"), "Input length must be 64 bytes");
        axi_read(12, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000002"), "Output compressed length must be 2 bytes");

      -- ----------------------------------------------------------------------
      -- Test 3: Multiple Distinct Runs (4 x 0x11, 8 x 0x22, 4 x 0x33)
      -- ----------------------------------------------------------------------
      elsif run("test_multiple_runs") then
        axi_write(0, x"00000001");

        -- Beat 0: 4 x 0x11
        wait until rising_edge(aclk);
        s_axis_tdata  <= x"11111111";
        s_axis_tkeep  <= "1111";
        s_axis_tvalid <= '1';
        s_axis_tlast  <= '0';
        loop
          wait until rising_edge(aclk);
          exit when s_axis_tready = '1';
        end loop;

        -- Beat 1: 4 x 0x22
        wait until rising_edge(aclk);
        s_axis_tdata <= x"22222222";
        loop
          wait until rising_edge(aclk);
          exit when s_axis_tready = '1';
        end loop;

        -- Beat 2: 4 x 0x22 (total 8 x 0x22)
        wait until rising_edge(aclk);
        s_axis_tdata <= x"22222222";
        loop
          wait until rising_edge(aclk);
          exit when s_axis_tready = '1';
        end loop;

        -- Beat 3: 4 x 0x33 (final beat)
        wait until rising_edge(aclk);
        s_axis_tdata <= x"33333333";
        s_axis_tlast <= '1';
        loop
          wait until rising_edge(aclk);
          exit when s_axis_tready = '1';
        end loop;

        wait until rising_edge(aclk);
        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';

        -- Beat 1 of Output: Token 1 [4, 0x11] = 0x1104, Token 2 [8, 0x22] = 0x2208
        -- Word = 0x22081104, tkeep = "1111", tlast = '0'
        loop
          wait until rising_edge(aclk);
          if m_axis_tvalid = '1' then
            check_equal(m_axis_tdata, std_logic_vector'(x"22081104"), "First beat must contain [4, 0x11] and [8, 0x22]");
            check_equal(m_axis_tkeep, std_logic_vector'("1111"), "TKeep must qualify 4 bytes");
            check_equal(m_axis_tlast, '0', "TLast must not be set on first beat");
            exit;
          end if;
        end loop;

        -- Beat 2 of Output: Token 3 [4, 0x33] = 0x3304, tkeep = "0011", tlast = '1'
        loop
          wait until rising_edge(aclk);
          if m_axis_tvalid = '1' then
            check_equal(m_axis_tdata(15 downto 0), std_logic_vector'(x"3304"), "Second beat must contain [4, 0x33]");
            check_equal(m_axis_tkeep, std_logic_vector'("0011"), "TKeep must qualify 2 bytes");
            check_equal(m_axis_tlast, '1', "TLast must be set on final beat");
            exit;
          end if;
        end loop;

        wait for 5 * c_clk_period;
        axi_read(12, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000006"), "Total compressed length must be 6 bytes (3 tokens)");

      -- ----------------------------------------------------------------------
      -- Test 4: Run Overflow (> 255 bytes saturation)
      -- ----------------------------------------------------------------------
      elsif run("test_run_overflow_300b") then
        axi_write(0, x"00000001");

        -- Transmit 75 beats of 4 bytes (300 bytes) of 0x55
        for i in 0 to 74 loop
          wait until rising_edge(aclk);
          s_axis_tdata  <= x"55555555";
          s_axis_tkeep  <= "1111";
          s_axis_tvalid <= '1';
          if i = 74 then
            s_axis_tlast <= '1';
          else
            s_axis_tlast <= '0';
          end if;

          loop
            wait until rising_edge(aclk);
            exit when s_axis_tready = '1';
          end loop;
        end loop;

        wait until rising_edge(aclk);
        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';

        -- Output should contain two tokens packed in one word:
        -- Token 1: [255 (0xFF), 0x55] = 0x55FF
        -- Token 2: [45  (0x2D), 0x55] = 0x552D
        -- Word: 0x552D55FF, tkeep = "1111", tlast = '1'
        loop
          wait until rising_edge(aclk);
          if m_axis_tvalid = '1' then
            check_equal(m_axis_tdata, std_logic_vector'(x"552D55FF"), "Word must pack [255, 0x55] and [45, 0x55]");
            check_equal(m_axis_tkeep, std_logic_vector'("1111"), "TKeep must qualify 4 bytes");
            check_equal(m_axis_tlast, '1', "TLast must be asserted on final beat");
            exit;
          end if;
        end loop;

        wait for 5 * c_clk_period;
        axi_read(12, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000004"), "Total compressed length must be 4 bytes");

      -- ----------------------------------------------------------------------
      -- Test 5: Backpressure Handling
      -- ----------------------------------------------------------------------
      elsif run("test_backpressure") then
        axi_write(0, x"00000001");

        -- Transmit 8 bytes (2 beats) of 0x77
        wait until rising_edge(aclk);
        s_axis_tdata  <= x"77777777";
        s_axis_tkeep  <= "1111";
        s_axis_tvalid <= '1';
        s_axis_tlast  <= '0';
        loop
          wait until rising_edge(aclk);
          exit when s_axis_tready = '1';
        end loop;

        wait until rising_edge(aclk);
        s_axis_tdata  <= x"77777777";
        s_axis_tlast  <= '1';
        loop
          wait until rising_edge(aclk);
          exit when s_axis_tready = '1';
        end loop;

        wait until rising_edge(aclk);
        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';

        -- Assert backpressure (hold m_axis_tready low for 5 cycles)
        m_axis_tready <= '0';
        wait for 5 * c_clk_period;
        check_equal(m_axis_tvalid, '1', "Valid must remain held high while ready is low");

        -- Release backpressure
        m_axis_tready <= '1';
        wait until rising_edge(aclk);
        check_equal(m_axis_tdata(15 downto 0), std_logic_vector'(x"7708"), "Token must be [8, 0x77]");
        check_equal(m_axis_tlast, '1', "TLast must be asserted");

      end if;
    end loop;

    test_runner_cleanup(runner);
  end process main;

end architecture tb;
