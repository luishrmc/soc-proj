--------------------------------------------------------------------------------
-- Company:       UFMG / Embedded Systems & SoC Laboratory
-- Engineer:      Antigravity Agentic Assistant & User
--
-- Create Date:   2026-10-19
-- Design Name:   axis_accel_mux
-- Module Name:   axis_accel_mux - rtl
-- Project Name:  Zynq-7010 PS/PL Compression & Encryption Benchmark
-- Target Devices: Digilent Cora Z7-10 (XC7Z010-1CLG400C)
-- Tool Versions: Vivado 2026.1 / GHDL VHDL-2008
-- Description:   AXI4-Stream Multi-Accelerator Multiplexer / Demultiplexer.
--                Dynamically routes AXI DMA MM2S and S2MM stream traffic to one
--                of four hardware acceleration cores (RLE, LZ4, AES-CTR, ChaCha20).
--                Supports auto-routing based on core BUSY flags or direct software
--                override via AXI4-Lite control register at 0x43C40000.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_accel_mux is
  generic (
    c_s_axi_addr_width : integer := 12;
    c_s_axi_data_width : integer := 32;
    c_axis_data_width  : integer := 32
  );
  port (
    -- Synchronous Stream and Control Clock & Reset
    aclk                  : in  std_logic;
    aresetn               : in  std_logic;

    -- Hardware Accelerator Core Busy Indicators
    busy_rle_i            : in  std_logic;
    busy_lz4_i            : in  std_logic;
    busy_aes_i            : in  std_logic;
    busy_chacha_i         : in  std_logic;

    -- ========================================================================
    -- AXI4-Lite Slave Interface (Routing Control & Status)
    -- ========================================================================
    s_axi_lite_awaddr     : in  std_logic_vector(c_s_axi_addr_width - 1 downto 0);
    s_axi_lite_awvalid    : in  std_logic;
    s_axi_lite_awready    : out std_logic;

    s_axi_lite_wdata      : in  std_logic_vector(c_s_axi_data_width - 1 downto 0);
    s_axi_lite_wstrb      : in  std_logic_vector((c_s_axi_data_width / 8) - 1 downto 0);
    s_axi_lite_wvalid     : in  std_logic;
    s_axi_lite_wready     : out std_logic;

    s_axi_lite_bresp      : out std_logic_vector(1 downto 0);
    s_axi_lite_bvalid     : out std_logic;
    s_axi_lite_bready     : in  std_logic;

    s_axi_lite_araddr     : in  std_logic_vector(c_s_axi_addr_width - 1 downto 0);
    s_axi_lite_arvalid    : in  std_logic;
    s_axi_lite_arready    : out std_logic;

    s_axi_lite_rdata      : out std_logic_vector(c_s_axi_data_width - 1 downto 0);
    s_axi_lite_rresp      : out std_logic_vector(1 downto 0);
    s_axi_lite_rvalid     : out std_logic;
    s_axi_lite_rready     : in  std_logic;

    -- ========================================================================
    -- AXI4-Stream DMA Ingress (MM2S: Memory to Stream)
    -- ========================================================================
    s_axis_dma_tdata      : in  std_logic_vector(c_axis_data_width - 1 downto 0);
    s_axis_dma_tkeep      : in  std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    s_axis_dma_tvalid     : in  std_logic;
    s_axis_dma_tready     : out std_logic;
    s_axis_dma_tlast      : in  std_logic;

    -- ========================================================================
    -- AXI4-Stream DMA Egress (S2MM: Stream to Memory)
    -- ========================================================================
    m_axis_dma_tdata      : out std_logic_vector(c_axis_data_width - 1 downto 0);
    m_axis_dma_tkeep      : out std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    m_axis_dma_tvalid     : out std_logic;
    m_axis_dma_tready     : in  std_logic;
    m_axis_dma_tlast      : out std_logic;

    -- ========================================================================
    -- Core 1: RLE Compression Accelerator Stream Interface
    -- ========================================================================
    m_axis_rle_tdata      : out std_logic_vector(c_axis_data_width - 1 downto 0);
    m_axis_rle_tkeep      : out std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    m_axis_rle_tvalid     : out std_logic;
    m_axis_rle_tready     : in  std_logic;
    m_axis_rle_tlast      : out std_logic;

    s_axis_rle_tdata      : in  std_logic_vector(c_axis_data_width - 1 downto 0);
    s_axis_rle_tkeep      : in  std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    s_axis_rle_tvalid     : in  std_logic;
    s_axis_rle_tready     : out std_logic;
    s_axis_rle_tlast      : in  std_logic;

    -- ========================================================================
    -- Core 2: LZ4 Compression Accelerator Stream Interface
    -- ========================================================================
    m_axis_lz4_tdata      : out std_logic_vector(c_axis_data_width - 1 downto 0);
    m_axis_lz4_tkeep      : out std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    m_axis_lz4_tvalid     : out std_logic;
    m_axis_lz4_tready     : in  std_logic;
    m_axis_lz4_tlast      : out std_logic;

    s_axis_lz4_tdata      : in  std_logic_vector(c_axis_data_width - 1 downto 0);
    s_axis_lz4_tkeep      : in  std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    s_axis_lz4_tvalid     : in  std_logic;
    s_axis_lz4_tready     : out std_logic;
    s_axis_lz4_tlast      : in  std_logic;

    -- ========================================================================
    -- Core 3: AES-128-CTR Crypto Accelerator Stream Interface
    -- ========================================================================
    m_axis_aes_tdata      : out std_logic_vector(c_axis_data_width - 1 downto 0);
    m_axis_aes_tkeep      : out std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    m_axis_aes_tvalid     : out std_logic;
    m_axis_aes_tready     : in  std_logic;
    m_axis_aes_tlast      : out std_logic;

    s_axis_aes_tdata      : in  std_logic_vector(c_axis_data_width - 1 downto 0);
    s_axis_aes_tkeep      : in  std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    s_axis_aes_tvalid     : in  std_logic;
    s_axis_aes_tready     : out std_logic;
    s_axis_aes_tlast      : in  std_logic;

    -- ========================================================================
    -- Core 4: ChaCha20 Crypto Accelerator Stream Interface
    -- ========================================================================
    m_axis_chacha_tdata   : out std_logic_vector(c_axis_data_width - 1 downto 0);
    m_axis_chacha_tkeep   : out std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    m_axis_chacha_tvalid  : out std_logic;
    m_axis_chacha_tready  : in  std_logic;
    m_axis_chacha_tlast   : out std_logic;

    s_axis_chacha_tdata   : in  std_logic_vector(c_axis_data_width - 1 downto 0);
    s_axis_chacha_tkeep   : in  std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    s_axis_chacha_tvalid  : in  std_logic;
    s_axis_chacha_tready  : out std_logic;
    s_axis_chacha_tlast   : in  std_logic
  );
