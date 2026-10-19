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

  -- Byte-level capture for decompressor verification
  type t_byte_arr is array (0 to 1023) of std_logic_vector(7 downto 0);
  signal captured_bytes : t_byte_arr := (others => (others => '0'));
  signal captured_count : integer := 0;
  signal capture_reset  : std_logic := '0';

begin

  -- Clock Generator: 100 MHz
  aclk <= not aclk after c_clk_period / 2;

  -- Capture output stream bytes for bit-level round-trip verification
  capture_proc : process (aclk)
  begin
    if rising_edge(aclk) then
      if aresetn = '0' or capture_reset = '1' then
        captured_count <= 0;
      elsif m_axis_tvalid = '1' and m_axis_tready = '1' then
        if m_axis_tkeep(0) = '1' then
          captured_bytes(captured_count) <= m_axis_tdata(7 downto 0);
          if m_axis_tkeep(1) = '1' then
            captured_bytes(captured_count + 1) <= m_axis_tdata(15 downto 8);
            if m_axis_tkeep(2) = '1' then
              captured_bytes(captured_count + 2) <= m_axis_tdata(23 downto 16);
              if m_axis_tkeep(3) = '1' then
                captured_bytes(captured_count + 3) <= m_axis_tdata(31 downto 24);
                captured_count <= captured_count + 4;
              else
                captured_count <= captured_count + 3;
              end if;
            else
              captured_count <= captured_count + 2;
            end if;
          else
            captured_count <= captured_count + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

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
    -- Helper procedure: LZ4 Decompression & Verification
    procedure lz4_decompress_and_verify(
      comp_bytes : in t_byte_arr;
      comp_len   : in integer;
      expected   : in t_byte_arr;
      exp_len    : in integer
    ) is
      variable v_dec : t_byte_arr := (others => (others => '0'));
      variable v_ip  : integer := 0;
      variable v_op  : integer := 0;
      variable v_tok : std_logic_vector(7 downto 0);
      variable v_lit_len : integer;
      variable v_mat_len : integer;
      variable v_off : integer;
      variable v_extra : integer;
    begin
      check(comp_len > 0, "Compressed output length must be > 0");
      while v_ip < comp_len loop
        v_tok := comp_bytes(v_ip);
        v_ip  := v_ip + 1;

        -- 1. Literal length
        v_lit_len := to_integer(unsigned(v_tok(7 downto 4)));
        if v_lit_len = 15 then
          while v_ip < comp_len loop
            v_extra := to_integer(unsigned(comp_bytes(v_ip)));
            v_ip := v_ip + 1;
            v_lit_len := v_lit_len + v_extra;
            exit when v_extra < 255;
          end loop;
        end if;

        -- 2. Copy literals
        for i in 0 to v_lit_len - 1 loop
          check(v_ip < comp_len, "Literal overflow in compressed stream");
          v_dec(v_op) := comp_bytes(v_ip);
          v_op := v_op + 1;
          v_ip := v_ip + 1;
        end loop;

        -- End of block if no more compressed bytes
        exit when v_ip >= comp_len;

        -- 3. Match offset (16-bit LE)
        check(v_ip + 1 < comp_len, "Truncated match offset in stream");
        v_off := to_integer(unsigned(comp_bytes(v_ip))) +
                 to_integer(unsigned(comp_bytes(v_ip + 1))) * 256;
        v_ip := v_ip + 2;
        check(v_off > 0 and v_off <= v_op, "Invalid match offset: " & integer'image(v_off));

        -- 4. Match length (nibble + 4)
        v_mat_len := to_integer(unsigned(v_tok(3 downto 0))) + 4;
        if v_tok(3 downto 0) = "1111" then
          while v_ip < comp_len loop
            v_extra := to_integer(unsigned(comp_bytes(v_ip)));
            v_ip := v_ip + 1;
            v_mat_len := v_mat_len + v_extra;
            exit when v_extra < 255;
          end loop;
        end if;

        -- Copy match (byte-by-byte to support overlapping runs)
        for i in 0 to v_mat_len - 1 loop
          v_dec(v_op) := v_dec(v_op - v_off);
          v_op := v_op + 1;
        end loop;
      end loop;

      check_equal(v_op, exp_len, "Decompressed length mismatch");
      for i in 0 to exp_len - 1 loop
        check_equal(v_dec(i), expected(i), "Decompressed byte mismatch at index " & integer'image(i));
      end loop;
    end procedure;
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
    variable v_exp      : t_byte_arr := (others => (others => '0'));

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      -- Reset DUT before each test case
      aresetn       <= '0';
      s_axis_tvalid <= '0';
      m_axis_tready <= '1';
      capture_reset <= '1';
      wait for 5 * c_clk_period;
      aresetn       <= '1';
      capture_reset <= '0';
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
      -- Test 2: Pure Literals Compression (Non-repeating bytes, 8 B)
      -- ----------------------------------------------------------------------
      elsif run("test_pure_literals") then
        capture_reset <= '1';
        wait until rising_edge(aclk);
        capture_reset <= '0';

        -- Trigger START bit
        axi_write(0, x"00000005"); -- START=1, IRQ_EN=1

        -- Expected raw bytes: 1, 2, 3, 4, 5, 6, 7, 8
        v_exp(0) := x"01"; v_exp(1) := x"02"; v_exp(2) := x"03"; v_exp(3) := x"04";
        v_exp(4) := x"05"; v_exp(5) := x"06"; v_exp(6) := x"07"; v_exp(7) := x"08";

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

        wait for 3 * c_clk_period;

        -- Verify input counter: 8 bytes
        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000008"), "SRC_LEN should record 8 processed input bytes");

        -- Verify output length > 0
        axi_read(12, v_read_val);
        check(to_integer(unsigned(v_read_val)) > 0, "DST_LEN should be non-zero");

        -- Verify cycle counter > 0
        axi_read(16, v_read_val);
        check(to_integer(unsigned(v_read_val)) > 0, "CYCLE_COUNT should record active processing cycles");

        -- Byte-by-byte decompress and verify exact match
        lz4_decompress_and_verify(captured_bytes, captured_count, v_exp, 8);

      -- ----------------------------------------------------------------------
      -- Test 3: Dictionary Match Detection (Repeating 4-byte sequence, 12 B)
      -- ----------------------------------------------------------------------
      elsif run("test_match_compression") then
        capture_reset <= '1';
        wait until rising_edge(aclk);
        capture_reset <= '0';

        axi_write(0, x"00000005"); -- START=1, IRQ_EN=1

        -- Expected 12 bytes: "ABCDABCD1234"
        v_exp(0) := x"41"; v_exp(1) := x"42"; v_exp(2) := x"43"; v_exp(3) := x"44";
        v_exp(4) := x"41"; v_exp(5) := x"42"; v_exp(6) := x"43"; v_exp(7) := x"44";
        v_exp(8) := x"31"; v_exp(9) := x"32"; v_exp(10) := x"33"; v_exp(11) := x"34";

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

        wait for 3 * c_clk_period;

        -- Verify SRC_LEN is 12 bytes
        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"0000000C"), "SRC_LEN should record 12 input bytes");

        -- Verify DST_LEN is recorded
        axi_read(12, v_read_val);
        check(to_integer(unsigned(v_read_val)) > 0, "DST_LEN should reflect compressed sequence bytes");

        -- Byte-by-byte decompress and verify exact match
        lz4_decompress_and_verify(captured_bytes, captured_count, v_exp, 12);

      -- ----------------------------------------------------------------------
      -- Test 4: Pure Literals > 15 Bytes (32 B, exercises literal extension)
      -- ----------------------------------------------------------------------
      elsif run("test_roundtrip_pure_literals_32b") then
        capture_reset <= '1';
        wait until rising_edge(aclk);
        capture_reset <= '0';

        axi_write(0, x"00000005"); -- START=1, IRQ_EN=1

        for i in 0 to 31 loop
          v_exp(i) := std_logic_vector(to_unsigned(i + 1, 8));
        end loop;

        -- Send 8 beats (32 bytes of non-repeating data)
        for i in 0 to 7 loop
          if i = 7 then
            send_beat(std_logic_vector(to_unsigned(i * 4 + 4, 8)) &
                      std_logic_vector(to_unsigned(i * 4 + 3, 8)) &
                      std_logic_vector(to_unsigned(i * 4 + 2, 8)) &
                      std_logic_vector(to_unsigned(i * 4 + 1, 8)), '1');
          else
            send_beat(std_logic_vector(to_unsigned(i * 4 + 4, 8)) &
                      std_logic_vector(to_unsigned(i * 4 + 3, 8)) &
                      std_logic_vector(to_unsigned(i * 4 + 2, 8)) &
                      std_logic_vector(to_unsigned(i * 4 + 1, 8)), '0');
          end if;
        end loop;

        loop
          axi_read(4, v_read_val);
          if v_read_val(1) = '1' then
            exit;
          end if;
          wait for c_clk_period;
        end loop;

        wait for 3 * c_clk_period;

        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000020"), "SRC_LEN should record 32 input bytes");

        -- Byte-by-byte decompress and verify exact match
        lz4_decompress_and_verify(captured_bytes, captured_count, v_exp, 32);

      -- ----------------------------------------------------------------------
      -- Test 5: Mixed Stream with Literals and Multiple Matches (64 B)
      -- ----------------------------------------------------------------------
      elsif run("test_roundtrip_mixed_64b") then
        capture_reset <= '1';
        wait until rising_edge(aclk);
        capture_reset <= '0';

        axi_write(0, x"00000005");

        -- 16 beats = 64 bytes:
        -- Bytes 0..15: Literals 0x01..0x10
        -- Bytes 16..31: Repeating "ABCD" (4 words)
        -- Bytes 32..47: Repeating "ABCD" (4 words, matches at offset 16/4)
        -- Bytes 48..63: Trailing literals 0x20..0x2F
        for i in 0 to 15 loop
          v_exp(i) := std_logic_vector(to_unsigned(i + 1, 8));
        end loop;
        for i in 16 to 47 loop
          case (i mod 4) is
            when 0 => v_exp(i) := x"41";
            when 1 => v_exp(i) := x"42";
            when 2 => v_exp(i) := x"43";
            when others => v_exp(i) := x"44";
          end case;
        end loop;
        for i in 48 to 63 loop
          v_exp(i) := std_logic_vector(to_unsigned(i - 48 + 32, 8));
        end loop;

        for b in 0 to 15 loop
          if b = 15 then
            send_beat(v_exp(b * 4 + 3) & v_exp(b * 4 + 2) & v_exp(b * 4 + 1) & v_exp(b * 4), '1');
          else
            send_beat(v_exp(b * 4 + 3) & v_exp(b * 4 + 2) & v_exp(b * 4 + 1) & v_exp(b * 4), '0');
          end if;
        end loop;

        loop
          axi_read(4, v_read_val);
          if v_read_val(1) = '1' then
            exit;
          end if;
          wait for c_clk_period;
        end loop;

        wait for 3 * c_clk_period;

        axi_read(8, v_read_val);
        check_equal(v_read_val, std_logic_vector'(x"00000040"), "SRC_LEN should record 64 input bytes");

        -- Byte-by-byte decompress and verify exact match
        lz4_decompress_and_verify(captured_bytes, captured_count, v_exp, 64);

      -- ----------------------------------------------------------------------
      -- Test 6: Structured Sequence Compression
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
      -- Test 7: Stream Backpressure (m_axis_tready = '0')
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
      -- Test 8: Soft Reset via CONTROL (bit 1)
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
