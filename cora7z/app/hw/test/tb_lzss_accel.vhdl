--------------------------------------------------------------------------------
-- Project: High-Performance PS/PL Acceleration on Zynq-7010
-- File:    tb_lzss_accel.vhdl
-- Entity:  tb_lzss_accel
-- Author:  Antigravity AI / Luis H. R. M. C.
-- Standard: VHDL-2008 (IEEE 1076-2008)
--
-- Description:
--   Self-checking VUnit testbench for lzss_accel.vhdl (Dual-Port BRAM interface).
--   Validates:
--     1. AXI4-Lite CSR register read/write access.
--     2. Sliding-window match search and token emission over BRAM.
--     3. Repetitive payload compression ratio validation (DST_LEN < SRC_LEN).
--     4. Hardware cycle counter telemetry and DONE latching.
--     5. Synchronous soft reset via CONTROL register.
--------------------------------------------------------------------------------

library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_lzss_accel is
  generic (runner_cfg : string);
end entity tb_lzss_accel;

architecture tb of tb_lzss_accel is

  constant c_clk_period : time := 10 ns; -- 100 MHz clock

  -- Global Clock & Reset
  signal aclk    : std_logic := '0';
  signal aresetn : std_logic := '0';
  signal irq_s   : std_logic;
  signal busy_s  : std_logic;

  -- AXI4-Lite Signals
  signal s_axi_awaddr  : std_logic_vector(11 downto 0) := (others => '0');
  signal s_axi_awvalid : std_logic := '0';
  signal s_axi_awready : std_logic;
  signal s_axi_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axi_wstrb   : std_logic_vector(3 downto 0)  := (others => '1');
  signal s_axi_wvalid  : std_logic := '0';
  signal s_axi_wready  : std_logic;
  signal s_axi_bresp   : std_logic_vector(1 downto 0);
  signal s_axi_bvalid  : std_logic;
  signal s_axi_bready  : std_logic := '0';
  signal s_axi_araddr  : std_logic_vector(11 downto 0) := (others => '0');
  signal s_axi_arvalid : std_logic := '0';
  signal s_axi_arready : std_logic;
  signal s_axi_rdata   : std_logic_vector(31 downto 0);
  signal s_axi_rresp   : std_logic_vector(1 downto 0);
  signal s_axi_rvalid  : std_logic;
  signal s_axi_rready  : std_logic := '0';

  -- BRAM Ingress Model
  signal bram_in_en    : std_logic;
  signal bram_in_we    : std_logic_vector(3 downto 0);
  signal bram_in_addr  : std_logic_vector(31 downto 0);
  signal bram_in_din   : std_logic_vector(31 downto 0);
  signal bram_in_dout  : std_logic_vector(31 downto 0) := (others => '0');

  -- BRAM Egress Model
  signal bram_out_en   : std_logic;
  signal bram_out_we   : std_logic_vector(3 downto 0);
  signal bram_out_addr : std_logic_vector(31 downto 0);
  signal bram_out_din  : std_logic_vector(31 downto 0);
  signal bram_out_dout : std_logic_vector(31 downto 0) := (others => '0');

  -- Behavioral BRAM Arrays (2 KB = 512 x 32-bit words)
  type ram_t is array (0 to 511) of std_logic_vector(31 downto 0);
  signal ram_in_mem  : ram_t := (others => (others => '0'));
  signal ram_out_mem : ram_t := (others => (others => '0'));

