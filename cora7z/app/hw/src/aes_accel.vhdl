--------------------------------------------------------------------------------
-- Project: High-Performance PS/PL Acceleration on Zynq-7010
-- File:    aes_accel.vhdl
-- Entity:  aes_accel
-- Author:  Antigravity AI / Luis H. R. M. C.
-- Standard: VHDL-2008 (IEEE 1076-2008)
--
-- Description:
--   Hardware Cryptographic Coprocessor implementing AES-128 in Counter Mode (CTR)
--   per NIST FIPS-197 and NIST SP 800-38A, adapted for True Dual-Port BRAM
--   communication with the ARM Cortex-A9 Processing System (ADR-017).
--
-- Interfaces:
--   - AXI4-Lite Slave (s_axi_lite) at 0x43C10000 for CSRs, Key, Nonce, Counter,
--     and hardware cycle telemetry.
--   - True Dual-Port BRAM Port B (bram_in) for reading unencrypted/encrypted data.
--   - True Dual-Port BRAM Port B (bram_out) for writing encrypted/decrypted data.
--   - Hardware cycle counter measuring compute cycles from START to DONE.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_accel is
  generic (
    c_s_axi_addr_width : integer := 12;
    c_s_axi_data_width : integer := 32
  );
  port (
    -- Global Clock and Reset (100 MHz FCLK_CLK1)
    aclk              : in  std_logic;
    aresetn           : in  std_logic;

    -- Interrupt Request and Busy Indicators
    irq_o             : out std_logic;
    busy_o            : out std_logic;

    -- AXI4-Lite Slave Interface (Control & Status Registers)
    s_axi_awaddr      : in  std_logic_vector(c_s_axi_addr_width - 1 downto 0);
    s_axi_awvalid     : in  std_logic;
    s_axi_awready     : out std_logic;
    s_axi_wdata       : in  std_logic_vector(c_s_axi_data_width - 1 downto 0);
    s_axi_wstrb       : in  std_logic_vector((c_s_axi_data_width / 8) - 1 downto 0);
    s_axi_wvalid      : in  std_logic;
    s_axi_wready      : out std_logic;
    s_axi_bresp       : out std_logic_vector(1 downto 0);
    s_axi_bvalid      : out std_logic;
    s_axi_bready      : in  std_logic;
    s_axi_araddr      : in  std_logic_vector(c_s_axi_addr_width - 1 downto 0);
    s_axi_arvalid     : in  std_logic;
    s_axi_arready     : out std_logic;
    s_axi_rdata       : out std_logic_vector(c_s_axi_data_width - 1 downto 0);
    s_axi_rresp       : out std_logic_vector(1 downto 0);
    s_axi_rvalid      : out std_logic;
    s_axi_rready      : in  std_logic;

    -- Native BRAM Input Interface (Port B - Ingress)
    bram_in_en        : out std_logic;
    bram_in_we        : out std_logic_vector(3 downto 0);
    bram_in_addr      : out std_logic_vector(31 downto 0);
    bram_in_din       : out std_logic_vector(31 downto 0);
    bram_in_dout      : in  std_logic_vector(31 downto 0);

    -- Native BRAM Output Interface (Port B - Egress)
    bram_out_en       : out std_logic;
    bram_out_we       : out std_logic_vector(3 downto 0);
    bram_out_addr     : out std_logic_vector(31 downto 0);
    bram_out_din      : out std_logic_vector(31 downto 0);
    bram_out_dout     : in  std_logic_vector(31 downto 0)
  );
end entity aes_accel;

