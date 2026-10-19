--------------------------------------------------------------------------------
-- Project: High-Performance PS/PL Acceleration on Zynq-7010
-- File:    aes_ctr_engine.vhdl
-- Entity:  aes_ctr_engine
-- Author:  Antigravity AI / Luis H. R. M. C.
-- Standard: VHDL-2008 (IEEE 1076-2008)
--
-- Description:
--   Hardware Cryptographic Coprocessor implementing the Advanced Encryption
--   Standard (AES-128) in Counter Mode (CTR) per NIST FIPS-197 and NIST SP 800-38A.
--
-- Interfaces:
--   - AXI4-Lite Slave (s_axi_lite) at 0x43C20000 for CSRs, Key, and Nonce/IV.
--   - AXI4-Stream Slave (s_axis) for 32-bit streaming plaintext/ciphertext ingress.
--   - AXI4-Stream Master (m_axis) for 32-bit streaming ciphertext/plaintext egress.
--   - External interrupt output (irq_o) for Cortex-A9 GIC.
--
-- Architecture:
--   - Iterative 10-round AES-128 core computing keystream E_K(IV || Counter).
--   - Keystream block (128 bits) is streamed out in 4x 32-bit words, XORed
--     with input data stream on-the-fly.
--   - Counter increments automatically after every 128-bit block.
--   - Designed to hook into standard Xilinx axis_data_fifo in Vivado Block Design.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_ctr_engine is
  generic (
    c_s_axi_addr_width : integer := 12;
    c_s_axi_data_width : integer := 32
  );
  port (
    -- Global Clock and Reset
    aclk           : in  std_logic;
    aresetn        : in  std_logic;

    -- Interrupt Request and Busy Indicators
    irq_o          : out std_logic;
    busy_o         : out std_logic;

    -- AXI4-Lite Slave Interface (Control & Status Registers)
    s_axi_lite_awaddr  : in  std_logic_vector(c_s_axi_addr_width - 1 downto 0);
    s_axi_lite_awvalid : in  std_logic;
    s_axi_lite_awready : out std_logic;
    s_axi_lite_wdata   : in  std_logic_vector(c_s_axi_data_width - 1 downto 0);
    s_axi_lite_wstrb   : in  std_logic_vector((c_s_axi_data_width / 8) - 1 downto 0);
    s_axi_lite_wvalid  : in  std_logic;
    s_axi_lite_wready  : out std_logic;
    s_axi_lite_bresp   : out std_logic_vector(1 downto 0);
    s_axi_lite_bvalid  : out std_logic;
    s_axi_lite_bready  : in  std_logic;
    s_axi_lite_araddr  : in  std_logic_vector(c_s_axi_addr_width - 1 downto 0);
    s_axi_lite_arvalid : in  std_logic;
    s_axi_lite_arready : out std_logic;
    s_axi_lite_rdata   : out std_logic_vector(c_s_axi_data_width - 1 downto 0);
    s_axi_lite_rresp   : out std_logic_vector(1 downto 0);
    s_axi_lite_rvalid  : out std_logic;
    s_axi_lite_rready  : in  std_logic;

    -- AXI4-Stream Slave Interface (Ingress Data)
    s_axis_tdata   : in  std_logic_vector(31 downto 0);
    s_axis_tkeep   : in  std_logic_vector(3 downto 0);
    s_axis_tvalid  : in  std_logic;
    s_axis_tready  : out std_logic;
    s_axis_tlast   : in  std_logic;

    -- AXI4-Stream Master Interface (Egress Data)
    m_axis_tdata   : out std_logic_vector(31 downto 0);
    m_axis_tkeep   : out std_logic_vector(3 downto 0);
    m_axis_tvalid  : out std_logic;
    m_axis_tready  : in  std_logic;
    m_axis_tlast   : out std_logic
  );
end entity aes_ctr_engine;

