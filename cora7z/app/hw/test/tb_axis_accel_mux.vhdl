-- ============================================================================
-- Testbench: tb_axis_accel_mux
-- Description:
--   Self-checking VUnit testbench for axis_accel_mux.vhdl.
--   Validates AXI4-Lite CSR access, auto-routing by core BUSY signals,
--   manual routing override, and full-duplex stream handshaking.
-- ============================================================================

library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_axis_accel_mux is
  generic (runner_cfg : string);
end entity tb_axis_accel_mux;

architecture tb of tb_axis_accel_mux is

  constant c_clk_period : time := 10 ns; -- 100 MHz clock

  -- Global Clock & Reset
  signal aclk    : std_logic := '0';
  signal aresetn : std_logic := '0';

  -- Core Busy Flags
  signal busy_rle_s    : std_logic := '0';
  signal busy_lz4_s    : std_logic := '0';
  signal busy_aes_s    : std_logic := '0';
  signal busy_chacha_s : std_logic := '0';

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

  -- DMA Stream Interfaces
  signal s_axis_dma_tdata  : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axis_dma_tkeep  : std_logic_vector(3 downto 0)  := (others => '1');
  signal s_axis_dma_tvalid : std_logic := '0';
  signal s_axis_dma_tready : std_logic;
  signal s_axis_dma_tlast  : std_logic := '0';

  signal m_axis_dma_tdata  : std_logic_vector(31 downto 0);
  signal m_axis_dma_tkeep  : std_logic_vector(3 downto 0);
  signal m_axis_dma_tvalid : std_logic;
  signal m_axis_dma_tready : std_logic := '1';
  signal m_axis_dma_tlast  : std_logic;

  -- Accelerator Stream Signals
  signal m_axis_rle_tdata   : std_logic_vector(31 downto 0);
  signal m_axis_rle_tkeep   : std_logic_vector(3 downto 0);
  signal m_axis_rle_tvalid  : std_logic;
  signal m_axis_rle_tready  : std_logic := '1';
  signal m_axis_rle_tlast   : std_logic;
  signal s_axis_rle_tdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axis_rle_tkeep   : std_logic_vector(3 downto 0)  := (others => '1');
  signal s_axis_rle_tvalid  : std_logic := '0';
  signal s_axis_rle_tready  : std_logic;
  signal s_axis_rle_tlast   : std_logic := '0';

  signal m_axis_lz4_tdata   : std_logic_vector(31 downto 0);
  signal m_axis_lz4_tkeep   : std_logic_vector(3 downto 0);
  signal m_axis_lz4_tvalid  : std_logic;
  signal m_axis_lz4_tready  : std_logic := '1';
  signal m_axis_lz4_tlast   : std_logic;
  signal s_axis_lz4_tdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axis_lz4_tkeep   : std_logic_vector(3 downto 0)  := (others => '1');
  signal s_axis_lz4_tvalid  : std_logic := '0';
  signal s_axis_lz4_tready  : std_logic;
  signal s_axis_lz4_tlast   : std_logic := '0';

  signal m_axis_aes_tdata   : std_logic_vector(31 downto 0);
  signal m_axis_aes_tkeep   : std_logic_vector(3 downto 0);
  signal m_axis_aes_tvalid  : std_logic;
  signal m_axis_aes_tready  : std_logic := '1';
  signal m_axis_aes_tlast   : std_logic;
  signal s_axis_aes_tdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axis_aes_tkeep   : std_logic_vector(3 downto 0)  := (others => '1');
  signal s_axis_aes_tvalid  : std_logic := '0';
  signal s_axis_aes_tready  : std_logic;
  signal s_axis_aes_tlast   : std_logic := '0';

  signal m_axis_chacha_tdata  : std_logic_vector(31 downto 0);
  signal m_axis_chacha_tkeep  : std_logic_vector(3 downto 0);
  signal m_axis_chacha_tvalid : std_logic;
  signal m_axis_chacha_tready : std_logic := '1';
  signal m_axis_chacha_tlast  : std_logic;
  signal s_axis_chacha_tdata  : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axis_chacha_tkeep  : std_logic_vector(3 downto 0)  := (others => '1');
  signal s_axis_chacha_tvalid : std_logic := '0';
  signal s_axis_chacha_tready : std_logic;
  signal s_axis_chacha_tlast  : std_logic := '0';