architecture rtl of aes_accel is

  -- Standard AES S-Box Lookup Table (256x8 bits)
  type sbox_t is array (0 to 255) of std_logic_vector(7 downto 0);
  constant c_sbox : sbox_t := (
    x"63", x"7C", x"77", x"7B", x"F2", x"6B", x"6F", x"C5", x"30", x"01", x"67", x"2B", x"FE", x"D7", x"AB", x"76",
    x"CA", x"82", x"C9", x"7D", x"FA", x"59", x"47", x"F0", x"AD", x"D4", x"A2", x"AF", x"9C", x"A4", x"72", x"C0",
    x"B7", x"FD", x"93", x"26", x"36", x"3F", x"F7", x"CC", x"34", x"A5", x"E5", x"F1", x"71", x"D8", x"31", x"15",
    x"04", x"C7", x"23", x"C3", x"18", x"96", x"05", x"9A", x"07", x"12", x"80", x"E2", x"EB", x"27", x"B2", x"75",
    x"09", x"83", x"2C", x"1A", x"1B", x"6E", x"5A", x"A0", x"52", x"3B", x"D6", x"B3", x"29", x"E3", x"2F", x"84",
    x"53", x"D1", x"00", x"ED", x"20", x"FC", x"B1", x"5B", x"6A", x"CB", x"BE", x"39", x"4A", x"4C", x"58", x"CF",
    x"D0", x"EF", x"AA", x"FB", x"43", x"4D", x"33", x"85", x"45", x"F9", x"02", x"7F", x"50", x"3C", x"9F", x"A8",
    x"51", x"A3", x"40", x"8F", x"92", x"9D", x"38", x"F5", x"BC", x"B6", x"DA", x"21", x"10", x"FF", x"F3", x"D2",
    x"CD", x"0C", x"13", x"EC", x"5F", x"97", x"44", x"17", x"C4", x"A7", x"7E", x"3D", x"64", x"5D", x"19", x"73",
    x"60", x"81", x"4F", x"DC", x"22", x"2A", x"90", x"88", x"46", x"EE", x"B8", x"14", x"DE", x"5E", x"0B", x"DB",
    x"E0", x"32", x"3A", x"0A", x"49", x"06", x"24", x"5C", x"C2", x"D3", x"AC", x"62", x"91", x"95", x"E4", x"79",
    x"E7", x"C8", x"37", x"6D", x"8D", x"D5", x"4E", x"A9", x"6C", x"56", x"F4", x"EA", x"65", x"7A", x"AE", x"08",
    x"BA", x"78", x"25", x"2E", x"1C", x"A6", x"B4", x"C6", x"E8", x"DD", x"74", x"1F", x"4B", x"BD", x"8B", x"8A",
    x"70", x"3E", x"B5", x"66", x"48", x"03", x"F6", x"0E", x"61", x"35", x"57", x"B9", x"86", x"C1", x"1D", x"9E",
    x"E1", x"F8", x"98", x"11", x"69", x"D9", x"8E", x"94", x"9B", x"1E", x"87", x"E9", x"CE", x"55", x"28", x"DF",
    x"8C", x"A1", x"89", x"0D", x"BF", x"E6", x"42", x"68", x"41", x"99", x"2D", x"0F", x"B0", x"54", x"BB", x"16"
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

  -- AES Core Datapath FSM States
  type fsm_state_t is (
    ST_IDLE,
    ST_EXPAND_KEYS,
    ST_LOAD_CTR,
    ST_ROUND_OP,
    ST_FETCH_REQ,
    ST_FETCH_WAIT,
    ST_WRITE_WORD,
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

begin

  -- Constant outputs and status indicators
  irq_o  <= irq_r;
  busy_o <= reg_status_r(0);

  bram_in_din <= (others => '0');
  bram_in_we  <= (others => '0');

  ------------------------------------------------------------------------------
  -- 1. AXI4-Lite Write Channel FSM
  ------------------------------------------------------------------------------
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

        if axi_bvalid_r = '1' and s_axi_bready = '1' then
          axi_bvalid_r <= '0';
        end if;

        if axi_awready_r = '0' and axi_wready_r = '0' then
          if s_axi_awvalid = '1' and s_axi_wvalid = '1' then
            axi_awready_r <= '1';
            axi_wready_r  <= '1';
            axi_bvalid_r  <= '1';

            v_addr := to_integer(unsigned(s_axi_awaddr(7 downto 0)));
            case v_addr is
              when 16#00# => -- CONTROL
                reg_control_r <= s_axi_wdata;
                if s_axi_wdata(0) = '1' then
                  start_pulse_s <= '1';
                end if;
                if s_axi_wdata(1) = '1' then
                  reset_core_s <= '1';
                end if;
              when 16#08# => -- SRC_LEN
                reg_src_len_r <= s_axi_wdata;
              when 16#14# => -- KEY_0
                reg_key_0_r <= s_axi_wdata;
              when 16#18# => -- KEY_1
                reg_key_1_r <= s_axi_wdata;
              when 16#1C# => -- KEY_2
                reg_key_2_r <= s_axi_wdata;
              when 16#20# => -- KEY_3
                reg_key_3_r <= s_axi_wdata;
              when 16#24# => -- IV_0
                reg_iv_0_r <= s_axi_wdata;
              when 16#28# => -- IV_1
                reg_iv_1_r <= s_axi_wdata;
              when 16#2C# => -- IV_2
                reg_iv_2_r <= s_axi_wdata;
              when 16#30# => -- COUNTER_INIT
                reg_counter_r <= unsigned(s_axi_wdata);
              when others =>
                null;
            end case;
          end if;
        else
          axi_awready_r <= '0';
          axi_wready_r  <= '0';
        end if;
      end if;
    end if;
  end process p_axi_write;

  s_axi_awready <= axi_awready_r;
  s_axi_wready  <= axi_wready_r;
  s_axi_bvalid  <= axi_bvalid_r;
  s_axi_bresp   <= "00"; -- OKAY

  ------------------------------------------------------------------------------
  -- 2. AXI4-Lite Read Channel FSM
  ------------------------------------------------------------------------------
  p_axi_read : process(aclk)
    variable v_addr : integer;
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        axi_arready_r <= '0';
        axi_rvalid_r  <= '0';
        axi_rdata_r   <= (others => '0');
      else
        if axi_rvalid_r = '1' and s_axi_rready = '1' then
          axi_rvalid_r <= '0';
        end if;

        if axi_arready_r = '0' and s_axi_arvalid = '1' then
          axi_arready_r <= '1';
          axi_rvalid_r  <= '1';

          v_addr := to_integer(unsigned(s_axi_araddr(7 downto 0)));
          case v_addr is
            when 16#00# => -- CONTROL
              axi_rdata_r <= reg_control_r;
            when 16#04# => -- STATUS
              axi_rdata_r <= reg_status_r;
            when 16#08# => -- SRC_LEN
              axi_rdata_r <= reg_src_len_r;
            when 16#0C# => -- DST_LEN
              axi_rdata_r <= reg_dst_len_r;
            when 16#10# => -- CYCLE_COUNT
              axi_rdata_r <= std_logic_vector(reg_cycle_count_r);
            when 16#14# => -- KEY_0
              axi_rdata_r <= reg_key_0_r;
            when 16#18# => -- KEY_1
              axi_rdata_r <= reg_key_1_r;
            when 16#1C# => -- KEY_2
              axi_rdata_r <= reg_key_2_r;
            when 16#20# => -- KEY_3
              axi_rdata_r <= reg_key_3_r;
            when 16#24# => -- IV_0
              axi_rdata_r <= reg_iv_0_r;
            when 16#28# => -- IV_1
              axi_rdata_r <= reg_iv_1_r;
            when 16#2C# => -- IV_2
              axi_rdata_r <= reg_iv_2_r;
            when 16#30# => -- COUNTER_INIT
              axi_rdata_r <= std_logic_vector(reg_counter_r);
            when others =>
              axi_rdata_r <= (others => '0');
          end case;
        else
          axi_arready_r <= '0';
        end if;
      end if;
    end if;
  end process p_axi_read;

  s_axi_arready <= axi_arready_r;
  s_axi_rvalid  <= axi_rvalid_r;
  s_axi_rdata   <= axi_rdata_r;
  s_axi_rresp   <= "00"; -- OKAY

  ------------------------------------------------------------------------------
  -- 3. AES Round Transformations (Combinational Datapath)
  ------------------------------------------------------------------------------
  -- SubBytes: Non-linear byte substitution via standard S-Box
  gen_sub_bytes: for i in 0 to 15 generate
    sub_bytes_s(i) <= c_sbox(to_integer(unsigned(state_matrix_r(i))));
  end generate gen_sub_bytes;

  -- ShiftRows: Cyclically shift rows of state matrix
  shift_rows_s(0)  <= sub_bytes_s(0);
  shift_rows_s(4)  <= sub_bytes_s(4);
  shift_rows_s(8)  <= sub_bytes_s(8);
  shift_rows_s(12) <= sub_bytes_s(12);

  shift_rows_s(1)  <= sub_bytes_s(5);
  shift_rows_s(5)  <= sub_bytes_s(9);
  shift_rows_s(9)  <= sub_bytes_s(13);
  shift_rows_s(13) <= sub_bytes_s(1);

  shift_rows_s(2)  <= sub_bytes_s(10);
  shift_rows_s(6)  <= sub_bytes_s(14);
  shift_rows_s(10) <= sub_bytes_s(2);
  shift_rows_s(14) <= sub_bytes_s(6);

  shift_rows_s(3)  <= sub_bytes_s(15);
  shift_rows_s(7)  <= sub_bytes_s(3);
  shift_rows_s(11) <= sub_bytes_s(7);
  shift_rows_s(15) <= sub_bytes_s(11);

  -- MixColumns: Linear transformation over GF(2^8)
  gen_mix_cols: for c in 0 to 3 generate
    mix_cols_s(4*c + 0) <= xtime(shift_rows_s(4*c + 0)) xor
                           xtime(shift_rows_s(4*c + 1)) xor shift_rows_s(4*c + 1) xor
                           shift_rows_s(4*c + 2) xor
                           shift_rows_s(4*c + 3);

    mix_cols_s(4*c + 1) <= shift_rows_s(4*c + 0) xor
                           xtime(shift_rows_s(4*c + 1)) xor
                           xtime(shift_rows_s(4*c + 2)) xor shift_rows_s(4*c + 2) xor
                           shift_rows_s(4*c + 3);

    mix_cols_s(4*c + 2) <= shift_rows_s(4*c + 0) xor
                           shift_rows_s(4*c + 1) xor
                           xtime(shift_rows_s(4*c + 2)) xor
                           xtime(shift_rows_s(4*c + 3)) xor shift_rows_s(4*c + 3);

    mix_cols_s(4*c + 3) <= xtime(shift_rows_s(4*c + 0)) xor shift_rows_s(4*c + 0) xor
                           shift_rows_s(4*c + 1) xor
                           shift_rows_s(4*c + 2) xor
                           xtime(shift_rows_s(4*c + 3));
  end generate gen_mix_cols;

  ------------------------------------------------------------------------------
  -- 4. Main FSM & Dual-Port BRAM Execution Datapath
  ------------------------------------------------------------------------------
  p_main_fsm : process(aclk)
    variable v_ctr_block      : state_t;
    variable v_xor_data       : std_logic_vector(31 downto 0);
    variable v_keystream_word : std_logic_vector(31 downto 0);
    variable v_rem_bytes      : unsigned(31 downto 0);
    variable v_temp_w         : state_t;
    variable v_sub_w          : std_logic_vector(7 downto 0);
  begin
    if rising_edge(aclk) then
      if aresetn = '0' or reset_core_s = '1' then
        state_r           <= ST_IDLE;
        reg_status_r      <= (others => '0');
        reg_dst_len_r     <= (others => '0');
        reg_cycle_count_r <= (others => '0');
        irq_r             <= '0';
        round_idx_r       <= 0;
        key_exp_round_r   <= 1;
        word_idx_r        <= 0;
        bytes_processed_r <= (others => '0');
        cur_counter_r     <= (others => '0');
        bram_in_en        <= '0';
        bram_in_addr      <= (others => '0');
        bram_out_en       <= '0';
        bram_out_we       <= (others => '0');
        bram_out_addr     <= (others => '0');
        bram_out_din      <= (others => '0');
      else
        -- Default BRAM control pulses
        bram_in_en  <= '0';
        bram_out_en <= '0';
        bram_out_we <= (others => '0');

        -- Hardware cycle counter increments while active
        if state_r /= ST_IDLE and state_r /= ST_DONE then
          reg_cycle_count_r <= reg_cycle_count_r + 1;
        end if;

        case state_r is

          ----------------------------------------------------------------------
          -- ST_IDLE: Awaiting Start Command from Processing System
          ----------------------------------------------------------------------
          when ST_IDLE =>
            irq_r <= '0';
            if start_pulse_s = '1' then
              reg_status_r(0)   <= '1'; -- BUSY = 1
              reg_status_r(1)   <= '0'; -- DONE = 0
              reg_status_r(2)   <= '0'; -- ERR = 0
              reg_cycle_count_r <= (others => '0');
              bytes_processed_r <= (others => '0');
              cur_counter_r     <= reg_counter_r;
              reg_dst_len_r     <= reg_src_len_r; -- In CTR mode, DST_LEN == SRC_LEN

              -- Load initial 128-bit User Key into Round Key 0
              -- Big-endian word to byte column mapping per FIPS-197
              round_keys_r(0)(0)  <= reg_key_0_r(31 downto 24);
              round_keys_r(0)(1)  <= reg_key_0_r(23 downto 16);
              round_keys_r(0)(2)  <= reg_key_0_r(15 downto 8);
              round_keys_r(0)(3)  <= reg_key_0_r(7 downto 0);

              round_keys_r(0)(4)  <= reg_key_1_r(31 downto 24);
              round_keys_r(0)(5)  <= reg_key_1_r(23 downto 16);
              round_keys_r(0)(6)  <= reg_key_1_r(15 downto 8);
              round_keys_r(0)(7)  <= reg_key_1_r(7 downto 0);

              round_keys_r(0)(8)  <= reg_key_2_r(31 downto 24);
              round_keys_r(0)(9)  <= reg_key_2_r(23 downto 16);
              round_keys_r(0)(10) <= reg_key_2_r(15 downto 8);
              round_keys_r(0)(11) <= reg_key_2_r(7 downto 0);

              round_keys_r(0)(12) <= reg_key_3_r(31 downto 24);
              round_keys_r(0)(13) <= reg_key_3_r(23 downto 16);
              round_keys_r(0)(14) <= reg_key_3_r(15 downto 8);
              round_keys_r(0)(15) <= reg_key_3_r(7 downto 0);

              if unsigned(reg_src_len_r) = 0 then
                state_r <= ST_DONE;
              else
                key_exp_round_r <= 1;
                state_r         <= ST_EXPAND_KEYS;
              end if;
            end if;

          ----------------------------------------------------------------------
          -- ST_EXPAND_KEYS: 10-cycle pipelined AES-128 Key Expansion Schedule
          ----------------------------------------------------------------------
          when ST_EXPAND_KEYS =>
            -- RotWord & SubWord on round_keys_r(r-1)(12..15)
            v_sub_w := c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(13)))) xor c_rcon(key_exp_round_r);
            round_keys_r(key_exp_round_r)(0) <= round_keys_r(key_exp_round_r - 1)(0) xor v_sub_w;
            round_keys_r(key_exp_round_r)(1) <= round_keys_r(key_exp_round_r - 1)(1) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(14))));
            round_keys_r(key_exp_round_r)(2) <= round_keys_r(key_exp_round_r - 1)(2) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(15))));
            round_keys_r(key_exp_round_r)(3) <= round_keys_r(key_exp_round_r - 1)(3) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(12))));

            -- Column 1
            round_keys_r(key_exp_round_r)(4) <= round_keys_r(key_exp_round_r - 1)(4) xor round_keys_r(key_exp_round_r - 1)(0) xor v_sub_w;
            round_keys_r(key_exp_round_r)(5) <= round_keys_r(key_exp_round_r - 1)(5) xor round_keys_r(key_exp_round_r - 1)(1) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(14))));
            round_keys_r(key_exp_round_r)(6) <= round_keys_r(key_exp_round_r - 1)(6) xor round_keys_r(key_exp_round_r - 1)(2) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(15))));
            round_keys_r(key_exp_round_r)(7) <= round_keys_r(key_exp_round_r - 1)(7) xor round_keys_r(key_exp_round_r - 1)(3) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(12))));

            -- Column 2
            round_keys_r(key_exp_round_r)(8)  <= round_keys_r(key_exp_round_r - 1)(8)  xor round_keys_r(key_exp_round_r - 1)(4) xor round_keys_r(key_exp_round_r - 1)(0) xor v_sub_w;
            round_keys_r(key_exp_round_r)(9)  <= round_keys_r(key_exp_round_r - 1)(9)  xor round_keys_r(key_exp_round_r - 1)(5) xor round_keys_r(key_exp_round_r - 1)(1) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(14))));
            round_keys_r(key_exp_round_r)(10) <= round_keys_r(key_exp_round_r - 1)(10) xor round_keys_r(key_exp_round_r - 1)(6) xor round_keys_r(key_exp_round_r - 1)(2) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(15))));
            round_keys_r(key_exp_round_r)(11) <= round_keys_r(key_exp_round_r - 1)(11) xor round_keys_r(key_exp_round_r - 1)(7) xor round_keys_r(key_exp_round_r - 1)(3) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(12))));

            -- Column 3
            round_keys_r(key_exp_round_r)(12) <= round_keys_r(key_exp_round_r - 1)(12) xor round_keys_r(key_exp_round_r - 1)(8)  xor round_keys_r(key_exp_round_r - 1)(4) xor round_keys_r(key_exp_round_r - 1)(0) xor v_sub_w;
            round_keys_r(key_exp_round_r)(13) <= round_keys_r(key_exp_round_r - 1)(13) xor round_keys_r(key_exp_round_r - 1)(9)  xor round_keys_r(key_exp_round_r - 1)(5) xor round_keys_r(key_exp_round_r - 1)(1) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(14))));
            round_keys_r(key_exp_round_r)(14) <= round_keys_r(key_exp_round_r - 1)(14) xor round_keys_r(key_exp_round_r - 1)(10) xor round_keys_r(key_exp_round_r - 1)(6) xor round_keys_r(key_exp_round_r - 1)(2) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(15))));
            round_keys_r(key_exp_round_r)(15) <= round_keys_r(key_exp_round_r - 1)(15) xor round_keys_r(key_exp_round_r - 1)(11) xor round_keys_r(key_exp_round_r - 1)(7) xor round_keys_r(key_exp_round_r - 1)(3) xor c_sbox(to_integer(unsigned(round_keys_r(key_exp_round_r - 1)(12))));

            if key_exp_round_r = 10 then
              state_r <= ST_LOAD_CTR;
            else
              key_exp_round_r <= key_exp_round_r + 1;
            end if;

          ----------------------------------------------------------------------
          -- ST_LOAD_CTR: Construct Counter Block [IV (96-bit) || CTR (32-bit)]
          ----------------------------------------------------------------------
          when ST_LOAD_CTR =>
            -- Bytes 0..3: IV_0
            v_ctr_block(0) := reg_iv_0_r(31 downto 24);
            v_ctr_block(1) := reg_iv_0_r(23 downto 16);
            v_ctr_block(2) := reg_iv_0_r(15 downto 8);
            v_ctr_block(3) := reg_iv_0_r(7 downto 0);

            -- Bytes 4..7: IV_1
            v_ctr_block(4) := reg_iv_1_r(31 downto 24);
            v_ctr_block(5) := reg_iv_1_r(23 downto 16);
            v_ctr_block(6) := reg_iv_1_r(15 downto 8);
            v_ctr_block(7) := reg_iv_1_r(7 downto 0);

            -- Bytes 8..11: IV_2
            v_ctr_block(8)  := reg_iv_2_r(31 downto 24);
            v_ctr_block(9)  := reg_iv_2_r(23 downto 16);
            v_ctr_block(10) := reg_iv_2_r(15 downto 8);
            v_ctr_block(11) := reg_iv_2_r(7 downto 0);

            -- Bytes 12..15: 32-bit Big-Endian Counter (NIST SP 800-38A standard)
            v_ctr_block(12) := std_logic_vector(cur_counter_r(31 downto 24));
            v_ctr_block(13) := std_logic_vector(cur_counter_r(23 downto 16));
            v_ctr_block(14) := std_logic_vector(cur_counter_r(15 downto 8));
            v_ctr_block(15) := std_logic_vector(cur_counter_r(7 downto 0));

            -- Round 0: AddRoundKey
            for i in 0 to 15 loop
              state_matrix_r(i) <= v_ctr_block(i) xor round_keys_r(0)(i);
            end loop;

            round_idx_r <= 1;
            state_r     <= ST_ROUND_OP;

          ----------------------------------------------------------------------
          -- ST_ROUND_OP: Iterative AES Rounds 1 to 10
          ----------------------------------------------------------------------
          when ST_ROUND_OP =>
            if round_idx_r < 10 then
              -- Rounds 1..9: SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
              for i in 0 to 15 loop
                state_matrix_r(i) <= mix_cols_s(i) xor round_keys_r(round_idx_r)(i);
              end loop;
              round_idx_r <= round_idx_r + 1;
            else
              -- Round 10: SubBytes -> ShiftRows -> AddRoundKey (No MixColumns)
              for i in 0 to 15 loop
                keystream_r(i) <= shift_rows_s(i) xor round_keys_r(10)(i);
              end loop;
              word_idx_r <= 0;
              state_r    <= ST_FETCH_REQ;
            end if;

          ----------------------------------------------------------------------
          -- ST_FETCH_REQ: Request 32-bit Word from Input BRAM (Port B)
          ----------------------------------------------------------------------
          when ST_FETCH_REQ =>
            if bytes_processed_r + to_unsigned(word_idx_r * 4, 32) < unsigned(reg_src_len_r) then
              bram_in_addr <= std_logic_vector(bytes_processed_r + to_unsigned(word_idx_r * 4, 32));
              bram_in_en   <= '1';
              state_r      <= ST_FETCH_WAIT;
            else
              -- Entire input stream processed
              state_r <= ST_DONE;
            end if;

          ----------------------------------------------------------------------
          -- ST_FETCH_WAIT: 1-Cycle Synchronous BRAM Read Latency
          ----------------------------------------------------------------------
          when ST_FETCH_WAIT =>
            state_r <= ST_WRITE_WORD;

          ----------------------------------------------------------------------
          -- ST_WRITE_WORD: XOR Keystream with Ingress Data and Write to Output BRAM
          ----------------------------------------------------------------------
          when ST_WRITE_WORD =>
            -- Map 4 bytes of keystream into 32-bit word matching Cortex-A9 byte order
            v_keystream_word(7 downto 0)   := keystream_r(word_idx_r * 4 + 0);
            v_keystream_word(15 downto 8)  := keystream_r(word_idx_r * 4 + 1);
            v_keystream_word(23 downto 16) := keystream_r(word_idx_r * 4 + 2);
            v_keystream_word(31 downto 24) := keystream_r(word_idx_r * 4 + 3);

            v_xor_data := bram_in_dout xor v_keystream_word;

            -- Calculate remaining byte count to assign byte write enable mask
            v_rem_bytes := unsigned(reg_src_len_r) - (bytes_processed_r + to_unsigned(word_idx_r * 4, 32));

            bram_out_addr <= std_logic_vector(bytes_processed_r + to_unsigned(word_idx_r * 4, 32));
            bram_out_din  <= v_xor_data;
            bram_out_en   <= '1';

            if v_rem_bytes >= 4 then
              bram_out_we <= "1111";
            elsif v_rem_bytes = 3 then
              bram_out_we <= "0111";
            elsif v_rem_bytes = 2 then
              bram_out_we <= "0011";
            else
              bram_out_we <= "0001";
            end if;

            if v_rem_bytes <= 4 then
              -- Last word of the entire buffer processed
              bytes_processed_r <= unsigned(reg_src_len_r);
              state_r           <= ST_DONE;
            elsif word_idx_r < 3 then
              word_idx_r <= word_idx_r + 1;
              state_r    <= ST_FETCH_REQ;
            else
              -- 128-bit block complete; increment block counter and start next
              bytes_processed_r <= bytes_processed_r + 16;
              cur_counter_r     <= cur_counter_r + 1;
              state_r           <= ST_LOAD_CTR;
            end if;

          ----------------------------------------------------------------------
          -- ST_DONE: Signal Completion and Assert Interrupt
          ----------------------------------------------------------------------
          when ST_DONE =>
            reg_status_r(0) <= '0'; -- BUSY = 0
            reg_status_r(1) <= '1'; -- DONE = 1
            if reg_control_r(2) = '1' then
              irq_r <= '1';
            end if;
            state_r <= ST_IDLE;

          when others =>
            state_r <= ST_IDLE;

        end case;
      end if;
    end if;
  end process p_main_fsm;

end architecture rtl;