architecture rtl of aes_ctr_engine is

  -- S-Box ROM (FIPS-197 Standard)
  type sbox_rom_t is array (0 to 255) of std_logic_vector(7 downto 0);
  constant c_sbox : sbox_rom_t := (
    x"63", x"7c", x"77", x"7b", x"f2", x"6b", x"6f", x"c5", x"30", x"01", x"67", x"2b", x"fe", x"d7", x"ab", x"76",
    x"ca", x"82", x"c9", x"7d", x"fa", x"59", x"47", x"f0", x"ad", x"d4", x"a2", x"af", x"9c", x"a4", x"72", x"c0",
    x"b7", x"fd", x"93", x"26", x"36", x"3f", x"f7", x"cc", x"34", x"a5", x"e5", x"f1", x"71", x"d8", x"31", x"15",
    x"04", x"c7", x"23", x"c3", x"18", x"96", x"05", x"9a", x"07", x"12", x"80", x"e2", x"eb", x"27", x"b2", x"75",
    x"09", x"83", x"2c", x"1a", x"1b", x"6e", x"5a", x"a0", x"52", x"3b", x"d6", x"b3", x"29", x"e3", x"2f", x"84",
    x"53", x"d1", x"00", x"ed", x"20", x"fc", x"b1", x"5b", x"6a", x"cb", x"be", x"39", x"4a", x"4c", x"58", x"cf",
    x"d0", x"ef", x"aa", x"fb", x"43", x"4d", x"33", x"85", x"45", x"f9", x"02", x"7f", x"50", x"3c", x"9f", x"a8",
    x"51", x"a3", x"40", x"8f", x"92", x"9d", x"38", x"f5", x"bc", x"b6", x"da", x"21", x"10", x"ff", x"f3", x"d2",
    x"cd", x"0c", x"13", x"ec", x"5f", x"97", x"44", x"17", x"c4", x"a7", x"7e", x"3d", x"64", x"5d", x"19", x"73",
    x"60", x"81", x"4f", x"dc", x"22", x"2a", x"90", x"88", x"46", x"ee", x"b8", x"14", x"de", x"5e", x"0b", x"db",
    x"e0", x"32", x"3a", x"0a", x"49", x"06", x"24", x"5c", x"c2", x"d3", x"ac", x"62", x"91", x"95", x"e4", x"79",
    x"e7", x"c8", x"37", x"6d", x"8d", x"d5", x"4e", x"a9", x"6c", x"56", x"f4", x"ea", x"65", x"7a", x"ae", x"08",
    x"ba", x"78", x"25", x"2e", x"1c", x"a6", x"b4", x"c6", x"e8", x"dd", x"74", x"1f", x"4b", x"bd", x"8b", x"8a",
    x"70", x"3e", x"b5", x"66", x"48", x"03", x"f6", x"0e", x"61", x"35", x"57", x"b9", x"86", x"c1", x"1d", x"9e",
    x"e1", x"f8", x"98", x"11", x"69", x"d9", x"8e", x"94", x"9b", x"1e", x"87", x"e9", x"ce", x"55", x"28", x"df",
    x"8c", x"a1", x"89", x"0d", x"bf", x"e6", x"42", x"68", x"41", x"99", x"2d", x"0f", x"b0", x"54", x"bb", x"16"
  );

  -- Round Constants (Rcon)
  type rcon_t is array (1 to 10) of std_logic_vector(7 downto 0);
  constant c_rcon : rcon_t := (
    x"01", x"02", x"04", x"08", x"10", x"20", x"40", x"80", x"1B", x"36"
  );

  -- Galois Field Multiplications for MixColumns: xtime(b)
  function xtime(b : std_logic_vector(7 downto 0)) return std_logic_vector is
    variable v_res : std_logic_vector(7 downto 0);
  begin
    if b(7) = '1' then
      v_res := (b(6 downto 0) & '0') xor x"1B";
    else
      v_res := (b(6 downto 0) & '0');
    end if;
    return v_res;
  end function xtime;

  -- State byte array types (16 bytes = 128 bits)
  type state_t is array (0 to 15) of std_logic_vector(7 downto 0);
  type round_keys_t is array (0 to 10) of state_t;

  -- Register Map Storage (AXI4-Lite)
  signal reg_control_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_status_r      : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_src_len_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_dst_len_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_cycle_count_r : unsigned(31 downto 0) := (others => '0');

  signal reg_key_0_r       : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_key_1_r       : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_key_2_r       : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_key_3_r       : std_logic_vector(31 downto 0) := (others => '0');

  signal reg_iv_0_r        : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_iv_1_r        : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_iv_2_r        : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_counter_r     : unsigned(31 downto 0) := x"00000001";

  -- Control signals
  signal start_pulse_s     : std_logic := '0';
  signal reset_core_s      : std_logic := '0';
  signal irq_r             : std_logic := '0';

  -- AXI4-Lite Handshake Registers
  signal axi_awready_r : std_logic := '0';
  signal axi_wready_r  : std_logic := '0';
  signal axi_bvalid_r  : std_logic := '0';
  signal axi_arready_r : std_logic := '0';
  signal axi_rvalid_r  : std_logic := '0';
  signal axi_rdata_r   : std_logic_vector(31 downto 0) := (others => '0');

  -- Precomputed Expanded Keys
  signal round_keys_r      : round_keys_t := (others => (others => (others => '0')));

  -- AES Core Datapath Signals
  type fsm_state_t is (
    ST_IDLE,
    ST_EXPAND_KEYS,
    ST_LOAD_CTR,
    ST_ROUND_OP,
    ST_STREAM_XOR,
    ST_NEXT_BLOCK,
    ST_DONE
  );
  signal state_r : fsm_state_t := ST_IDLE;

  signal round_idx_r       : integer range 0 to 10 := 0;
  signal key_exp_round_r   : integer range 1 to 10 := 1;
  signal state_matrix_r    : state_t := (others => (others => '0'));
  signal keystream_r       : state_t := (others => (others => '0'));

  -- Streaming word tracker (4x 32-bit words per 128-bit block)
  signal word_idx_r        : integer range 0 to 3 := 0;
  signal bytes_processed_r : unsigned(31 downto 0) := (others => '0');
  signal cur_counter_r     : unsigned(31 downto 0) := (others => '0');

  -- Intermediate round transformation signals
  signal sub_bytes_s       : state_t;
  signal shift_rows_s      : state_t;
  signal mix_cols_s        : state_t;
  signal round_out_s       : state_t;