begin

  -- Clock Generator: 100 MHz
  aclk <= not aclk after c_clk_period / 2;

  -- Device Under Test
  dut : entity work.axis_accel_mux
    generic map (
      c_s_axi_addr_width => 12,
      c_s_axi_data_width => 32,
      c_axis_data_width  => 32
    )
    port map (
      aclk                 => aclk,
      aresetn              => aresetn,
      busy_rle_i           => busy_rle_s,
      busy_lz4_i           => busy_lz4_s,
      busy_aes_i           => busy_aes_s,
      busy_chacha_i        => busy_chacha_s,
      s_axi_lite_awaddr    => s_axi_lite_awaddr,
      s_axi_lite_awvalid   => s_axi_lite_awvalid,
      s_axi_lite_awready   => s_axi_lite_awready,
      s_axi_lite_wdata     => s_axi_lite_wdata,
      s_axi_lite_wstrb     => s_axi_lite_wstrb,
      s_axi_lite_wvalid    => s_axi_lite_wvalid,
      s_axi_lite_wready    => s_axi_lite_wready,
      s_axi_lite_bresp     => s_axi_lite_bresp,
      s_axi_lite_bvalid    => s_axi_lite_bvalid,
      s_axi_lite_bready    => s_axi_lite_bready,
      s_axi_lite_araddr    => s_axi_lite_araddr,
      s_axi_lite_arvalid   => s_axi_lite_arvalid,
      s_axi_lite_arready   => s_axi_lite_arready,
      s_axi_lite_rdata     => s_axi_lite_rdata,
      s_axi_lite_rresp     => s_axi_lite_rresp,
      s_axi_lite_rvalid    => s_axi_lite_rvalid,
      s_axi_lite_rready    => s_axi_lite_rready,
      s_axis_dma_tdata     => s_axis_dma_tdata,
      s_axis_dma_tkeep     => s_axis_dma_tkeep,
      s_axis_dma_tvalid    => s_axis_dma_tvalid,
      s_axis_dma_tready    => s_axis_dma_tready,
      s_axis_dma_tlast     => s_axis_dma_tlast,
      m_axis_dma_tdata     => m_axis_dma_tdata,
      m_axis_dma_tkeep     => m_axis_dma_tkeep,
      m_axis_dma_tvalid    => m_axis_dma_tvalid,
      m_axis_dma_tready    => m_axis_dma_tready,
      m_axis_dma_tlast     => m_axis_dma_tlast,
      m_axis_rle_tdata     => m_axis_rle_tdata,
      m_axis_rle_tkeep     => m_axis_rle_tkeep,
      m_axis_rle_tvalid    => m_axis_rle_tvalid,
      m_axis_rle_tready    => m_axis_rle_tready,
      m_axis_rle_tlast     => m_axis_rle_tlast,
      s_axis_rle_tdata     => s_axis_rle_tdata,
      s_axis_rle_tkeep     => s_axis_rle_tkeep,
      s_axis_rle_tvalid    => s_axis_rle_tvalid,
      s_axis_rle_tready    => s_axis_rle_tready,
      s_axis_rle_tlast     => s_axis_rle_tlast,
      m_axis_lz4_tdata     => m_axis_lz4_tdata,
      m_axis_lz4_tkeep     => m_axis_lz4_tkeep,
      m_axis_lz4_tvalid    => m_axis_lz4_tvalid,
      m_axis_lz4_tready    => m_axis_lz4_tready,
      m_axis_lz4_tlast     => m_axis_lz4_tlast,
      s_axis_lz4_tdata     => s_axis_lz4_tdata,
      s_axis_lz4_tkeep     => s_axis_lz4_tkeep,
      s_axis_lz4_tvalid    => s_axis_lz4_tvalid,
      s_axis_lz4_tready    => s_axis_lz4_tready,
      s_axis_lz4_tlast     => s_axis_lz4_tlast,
      m_axis_aes_tdata     => m_axis_aes_tdata,
      m_axis_aes_tkeep     => m_axis_aes_tkeep,
      m_axis_aes_tvalid    => m_axis_aes_tvalid,
      m_axis_aes_tready    => m_axis_aes_tready,
      m_axis_aes_tlast     => m_axis_aes_tlast,
      s_axis_aes_tdata     => s_axis_aes_tdata,
      s_axis_aes_tkeep     => s_axis_aes_tkeep,
      s_axis_aes_tvalid    => s_axis_aes_tvalid,
      s_axis_aes_tready    => s_axis_aes_tready,
      s_axis_aes_tlast     => s_axis_aes_tlast,
      m_axis_chacha_tdata  => m_axis_chacha_tdata,
      m_axis_chacha_tkeep  => m_axis_chacha_tkeep,
      m_axis_chacha_tvalid => m_axis_chacha_tvalid,
      m_axis_chacha_tready => m_axis_chacha_tready,
      m_axis_chacha_tlast  => m_axis_chacha_tlast,
      s_axis_chacha_tdata  => s_axis_chacha_tdata,
      s_axis_chacha_tkeep  => s_axis_chacha_tkeep,
      s_axis_chacha_tvalid => s_axis_chacha_tvalid,
      s_axis_chacha_tready => s_axis_chacha_tready,
      s_axis_chacha_tlast  => s_axis_chacha_tlast
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
      busy_rle_s    <= '0';
      busy_lz4_s    <= '0';
      busy_aes_s    <= '0';
      busy_chacha_s <= '0';
      s_axis_dma_tvalid    <= '0';
      s_axis_rle_tvalid    <= '0';
      s_axis_lz4_tvalid    <= '0';
      s_axis_aes_tvalid    <= '0';
      s_axis_chacha_tvalid <= '0';
      m_axis_dma_tready    <= '1';
      wait for 5 * c_clk_period;
      aresetn       <= '1';
      wait for 5 * c_clk_period;

      -- ----------------------------------------------------------------------
      -- Test 1: CSR Access
      -- ----------------------------------------------------------------------
      if run("test_csr_access") then
        -- Default ROUTING_CTRL should be 0 (auto)
        axi_read(0, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000000"), "Default ROUTING_CTRL should be 0");

        -- Default ACTIVE_CORE should be 0 (parked)
        axi_read(4, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000000"), "Default ACTIVE_CORE should be 0");

        -- Write manual route to LZ4 (2)
        axi_write(0, x"00000002");
        axi_read(0, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000002"), "ROUTING_CTRL should be 2");

        -- Read active core -> should be 2
        axi_read(4, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000002"), "ACTIVE_CORE should be 2");

      -- ----------------------------------------------------------------------
      -- Test 2: Auto Routing by Core BUSY
      -- ----------------------------------------------------------------------
      elsif run("test_auto_routing") then
        -- Assert RLE busy
        busy_rle_s <= '1';
        wait until rising_edge(aclk);
        axi_read(4, v_read_val);
        check_equal(v_read_val(2 downto 0), std_logic_vector'("001"), "Core 1 (RLE) should be active");

        -- Send beat from DMA
        s_axis_dma_tdata  <= x"DEADBEEF";
        s_axis_dma_tvalid <= '1';
        wait for 1 ns;
        check_equal(m_axis_rle_tvalid, '1', "RLE should receive valid beat");
        check_equal(m_axis_rle_tdata, std_logic_vector'(x"DEADBEEF"), "RLE receives data");
        check_equal(m_axis_lz4_tvalid, '0', "LZ4 must not receive beat");
        check_equal(m_axis_aes_tvalid, '0', "AES must not receive beat");
        check_equal(m_axis_chacha_tvalid, '0', "ChaCha must not receive beat");
        check_equal(s_axis_dma_tready, '1', "DMA ready reflects RLE ready");

        -- Clear RLE, assert AES busy
        busy_rle_s <= '0';
        busy_aes_s <= '1';
        wait until rising_edge(aclk);
        axi_read(4, v_read_val);
        check_equal(v_read_val(2 downto 0), std_logic_vector'("011"), "Core 3 (AES) should be active");

        -- Send beat from AES back to DMA
        s_axis_aes_tdata  <= x"CAFEBABE";
        s_axis_aes_tvalid <= '1';
        s_axis_aes_tlast  <= '1';
        wait for 1 ns;
        check_equal(m_axis_dma_tvalid, '1', "DMA receives beat from AES");
        check_equal(m_axis_dma_tdata, std_logic_vector'(x"CAFEBABE"), "DMA receives AES data");
        check_equal(m_axis_dma_tlast, '1', "DMA receives tlast");

      -- ----------------------------------------------------------------------
      -- Test 3: Manual Routing Override
      -- ----------------------------------------------------------------------
      elsif run("test_manual_routing") then
        -- Even if RLE is busy, software overrides to ChaCha20 (4)
        busy_rle_s <= '1';
        axi_write(0, x"00000004");
        axi_read(4, v_read_val);
        check_equal(v_read_val(2 downto 0), std_logic_vector'("100"), "Core 4 (ChaCha20) should be active");

        -- Check streaming routing to ChaCha20
        s_axis_dma_tdata  <= x"12345678";
        s_axis_dma_tvalid <= '1';
        wait for 1 ns;
        check_equal(m_axis_chacha_tvalid, '1', "ChaCha20 receives valid beat");
        check_equal(m_axis_rle_tvalid, '0', "RLE must not receive beat despite busy");

      -- ----------------------------------------------------------------------
      -- Test 4: Backpressure Propagation
      -- ----------------------------------------------------------------------
      elsif run("test_backpressure") then
        busy_lz4_s <= '1';
        wait until rising_edge(aclk);

        -- Downstream core LZ4 is not ready
        m_axis_lz4_tready <= '0';
        wait for 1 ns;
        check_equal(s_axis_dma_tready, '0', "DMA ready should be 0 when LZ4 not ready");

        -- Downstream becomes ready
        m_axis_lz4_tready <= '1';
        wait for 1 ns;
        check_equal(s_axis_dma_tready, '1', "DMA ready should be 1 when LZ4 ready");
      end if;

    end loop;

    test_runner_cleanup(runner);
  end process;

end architecture tb;