begin

  -- 100 MHz Clock Generator
  p_clk : process
  begin
    while true loop
      aclk <= '0';
      wait for c_clk_period / 2;
      aclk <= '1';
      wait for c_clk_period / 2;
    end loop;
  end process p_clk;

  -- Behavioral True Dual-Port BRAM Models
  p_bram_models : process(aclk)
    variable v_idx_in  : integer;
    variable v_idx_out : integer;
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        ram_out_mem <= (others => (others => '0'));
      else
        -- BRAM IN Port B
        if bram_in_en = '1' then
          v_idx_in := to_integer(unsigned(bram_in_addr(10 downto 2)));
          if v_idx_in < 512 then
            bram_in_dout <= ram_in_mem(v_idx_in);
          end if;
        end if;

        -- BRAM OUT Port B
        if bram_out_en = '1' then
          v_idx_out := to_integer(unsigned(bram_out_addr(10 downto 2)));
          if v_idx_out < 512 then
            bram_out_dout <= ram_out_mem(v_idx_out);
            if bram_out_we(0) = '1' then
              ram_out_mem(v_idx_out)(7 downto 0) <= bram_out_din(7 downto 0);
            end if;
            if bram_out_we(1) = '1' then
              ram_out_mem(v_idx_out)(15 downto 8) <= bram_out_din(15 downto 8);
            end if;
            if bram_out_we(2) = '1' then
              ram_out_mem(v_idx_out)(23 downto 16) <= bram_out_din(23 downto 16);
            end if;
            if bram_out_we(3) = '1' then
              ram_out_mem(v_idx_out)(31 downto 24) <= bram_out_din(31 downto 24);
            end if;
          end if;
        end if;
      end if;
    end if;
  end process p_bram_models;

  -- Unit Under Test (UUT)
  uut : entity work.lzss_accel
    generic map (
      c_s_axi_addr_width => 12,
      c_s_axi_data_width => 32,
      c_window_size      => 256,
      c_max_lookahead    => 16,
      c_min_match        => 3
    )
    port map (
      aclk          => aclk,
      aresetn       => aresetn,
      irq_o         => irq_s,
      busy_o        => busy_s,
      s_axi_awaddr  => s_axi_awaddr,
      s_axi_awvalid => s_axi_awvalid,
      s_axi_awready => s_axi_awready,
      s_axi_wdata   => s_axi_wdata,
      s_axi_wstrb   => s_axi_wstrb,
      s_axi_wvalid  => s_axi_wvalid,
      s_axi_wready  => s_axi_wready,
      s_axi_bresp   => s_axi_bresp,
      s_axi_bvalid  => s_axi_bvalid,
      s_axi_bready  => s_axi_bready,
      s_axi_araddr  => s_axi_araddr,
      s_axi_arvalid => s_axi_arvalid,
      s_axi_arready => s_axi_arready,
      s_axi_rdata   => s_axi_rdata,
      s_axi_rresp   => s_axi_rresp,
      s_axi_rvalid  => s_axi_rvalid,
      s_axi_rready  => s_axi_rready,
      bram_in_en    => bram_in_en,
      bram_in_we    => bram_in_we,
      bram_in_addr  => bram_in_addr,
      bram_in_din   => bram_in_din,
      bram_in_dout  => bram_in_dout,
      bram_out_en   => bram_out_en,
      bram_out_we   => bram_out_we,
      bram_out_addr => bram_out_addr,
      bram_out_din  => bram_out_din,
      bram_out_dout => bram_out_dout
    );

  -- Main Test Sequence
  p_test : process

    procedure axi_write(addr : in integer; data : in std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(aclk);
      s_axi_awaddr  <= std_logic_vector(to_unsigned(addr, 12));
      s_axi_awvalid <= '1';
      s_axi_wdata   <= data;
      s_axi_wstrb   <= "1111";
      s_axi_wvalid  <= '1';
      s_axi_bready  <= '1';
      loop
        wait until rising_edge(aclk);
        if s_axi_awready = '1' then
          s_axi_awvalid <= '0';
        end if;
        if s_axi_wready = '1' then
          s_axi_wvalid <= '0';
        end if;
        if s_axi_bvalid = '1' then
          s_axi_bready <= '0';
          exit;
        end if;
      end loop;
    end procedure axi_write;

    procedure axi_read(addr : in integer; data : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(aclk);
      s_axi_araddr  <= std_logic_vector(to_unsigned(addr, 12));
      s_axi_arvalid <= '1';
      s_axi_rready  <= '1';
      loop
        wait until rising_edge(aclk);
        if s_axi_arready = '1' then
          s_axi_arvalid <= '0';
        end if;
        if s_axi_rvalid = '1' then
          data := s_axi_rdata;
          s_axi_rready <= '0';
          exit;
        end if;
      end loop;
    end procedure axi_read;

    variable v_data   : std_logic_vector(31 downto 0);
    variable v_status : std_logic_vector(31 downto 0);
    variable v_dst_len: integer;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset Sequence
      aresetn <= '0';
      wait for 50 ns;
      aresetn <= '1';
      wait for 20 ns;

      if run("test_csr_access") then
        info("Testing LZSS AXI4-Lite CSR register write and readback...");
        axi_write(16#08#, x"00000100"); -- 256 bytes
        axi_read(16#08#, v_data);
        check_equal(v_data, std_logic_vector'(x"00000100"), "SRC_LEN readback mismatch");

      elsif run("test_redundant_compression") then
        info("Testing LZSS sliding-window compression on redundant pattern over BRAM...");
        -- Load 24 bytes of repetitive string: "ABCABCABCABCABCABCABCABC"
        -- 'A'=0x41, 'B'=0x42, 'C'=0x43
        -- Word 0: 0x43424141 -> "AABC" ? No: 'A', 'B', 'C', 'A' -> x"41434241"
        ram_in_mem(0) <= x"41434241"; -- "ABCA"
        ram_in_mem(1) <= x"42414342"; -- "BCAB"
        ram_in_mem(2) <= x"43424143"; -- "CABC"
        ram_in_mem(3) <= x"41434241"; -- "ABCA"
        ram_in_mem(4) <= x"42414342"; -- "BCAB"
        ram_in_mem(5) <= x"43424143"; -- "CABC"

        -- Length: 24 bytes
        axi_write(16#08#, x"00000018");

        -- Assert START
        axi_write(16#00#, x"00000001");

        -- Poll STATUS until DONE
        loop
          axi_read(16#04#, v_status);
          exit when v_status(1) = '1';
          wait for 10 ns;
        end loop;

        -- Check Cycle Count
        axi_read(16#10#, v_data);
        check(unsigned(v_data) > 0, "Hardware cycle counter should be > 0");
        info("LZSS compression completed in " & integer'image(to_integer(unsigned(v_data))) & " cycles.");

        -- Check DST_LEN
        axi_read(16#0C#, v_data);
        v_dst_len := to_integer(unsigned(v_data));
        info("Compressed size: " & integer'image(v_dst_len) & " bytes (original: 24 bytes).");
        check(v_dst_len < 24, "Compressed size must be less than original uncompressed size!");

        -- Check uncompressed length header: 0x00, 0x18
        check_equal(ram_out_mem(0)(7 downto 0), std_logic_vector'(x"00"), "Header MSB mismatch");
        check_equal(ram_out_mem(0)(15 downto 8), std_logic_vector'(x"18"), "Header LSB mismatch");

      elsif run("test_64b_pattern") then
        info("Testing LZSS 64-byte test payload...");
        -- Load 64 bytes matching test_sw_pipeline.c: (i * 3 + 0x20) & 0xFF
        for w in 0 to 15 loop
          ram_in_mem(w)(7 downto 0)   <= std_logic_vector(to_unsigned(((w * 4 + 0) * 3 + 16#20#) mod 256, 8));
          ram_in_mem(w)(15 downto 8)  <= std_logic_vector(to_unsigned(((w * 4 + 1) * 3 + 16#20#) mod 256, 8));
          ram_in_mem(w)(23 downto 16) <= std_logic_vector(to_unsigned(((w * 4 + 2) * 3 + 16#20#) mod 256, 8));
          ram_in_mem(w)(31 downto 24) <= std_logic_vector(to_unsigned(((w * 4 + 3) * 3 + 16#20#) mod 256, 8));
        end loop;

        -- Length: 64 bytes
        axi_write(16#08#, x"00000040");

        -- Assert START
        axi_write(16#00#, x"00000001");

        -- Poll STATUS until DONE
        loop
          axi_read(16#04#, v_status);
          exit when v_status(1) = '1';
          wait for 10 ns;
        end loop;

        axi_read(16#0C#, v_data);
        v_dst_len := to_integer(unsigned(v_data));
        info("64B compressed size: " & integer'image(v_dst_len));

        -- Print first 4 words of ram_out_mem
        for w in 0 to 3 loop
          info("ram_out_mem(" & integer'image(w) & ") = 0x" & to_hstring(ram_out_mem(w)));
        end loop;

      elsif run("test_soft_reset") then
        info("Testing synchronous soft reset on LZSS...");
        axi_write(16#00#, x"00000002"); -- RESET_CORE bit 1
        wait for 30 ns;
        axi_read(16#04#, v_status);
        check_equal(v_status(0), '0', "BUSY should be 0 after reset");
        check_equal(v_status(1), '0', "DONE should be 0 after reset");

      end if;

    end loop;

    test_runner_cleanup(runner);
  end process p_test;

end architecture tb;