begin

  irq_o  <= irq_r;
  busy_o <= reg_status_r(0);

  -- AXI4-Stream Interface (Combinational zero-latency XOR streaming per PG021)
  s_axis_tready <= m_axis_tready when (state_r = ST_STREAM_XOR) else '0';
  m_axis_tvalid <= s_axis_tvalid when (state_r = ST_STREAM_XOR) else '0';
  m_axis_tdata  <= s_axis_tdata xor (keystream_r(4*word_idx_r + 3) &
                                     keystream_r(4*word_idx_r + 2) &
                                     keystream_r(4*word_idx_r + 1) &
                                     keystream_r(4*word_idx_r + 0));
  m_axis_tkeep  <= s_axis_tkeep;
  m_axis_tlast  <= s_axis_tlast;
  s_axi_lite_awready <= axi_awready_r;
  s_axi_lite_wready  <= axi_wready_r;
  s_axi_lite_bresp   <= "00"; -- OKAY
  s_axi_lite_bvalid  <= axi_bvalid_r;
  s_axi_lite_arready <= axi_arready_r;
  s_axi_lite_rdata   <= axi_rdata_r;
  s_axi_lite_rresp   <= "00"; -- OKAY
  s_axi_lite_rvalid  <= axi_rvalid_r;

  p_axi_write : process(aclk)
    variable v_addr : integer;
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        axi_awready_r     <= '0';
        axi_wready_r      <= '0';
        axi_bvalid_r      <= '0';
        reg_control_r     <= (others => '0');
        reg_src_len_r     <= (others => '0');
        reg_key_0_r       <= (others => '0');
        reg_key_1_r       <= (others => '0');
        reg_key_2_r       <= (others => '0');
        reg_key_3_r       <= (others => '0');
        reg_iv_0_r        <= (others => '0');
        reg_iv_1_r        <= (others => '0');
        reg_iv_2_r        <= (others => '0');
        reg_counter_r     <= x"00000001";
        start_pulse_s     <= '0';
        reset_core_s      <= '0';
      else
        start_pulse_s <= '0';
        reset_core_s  <= '0';

        if axi_awready_r = '0' and s_axi_lite_awvalid = '1' and s_axi_lite_wvalid = '1' then
          axi_awready_r <= '1';
          axi_wready_r  <= '1';
        else
          axi_awready_r <= '0';
          axi_wready_r  <= '0';
        end if;

        if axi_awready_r = '1' and s_axi_lite_awvalid = '1' and axi_wready_r = '1' and s_axi_lite_wvalid = '1' then
          axi_bvalid_r <= '1';
          v_addr := to_integer(unsigned(s_axi_lite_awaddr(7 downto 0)));

          case v_addr is
            when 16#00# => -- CONTROL
              reg_control_r <= s_axi_lite_wdata;
              if s_axi_lite_wdata(0) = '1' then
                start_pulse_s <= '1';
              end if;
              if s_axi_lite_wdata(1) = '1' then
                reset_core_s  <= '1';
              end if;
            when 16#08# => -- SRC_LEN
              reg_src_len_r <= s_axi_lite_wdata;
            when 16#14# => -- KEY_0
              reg_key_0_r <= s_axi_lite_wdata;
            when 16#18# => -- KEY_1
              reg_key_1_r <= s_axi_lite_wdata;
            when 16#1C# => -- KEY_2
              reg_key_2_r <= s_axi_lite_wdata;
            when 16#20# => -- KEY_3
              reg_key_3_r <= s_axi_lite_wdata;
            when 16#24# => -- IV_0
              reg_iv_0_r <= s_axi_lite_wdata;
            when 16#28# => -- IV_1
              reg_iv_1_r <= s_axi_lite_wdata;
            when 16#2C# => -- IV_2
              reg_iv_2_r <= s_axi_lite_wdata;
            when 16#30# => -- COUNTER_INIT
              reg_counter_r <= unsigned(s_axi_lite_wdata);
            when others =>
              null;
          end case;
        elsif s_axi_lite_bready = '1' then
          axi_bvalid_r <= '0';
        end if;
      end if;
    end if;
  end process p_axi_write;

  p_axi_read : process(aclk)
    variable v_addr : integer;
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        axi_arready_r <= '0';
        axi_rvalid_r  <= '0';
        axi_rdata_r   <= (others => '0');
      else
        if axi_arready_r = '0' and s_axi_lite_arvalid = '1' then
          axi_arready_r <= '1';
        else
          axi_arready_r <= '0';
        end if;

        if axi_arready_r = '1' and s_axi_lite_arvalid = '1' then
          axi_rvalid_r <= '1';
          v_addr := to_integer(unsigned(s_axi_lite_araddr(7 downto 0)));

          case v_addr is
            when 16#00# => axi_rdata_r <= reg_control_r;
            when 16#04# => axi_rdata_r <= reg_status_r;
            when 16#08# => axi_rdata_r <= reg_src_len_r;
            when 16#0C# => axi_rdata_r <= reg_dst_len_r;
            when 16#10# => axi_rdata_r <= std_logic_vector(reg_cycle_count_r);
            when 16#14# => axi_rdata_r <= reg_key_0_r;
            when 16#18# => axi_rdata_r <= reg_key_1_r;
            when 16#1C# => axi_rdata_r <= reg_key_2_r;
            when 16#20# => axi_rdata_r <= reg_key_3_r;
            when 16#24# => axi_rdata_r <= reg_iv_0_r;
            when 16#28# => axi_rdata_r <= reg_iv_1_r;
            when 16#2C# => axi_rdata_r <= reg_iv_2_r;
            when 16#30# => axi_rdata_r <= std_logic_vector(reg_counter_r);
            when others => axi_rdata_r <= (others => '0');
          end case;
        elsif s_axi_lite_rready = '1' then
          axi_rvalid_r <= '0';
        end if;
      end if;
    end if;
  end process p_axi_read;

  ------------------------------------------------------------------------------
  -- 2. AES-128 Combinational Transformations for Active Round
  ------------------------------------------------------------------------------
  -- SubBytes: 16 parallel S-Box substitutions
  gen_sub_bytes : for i in 0 to 15 generate
    sub_bytes_s(i) <= c_sbox(to_integer(unsigned(state_matrix_r(i))));
  end generate gen_sub_bytes;

  -- ShiftRows: Circular left shift of rows in 4x4 column-major matrix
  -- Row 0: 0, 4,  8, 12 -> 0,  4,  8, 12 (no shift)
  shift_rows_s(0)  <= sub_bytes_s(0);
  shift_rows_s(4)  <= sub_bytes_s(4);
  shift_rows_s(8)  <= sub_bytes_s(8);
  shift_rows_s(12) <= sub_bytes_s(12);

  -- Row 1: 1, 5,  9, 13 -> 5,  9, 13,  1 (shift 1)
  shift_rows_s(1)  <= sub_bytes_s(5);
  shift_rows_s(5)  <= sub_bytes_s(9);
  shift_rows_s(9)  <= sub_bytes_s(13);
  shift_rows_s(13) <= sub_bytes_s(1);

  -- Row 2: 2, 6, 10, 14 -> 10, 14, 2,  6 (shift 2)
  shift_rows_s(2)  <= sub_bytes_s(10);
  shift_rows_s(6)  <= sub_bytes_s(14);
  shift_rows_s(10) <= sub_bytes_s(2);
  shift_rows_s(14) <= sub_bytes_s(6);

  -- Row 3: 3, 7, 11, 15 -> 15, 3,  7, 11 (shift 3)
  shift_rows_s(3)  <= sub_bytes_s(15);
  shift_rows_s(7)  <= sub_bytes_s(3);
  shift_rows_s(11) <= sub_bytes_s(7);
  shift_rows_s(15) <= sub_bytes_s(11);

  -- MixColumns: Galois Field multiplication per column
  gen_mix_cols : for c in 0 to 3 generate
    signal a0, a1, a2, a3 : std_logic_vector(7 downto 0);
  begin
    a0 <= shift_rows_s(4*c + 0);
    a1 <= shift_rows_s(4*c + 1);
    a2 <= shift_rows_s(4*c + 2);
    a3 <= shift_rows_s(4*c + 3);

    mix_cols_s(4*c + 0) <= xtime(a0 xor a1) xor a1 xor a2 xor a3;
    mix_cols_s(4*c + 1) <= xtime(a1 xor a2) xor a2 xor a3 xor a0;
    mix_cols_s(4*c + 2) <= xtime(a2 xor a3) xor a3 xor a0 xor a1;
    mix_cols_s(4*c + 3) <= xtime(a3 xor a0) xor a0 xor a1 xor a2;
  end generate gen_mix_cols;

  -- Select MixColumns for Rounds 1-9, or ShiftRows for Round 10
  gen_round_out : for i in 0 to 15 generate
    round_out_s(i) <= (mix_cols_s(i) xor round_keys_r(round_idx_r)(i)) when round_idx_r < 10 else
                      (shift_rows_s(i) xor round_keys_r(10)(i));
  end generate gen_round_out;

  ------------------------------------------------------------------------------
  -- 3. Core FSM: Key Expansion, Counter Encryption, and Stream XOR
  ------------------------------------------------------------------------------
  p_aes_fsm : process(aclk)
    variable v_rot0 : std_logic_vector(7 downto 0);
    variable v_rot1 : std_logic_vector(7 downto 0);
    variable v_rot2 : std_logic_vector(7 downto 0);
    variable v_rot3 : std_logic_vector(7 downto 0);
    variable v_w0_0 : std_logic_vector(7 downto 0);
    variable v_w0_1 : std_logic_vector(7 downto 0);
    variable v_w0_2 : std_logic_vector(7 downto 0);
    variable v_w0_3 : std_logic_vector(7 downto 0);
    variable v_w1_0 : std_logic_vector(7 downto 0);
    variable v_w1_1 : std_logic_vector(7 downto 0);
    variable v_w1_2 : std_logic_vector(7 downto 0);
    variable v_w1_3 : std_logic_vector(7 downto 0);
    variable v_w2_0 : std_logic_vector(7 downto 0);
    variable v_w2_1 : std_logic_vector(7 downto 0);
    variable v_w2_2 : std_logic_vector(7 downto 0);
    variable v_w2_3 : std_logic_vector(7 downto 0);
    variable v_w3_0 : std_logic_vector(7 downto 0);
    variable v_w3_1 : std_logic_vector(7 downto 0);
    variable v_w3_2 : std_logic_vector(7 downto 0);
    variable v_w3_3 : std_logic_vector(7 downto 0);
  begin
    if rising_edge(aclk) then
      if aresetn = '0' or reset_core_s = '1' then
        state_r           <= ST_IDLE;
        reg_status_r      <= (others => '0');
        reg_dst_len_r     <= (others => '0');
        reg_cycle_count_r <= (others => '0');
        irq_r             <= '0';
        bytes_processed_r <= (others => '0');
        round_idx_r       <= 0;
        key_exp_round_r   <= 1;
      else
        irq_r <= '0';

        case state_r is
          ----------------------------------------------------------------------
          -- IDLE: Wait for start command
          ----------------------------------------------------------------------
          when ST_IDLE =>
            if start_pulse_s = '1' then
              reg_status_r(0)   <= '1'; -- BUSY
              reg_status_r(1)   <= '0'; -- clear DONE
              reg_status_r(2)   <= '0'; -- clear ERR
              reg_cycle_count_r <= (others => '0');
              bytes_processed_r <= (others => '0');
              cur_counter_r     <= reg_counter_r;

              -- Round 0 Key: direct load from 32-bit registers (little-endian byte lanes)
              round_keys_r(0)(0)  <= reg_key_0_r(7 downto 0);
              round_keys_r(0)(1)  <= reg_key_0_r(15 downto 8);
              round_keys_r(0)(2)  <= reg_key_0_r(23 downto 16);
              round_keys_r(0)(3)  <= reg_key_0_r(31 downto 24);

              round_keys_r(0)(4)  <= reg_key_1_r(7 downto 0);
              round_keys_r(0)(5)  <= reg_key_1_r(15 downto 8);
              round_keys_r(0)(6)  <= reg_key_1_r(23 downto 16);
              round_keys_r(0)(7)  <= reg_key_1_r(31 downto 24);

              round_keys_r(0)(8)  <= reg_key_2_r(7 downto 0);
              round_keys_r(0)(9)  <= reg_key_2_r(15 downto 8);
              round_keys_r(0)(10) <= reg_key_2_r(23 downto 16);
              round_keys_r(0)(11) <= reg_key_2_r(31 downto 24);

              round_keys_r(0)(12) <= reg_key_3_r(7 downto 0);
              round_keys_r(0)(13) <= reg_key_3_r(15 downto 8);
              round_keys_r(0)(14) <= reg_key_3_r(23 downto 16);
              round_keys_r(0)(15) <= reg_key_3_r(31 downto 24);

              key_exp_round_r <= 1;
              state_r         <= ST_EXPAND_KEYS;
            end if;

          ----------------------------------------------------------------------
          -- EXPAND_KEYS: Sequentially compute round keys (1 round per cycle)
          ----------------------------------------------------------------------
          when ST_EXPAND_KEYS =>
            reg_cycle_count_r <= reg_cycle_count_r + 1;

            -- RotWord & SubWord on previous round's word 3 (bytes 12..15):
            -- RotWord shifts left: byte 1 -> pos 0, byte 2 -> pos 1, byte 3 -> pos 2, byte 0 -> pos 3
            v_rot0 := c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(13)))) xor c_rcon(key_exp_round_r);
            v_rot1 := c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(14))));
            v_rot2 := c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(15))));
            v_rot3 := c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(12))));

            -- Word 0 of current round
            v_w0_0 := round_keys_r(key_exp_round_r - 1)(0) xor v_rot0;
            v_w0_1 := round_keys_r(key_exp_round_r - 1)(1) xor v_rot1;
            v_w0_2 := round_keys_r(key_exp_round_r - 1)(2) xor v_rot2;
            v_w0_3 := round_keys_r(key_exp_round_r - 1)(3) xor v_rot3;

            -- Word 1 of current round
            v_w1_0 := round_keys_r(key_exp_round_r - 1)(4) xor v_w0_0;
            v_w1_1 := round_keys_r(key_exp_round_r - 1)(5) xor v_w0_1;
            v_w1_2 := round_keys_r(key_exp_round_r - 1)(6) xor v_w0_2;
            v_w1_3 := round_keys_r(key_exp_round_r - 1)(7) xor v_w0_3;

            -- Word 2 of current round
            v_w2_0 := round_keys_r(key_exp_round_r - 1)(8)  xor v_w1_0;
            v_w2_1 := round_keys_r(key_exp_round_r - 1)(9)  xor v_w1_1;
            v_w2_2 := round_keys_r(key_exp_round_r - 1)(10) xor v_w1_2;
            v_w2_3 := round_keys_r(key_exp_round_r - 1)(11) xor v_w1_3;

            -- Word 3 of current round
            v_w3_0 := round_keys_r(key_exp_round_r - 1)(12) xor v_w2_0;
            v_w3_1 := round_keys_r(key_exp_round_r - 1)(13) xor v_w2_1;
            v_w3_2 := round_keys_r(key_exp_round_r - 1)(14) xor v_w2_2;
            v_w3_3 := round_keys_r(key_exp_round_r - 1)(15) xor v_w2_3;

            round_keys_r(key_exp_round_r)(0)  <= v_w0_0;
            round_keys_r(key_exp_round_r)(1)  <= v_w0_1;
            round_keys_r(key_exp_round_r)(2)  <= v_w0_2;
            round_keys_r(key_exp_round_r)(3)  <= v_w0_3;

            round_keys_r(key_exp_round_r)(4)  <= v_w1_0;
            round_keys_r(key_exp_round_r)(5)  <= v_w1_1;
            round_keys_r(key_exp_round_r)(6)  <= v_w1_2;
            round_keys_r(key_exp_round_r)(7)  <= v_w1_3;

            round_keys_r(key_exp_round_r)(8)  <= v_w2_0;
            round_keys_r(key_exp_round_r)(9)  <= v_w2_1;
            round_keys_r(key_exp_round_r)(10) <= v_w2_2;
            round_keys_r(key_exp_round_r)(11) <= v_w2_3;

            round_keys_r(key_exp_round_r)(12) <= v_w3_0;
            round_keys_r(key_exp_round_r)(13) <= v_w3_1;
            round_keys_r(key_exp_round_r)(14) <= v_w3_2;
            round_keys_r(key_exp_round_r)(15) <= v_w3_3;

            if key_exp_round_r = 10 then
              state_r <= ST_LOAD_CTR;
            else
              key_exp_round_r <= key_exp_round_r + 1;
            end if;

          ----------------------------------------------------------------------
          -- LOAD_CTR: Load IV and Counter Block into State Matrix
          ----------------------------------------------------------------------
          when ST_LOAD_CTR =>
            reg_cycle_count_r <= reg_cycle_count_r + 1;

            -- 128-bit Counter Block per NIST SP 800-38A Section F.5.1:
            -- Column 0: IV_0 (bytes 0..3)
            state_matrix_r(0)  <= reg_iv_0_r(7 downto 0)   xor round_keys_r(0)(0);
            state_matrix_r(1)  <= reg_iv_0_r(15 downto 8)  xor round_keys_r(0)(1);
            state_matrix_r(2)  <= reg_iv_0_r(23 downto 16) xor round_keys_r(0)(2);
            state_matrix_r(3)  <= reg_iv_0_r(31 downto 24) xor round_keys_r(0)(3);

            -- Column 1: IV_1 (bytes 4..7)
            state_matrix_r(4)  <= reg_iv_1_r(7 downto 0)   xor round_keys_r(0)(4);
            state_matrix_r(5)  <= reg_iv_1_r(15 downto 8)  xor round_keys_r(0)(5);
            state_matrix_r(6)  <= reg_iv_1_r(23 downto 16) xor round_keys_r(0)(6);
            state_matrix_r(7)  <= reg_iv_1_r(31 downto 24) xor round_keys_r(0)(7);

            -- Column 2: IV_2 (bytes 8..11)
            state_matrix_r(8)  <= reg_iv_2_r(7 downto 0)   xor round_keys_r(0)(8);
            state_matrix_r(9)  <= reg_iv_2_r(15 downto 8)  xor round_keys_r(0)(9);
            state_matrix_r(10) <= reg_iv_2_r(23 downto 16) xor round_keys_r(0)(10);
            state_matrix_r(11) <= reg_iv_2_r(31 downto 24) xor round_keys_r(0)(11);

            -- Column 3: Counter (Big-Endian increment in bytes 12..15)
            state_matrix_r(12) <= std_logic_vector(cur_counter_r(31 downto 24)) xor round_keys_r(0)(12);
            state_matrix_r(13) <= std_logic_vector(cur_counter_r(23 downto 16)) xor round_keys_r(0)(13);
            state_matrix_r(14) <= std_logic_vector(cur_counter_r(15 downto 8))  xor round_keys_r(0)(14);
            state_matrix_r(15) <= std_logic_vector(cur_counter_r(7 downto 0))   xor round_keys_r(0)(15);

            round_idx_r <= 1;
            state_r     <= ST_ROUND_OP;

          ----------------------------------------------------------------------
          -- ROUND_OP: Execute Rounds 1 to 10 iteratively
          ----------------------------------------------------------------------
          when ST_ROUND_OP =>
            reg_cycle_count_r <= reg_cycle_count_r + 1;
            state_matrix_r    <= round_out_s;

            if round_idx_r = 10 then
              keystream_r <= round_out_s;
              word_idx_r  <= 0;
              state_r     <= ST_STREAM_XOR;
            else
              round_idx_r <= round_idx_r + 1;
            end if;

          ----------------------------------------------------------------------
          -- STREAM_XOR: Stream 4x 32-bit Words and XOR with Ingress Data
          ----------------------------------------------------------------------
          when ST_STREAM_XOR =>
            reg_cycle_count_r <= reg_cycle_count_r + 1;

            if s_axis_tvalid = '1' and m_axis_tready = '1' then
              bytes_processed_r <= bytes_processed_r + 4;

              if s_axis_tlast = '1' or (bytes_processed_r + 4 >= unsigned(reg_src_len_r) and unsigned(reg_src_len_r) > 0) then
                state_r <= ST_DONE;
              elsif word_idx_r = 3 then
                state_r <= ST_NEXT_BLOCK;
              else
                word_idx_r <= word_idx_r + 1;
              end if;
            end if;

          ----------------------------------------------------------------------
          -- NEXT_BLOCK: Advance counter and loop back for next 128-bit block
          ----------------------------------------------------------------------
          when ST_NEXT_BLOCK =>
            reg_cycle_count_r <= reg_cycle_count_r + 1;
            cur_counter_r     <= cur_counter_r + 1;
            state_r           <= ST_LOAD_CTR;

          ----------------------------------------------------------------------
          -- DONE: Assert completion and raise interrupt if enabled
          ----------------------------------------------------------------------
          when ST_DONE =>
            reg_status_r(0) <= '0'; -- clear BUSY
            reg_status_r(1) <= '1'; -- set DONE
            reg_dst_len_r   <= std_logic_vector(bytes_processed_r);

            if reg_control_r(2) = '1' then -- IRQ_EN
              irq_r <= '1';
            end if;

            state_r <= ST_IDLE;
        end case;
      end if;
    end if;
  end process p_aes_fsm;

end architecture rtl;