end entity axis_accel_mux;

architecture rtl of axis_accel_mux is

  -- Register address offsets (per INTERFACES.md Section 2.6)
  constant c_addr_routing_ctrl : std_logic_vector(7 downto 0) := x"00";
  constant c_addr_active_core  : std_logic_vector(7 downto 0) := x"04";

  -- AXI4-Lite Internal Handshake Registers
  signal axi_awready_r : std_logic := '0';
  signal axi_wready_r  : std_logic := '0';
  signal axi_bvalid_r  : std_logic := '0';
  signal axi_arready_r : std_logic := '0';
  signal axi_rvalid_r  : std_logic := '0';
  signal axi_rdata_r   : std_logic_vector(31 downto 0) := (others => '0');

  -- Control Register: 0=Auto by busy, 1=RLE, 2=LZ4, 3=AES, 4=ChaCha20
  signal reg_routing_ctrl_r : std_logic_vector(31 downto 0) := (others => '0');

  -- Active Core Selection: 0=None/Parked, 1=RLE, 2=LZ4, 3=AES, 4=ChaCha20
  signal active_core_s : integer range 0 to 4 := 0;

begin

  -- ==========================================================================
  -- Section 1: AXI4-Lite Control & Status Registers
  -- ==========================================================================
  s_axi_lite_awready <= axi_awready_r;
  s_axi_lite_wready  <= axi_wready_r;
  s_axi_lite_bresp   <= "00"; -- OKAY
  s_axi_lite_bvalid  <= axi_bvalid_r;

  s_axi_lite_arready <= axi_arready_r;
  s_axi_lite_rdata   <= axi_rdata_r;
  s_axi_lite_rresp   <= "00"; -- OKAY
  s_axi_lite_rvalid  <= axi_rvalid_r;

  -- AXI4-Lite Write Channel
  process (aclk)
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        axi_awready_r      <= '0';
        axi_wready_r       <= '0';
        axi_bvalid_r       <= '0';
        reg_routing_ctrl_r <= (others => '0');
      else
        if (s_axi_lite_awvalid = '1' and axi_awready_r = '0') and
           (s_axi_lite_wvalid = '1' and axi_wready_r = '0') then
          axi_awready_r <= '1';
          axi_wready_r  <= '1';

          if s_axi_lite_awaddr(7 downto 0) = c_addr_routing_ctrl then
            reg_routing_ctrl_r <= s_axi_lite_wdata;
          end if;
        else
          axi_awready_r <= '0';
          axi_wready_r  <= '0';
        end if;

        if (axi_awready_r = '1' and axi_wready_r = '1') then
          axi_bvalid_r <= '1';
        elsif s_axi_lite_bready = '1' then
          axi_bvalid_r <= '0';
        end if;
      end if;
    end if;
  end process;

  -- AXI4-Lite Read Channel
  process (aclk)
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        axi_arready_r <= '0';
        axi_rvalid_r  <= '0';
        axi_rdata_r   <= (others => '0');
      else
        if s_axi_lite_arvalid = '1' and axi_arready_r = '0' then
          axi_arready_r <= '1';
          axi_rvalid_r  <= '1';

          case s_axi_lite_araddr(7 downto 0) is
            when c_addr_routing_ctrl =>
              axi_rdata_r <= reg_routing_ctrl_r;
            when c_addr_active_core =>
              axi_rdata_r <= std_logic_vector(to_unsigned(active_core_s, 32));
            when others =>
              axi_rdata_r <= (others => '0');
          end case;
        else
          axi_arready_r <= '0';
          if s_axi_lite_rready = '1' then
            axi_rvalid_r <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;

  -- ==========================================================================
  -- Section 2: Routing Arbitration Logic
  -- ==========================================================================
  process (reg_routing_ctrl_r, busy_rle_i, busy_lz4_i, busy_aes_i, busy_chacha_i)
  begin
    case reg_routing_ctrl_r(2 downto 0) is
      when "001" =>
        active_core_s <= 1; -- Manual Override: RLE
      when "010" =>
        active_core_s <= 2; -- Manual Override: LZ4
      when "011" =>
        active_core_s <= 3; -- Manual Override: AES-128-CTR
      when "100" =>
        active_core_s <= 4; -- Manual Override: ChaCha20
      when others =>
        -- Auto Mode: Route based on which core has BUSY asserted
        if busy_rle_i = '1' then
          active_core_s <= 1;
        elsif busy_lz4_i = '1' then
          active_core_s <= 2;
        elsif busy_aes_i = '1' then
          active_core_s <= 3;
        elsif busy_chacha_i = '1' then
          active_core_s <= 4;
        else
          active_core_s <= 0; -- Idle / Parked
        end if;
    end case;
  end process;

  -- ==========================================================================
  -- Section 3: AXI4-Stream Demultiplexer (DMA MM2S -> Selected Core)
  -- ==========================================================================
  -- Connect data and metadata common signals
  m_axis_rle_tdata    <= s_axis_dma_tdata;
  m_axis_rle_tkeep    <= s_axis_dma_tkeep;
  m_axis_rle_tlast    <= s_axis_dma_tlast;

  m_axis_lz4_tdata    <= s_axis_dma_tdata;
  m_axis_lz4_tkeep    <= s_axis_dma_tkeep;
  m_axis_lz4_tlast    <= s_axis_dma_tlast;

  m_axis_aes_tdata    <= s_axis_dma_tdata;
  m_axis_aes_tkeep    <= s_axis_dma_tkeep;
  m_axis_aes_tlast    <= s_axis_dma_tlast;

  m_axis_chacha_tdata <= s_axis_dma_tdata;
  m_axis_chacha_tkeep <= s_axis_dma_tkeep;
  m_axis_chacha_tlast <= s_axis_dma_tlast;

  -- Demux valid and ready handshakes
  process (active_core_s, s_axis_dma_tvalid, m_axis_rle_tready,
           m_axis_lz4_tready, m_axis_aes_tready, m_axis_chacha_tready)
  begin
    m_axis_rle_tvalid    <= '0';
    m_axis_lz4_tvalid    <= '0';
    m_axis_aes_tvalid    <= '0';
    m_axis_chacha_tvalid <= '0';
    s_axis_dma_tready    <= '0';

    case active_core_s is
      when 1 =>
        m_axis_rle_tvalid <= s_axis_dma_tvalid;
        s_axis_dma_tready <= m_axis_rle_tready;

      when 2 =>
        m_axis_lz4_tvalid <= s_axis_dma_tvalid;
        s_axis_dma_tready <= m_axis_lz4_tready;

      when 3 =>
        m_axis_aes_tvalid <= s_axis_dma_tvalid;
        s_axis_dma_tready <= m_axis_aes_tready;

      when 4 =>
        m_axis_chacha_tvalid <= s_axis_dma_tvalid;
        s_axis_dma_tready    <= m_axis_chacha_tready;

      when others =>
        s_axis_dma_tready <= '0';
    end case;
  end process;

  -- ==========================================================================
  -- Section 4: AXI4-Stream Multiplexer (Selected Core -> DMA S2MM)
  -- ==========================================================================
  process (active_core_s, m_axis_dma_tready,
           s_axis_rle_tdata, s_axis_rle_tkeep, s_axis_rle_tvalid, s_axis_rle_tlast,
           s_axis_lz4_tdata, s_axis_lz4_tkeep, s_axis_lz4_tvalid, s_axis_lz4_tlast,
           s_axis_aes_tdata, s_axis_aes_tkeep, s_axis_aes_tvalid, s_axis_aes_tlast,
           s_axis_chacha_tdata, s_axis_chacha_tkeep, s_axis_chacha_tvalid, s_axis_chacha_tlast)
  begin
    s_axis_rle_tready    <= '0';
    s_axis_lz4_tready    <= '0';
    s_axis_aes_tready    <= '0';
    s_axis_chacha_tready <= '0';

    case active_core_s is
      when 1 =>
        m_axis_dma_tdata  <= s_axis_rle_tdata;
        m_axis_dma_tkeep  <= s_axis_rle_tkeep;
        m_axis_dma_tvalid <= s_axis_rle_tvalid;
        m_axis_dma_tlast  <= s_axis_rle_tlast;
        s_axis_rle_tready <= m_axis_dma_tready;

      when 2 =>
        m_axis_dma_tdata  <= s_axis_lz4_tdata;
        m_axis_dma_tkeep  <= s_axis_lz4_tkeep;
        m_axis_dma_tvalid <= s_axis_lz4_tvalid;
        m_axis_dma_tlast  <= s_axis_lz4_tlast;
        s_axis_lz4_tready <= m_axis_dma_tready;

      when 3 =>
        m_axis_dma_tdata  <= s_axis_aes_tdata;
        m_axis_dma_tkeep  <= s_axis_aes_tkeep;
        m_axis_dma_tvalid <= s_axis_aes_tvalid;
        m_axis_dma_tlast  <= s_axis_aes_tlast;
        s_axis_aes_tready <= m_axis_dma_tready;

      when 4 =>
        m_axis_dma_tdata     <= s_axis_chacha_tdata;
        m_axis_dma_tkeep     <= s_axis_chacha_tkeep;
        m_axis_dma_tvalid    <= s_axis_chacha_tvalid;
        m_axis_dma_tlast     <= s_axis_chacha_tlast;
        s_axis_chacha_tready <= m_axis_dma_tready;

      when others =>
        m_axis_dma_tdata  <= (others => '0');
        m_axis_dma_tkeep  <= (others => '0');
        m_axis_dma_tvalid <= '0';
        m_axis_dma_tlast  <= '0';
    end case;
  end process;

end architecture rtl;
