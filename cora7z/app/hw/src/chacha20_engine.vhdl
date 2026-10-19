--------------------------------------------------------------------------------
-- Project: High-Performance PS/PL Acceleration on Zynq-7010
-- File:    chacha20_engine.vhdl
-- Entity:  chacha20_engine
-- Author:  Antigravity AI / Luis H. R. M. C.
-- Standard: VHDL-2008 (IEEE 1076-2008)
--
-- Description:
--   Hardware Cryptographic Stream Cipher Coprocessor implementing ChaCha20
--   per IETF RFC 8439.
--
-- Interfaces:
--   - AXI4-Lite Slave (s_axi_lite) at 0x43C30000 for CSRs, 256-bit Key,
--     96-bit Nonce/IV, and Block Counter.
--   - AXI4-Stream Slave (s_axis) for 32-bit streaming plaintext/ciphertext ingress.
--   - AXI4-Stream Master (m_axis) for 32-bit streaming ciphertext/plaintext egress.
--   - External interrupt output (irq_o) for Cortex-A9 GIC.
--
-- Architecture:
--   - 512-bit working state (16 words of 32 bits).
--   - 4 parallel Quarter-Round (QR) ALUs performing column and diagonal rounds.
--   - 20 rounds (10 double-rounds) computed in 20 clock cycles.
--   - Keystream addition modulo 2^32 produces 64 bytes (16 words) per block.
--   - Automatic counter increment for multi-block stream encryption.
--   - Full AXI4-Stream backpressure handling with zero-latency XOR datapath.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity chacha20_engine is
  generic (
    c_s_axi_addr_width : integer := 12;
    c_s_axi_data_width : integer := 32
  );
  port (
    -- Global Clock and Reset
    aclk           : in  std_logic;
    aresetn        : in  std_logic;

    -- Interrupt Request (Active-High)
    irq_o          : out std_logic;

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
end entity chacha20_engine;

architecture rtl of chacha20_engine is

  -- Constant state parameters (RFC 8439: "expand 32-byte k")
  constant c_const_0 : unsigned(31 downto 0) := x"61707865"; -- "expa"
  constant c_const_1 : unsigned(31 downto 0) := x"3320646e"; -- "nd 3"
  constant c_const_2 : unsigned(31 downto 0) := x"79622d32"; -- "2-by"
  constant c_const_3 : unsigned(31 downto 0) := x"6b206574"; -- "te k"

  -- State array types
  type state_t is array (0 to 15) of unsigned(31 downto 0);
  type key_array_t is array (0 to 7) of unsigned(31 downto 0);
  type nonce_array_t is array (0 to 2) of unsigned(31 downto 0);

  type qr_out_t is record
    a : unsigned(31 downto 0);
    b : unsigned(31 downto 0);
    c : unsigned(31 downto 0);
    d : unsigned(31 downto 0);
  end record qr_out_t;

  -- Left rotation helper function
  function rotl16(x : unsigned(31 downto 0)) return unsigned is
  begin
    return x(15 downto 0) & x(31 downto 16);
  end function rotl16;

  function rotl12(x : unsigned(31 downto 0)) return unsigned is
  begin
    return x(19 downto 0) & x(31 downto 20);
  end function rotl12;

  function rotl8(x : unsigned(31 downto 0)) return unsigned is
  begin
    return x(23 downto 0) & x(31 downto 24);
  end function rotl8;

  function rotl7(x : unsigned(31 downto 0)) return unsigned is
  begin
    return x(24 downto 0) & x(31 downto 25);
  end function rotl7;

  -- Quarter-Round transformation
  function chacha_qr(
    a_in : unsigned(31 downto 0);
    b_in : unsigned(31 downto 0);
    c_in : unsigned(31 downto 0);
    d_in : unsigned(31 downto 0)
  ) return qr_out_t is
    variable v_a : unsigned(31 downto 0);
    variable v_b : unsigned(31 downto 0);
    variable v_c : unsigned(31 downto 0);
    variable v_d : unsigned(31 downto 0);
    variable res : qr_out_t;
  begin
    -- Step 1
    v_a := a_in + b_in;
    v_d := rotl16(d_in xor v_a);
    -- Step 2
    v_c := c_in + v_d;
    v_b := rotl12(b_in xor v_c);
    -- Step 3
    v_a := v_a + v_b;
    v_d := rotl8(v_d xor v_a);
    -- Step 4
    v_c := v_c + v_d;
    v_b := rotl7(v_b xor v_c);

    res.a := v_a;
    res.b := v_b;
    res.c := v_c;
    res.d := v_d;
    return res;
  end function chacha_qr;

  -- FSM States
  type fsm_state_t is (
    S_IDLE,
    S_LOAD_STATE,
    S_ROUNDS,
    S_ADD_STATE,
    S_STREAM,
    S_DONE
  );

  signal fsm_state_r : fsm_state_t;

  -- CSR Storage
  signal control_start_r     : std_logic;
  signal control_reset_r     : std_logic;
  signal control_irq_en_r    : std_logic;
  signal status_busy_r       : std_logic;
  signal status_done_r       : std_logic;
  signal status_err_r        : std_logic;
  signal src_len_r           : unsigned(31 downto 0);
  signal dst_len_r           : unsigned(31 downto 0);
  signal cycle_count_r       : unsigned(31 downto 0);

  signal key_r               : key_array_t;
  signal nonce_r             : nonce_array_t;
  signal block_counter_init_r: unsigned(31 downto 0);
  signal current_counter_r   : unsigned(31 downto 0);

  -- Internal Datapath Registers
  signal state_init_r        : state_t;
  signal state_work_r        : state_t;
  signal keystream_r         : state_t;
  signal round_cnt_r         : integer range 0 to 20;
  signal word_idx_r          : integer range 0 to 15;
  signal bytes_processed_r   : unsigned(31 downto 0);

  -- AXI4-Lite Handshake Registers
  signal axi_awready_r       : std_logic;
  signal axi_wready_r        : std_logic;
  signal axi_bvalid_r        : std_logic;
  signal axi_arready_r       : std_logic;
  signal axi_rvalid_r        : std_logic;
  signal axi_rdata_r         : std_logic_vector(31 downto 0);
  signal axi_awaddr_r        : std_logic_vector(c_s_axi_addr_width - 1 downto 0);
  signal axi_awdone_r        : std_logic;

  -- Interrupt generator
  signal irq_pulse_r         : std_logic;

begin

  irq_o <= irq_pulse_r;

  -- AXI4-Stream Interface (Combinational zero-latency XOR streaming)
  s_axis_tready <= m_axis_tready when (fsm_state_r = S_STREAM) else '0';
  m_axis_tvalid <= s_axis_tvalid when (fsm_state_r = S_STREAM) else '0';
  m_axis_tdata  <= s_axis_tdata xor std_logic_vector(keystream_r(word_idx_r));
  m_axis_tkeep  <= s_axis_tkeep;
  m_axis_tlast  <= s_axis_tlast;

  ------------------------------------------------------------------------------
  -- 1. AXI4-Lite Write & Read Channel Logic
  ------------------------------------------------------------------------------
  s_axi_lite_awready <= axi_awready_r;
  s_axi_lite_wready  <= axi_wready_r;
  s_axi_lite_bresp   <= "00"; -- OKAY
  s_axi_lite_bvalid  <= axi_bvalid_r;

  s_axi_lite_arready <= axi_arready_r;
  s_axi_lite_rresp   <= "00"; -- OKAY
  s_axi_lite_rvalid  <= axi_rvalid_r;
  s_axi_lite_rdata   <= axi_rdata_r;

  p_axi_write : process(aclk)
    variable v_addr : integer range 0 to 4095;
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        axi_awready_r        <= '0';
        axi_wready_r         <= '0';
        axi_bvalid_r         <= '0';
        axi_awdone_r         <= '0';
        axi_awaddr_r         <= (others => '0');
        control_start_r      <= '0';
        control_reset_r      <= '0';
        control_irq_en_r     <= '0';
        src_len_r            <= (others => '0');
        key_r                <= (others => (others => '0'));
        nonce_r              <= (others => (others => '0'));
        block_counter_init_r <= to_unsigned(1, 32);
      else
        -- Default self-clearing strobe
        control_start_r <= '0';
        control_reset_r <= '0';

        -- Address handshake
        if (s_axi_lite_awvalid = '1' and axi_awready_r = '1') then
          axi_awaddr_r <= s_axi_lite_awaddr;
          axi_awdone_r <= '1';
          axi_awready_r <= '0';
        elsif (axi_bvalid_r = '1' and s_axi_lite_bready = '1') then
          axi_awdone_r <= '0';
        end if;

        if (s_axi_lite_awvalid = '1' and axi_awready_r = '0' and axi_awdone_r = '0') then
          axi_awready_r <= '1';
        else
          axi_awready_r <= '0';
        end if;

        -- Data handshake
        if (s_axi_lite_wvalid = '1' and axi_wready_r = '0' and (axi_awdone_r = '1' or s_axi_lite_awvalid = '1')) then
          axi_wready_r <= '1';
        else
          axi_wready_r <= '0';
        end if;

        -- Write transaction completion
        if (axi_wready_r = '1' and s_axi_lite_wvalid = '1') then
          axi_bvalid_r <= '1';
          if axi_awdone_r = '1' then
            v_addr := to_integer(unsigned(axi_awaddr_r(11 downto 0)));
          else
            v_addr := to_integer(unsigned(s_axi_lite_awaddr(11 downto 0)));
          end if;

          case v_addr is
            when 16#00# => -- CONTROL
              control_start_r  <= s_axi_lite_wdata(0);
              control_reset_r  <= s_axi_lite_wdata(1);
              control_irq_en_r <= s_axi_lite_wdata(2);

            when 16#08# => -- SRC_LEN
              src_len_r <= unsigned(s_axi_lite_wdata);

            when 16#14# => -- KEY_0
              key_r(0) <= unsigned(s_axi_lite_wdata);
            when 16#18# => -- KEY_1
              key_r(1) <= unsigned(s_axi_lite_wdata);
            when 16#1C# => -- KEY_2
              key_r(2) <= unsigned(s_axi_lite_wdata);
            when 16#20# => -- KEY_3
              key_r(3) <= unsigned(s_axi_lite_wdata);
            when 16#24# => -- KEY_4
              key_r(4) <= unsigned(s_axi_lite_wdata);
            when 16#28# => -- KEY_5
              key_r(5) <= unsigned(s_axi_lite_wdata);
            when 16#2C# => -- KEY_6
              key_r(6) <= unsigned(s_axi_lite_wdata);
            when 16#30# => -- KEY_7
              key_r(7) <= unsigned(s_axi_lite_wdata);

            when 16#34# => -- NONCE_0
              nonce_r(0) <= unsigned(s_axi_lite_wdata);
            when 16#38# => -- NONCE_1
              nonce_r(1) <= unsigned(s_axi_lite_wdata);
            when 16#3C# => -- NONCE_2
              nonce_r(2) <= unsigned(s_axi_lite_wdata);

            when 16#40# => -- BLOCK_COUNTER
              block_counter_init_r <= unsigned(s_axi_lite_wdata);

            when others =>
              null;
          end case;
        elsif (axi_bvalid_r = '1' and s_axi_lite_bready = '1') then
          axi_bvalid_r <= '0';
        end if;
      end if;
    end if;
  end process p_axi_write;

  p_axi_read : process(aclk)
    variable v_addr : integer range 0 to 4095;
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        axi_arready_r <= '0';
        axi_rvalid_r  <= '0';
        axi_rdata_r   <= (others => '0');
      else
        if (s_axi_lite_arvalid = '1' and axi_arready_r = '0') then
          axi_arready_r <= '1';
        else
          axi_arready_r <= '0';
        end if;

        if (s_axi_lite_arvalid = '1' and axi_arready_r = '1') then
          axi_rvalid_r <= '1';
          v_addr := to_integer(unsigned(s_axi_lite_araddr(11 downto 0)));

          case v_addr is
            when 16#00# => -- CONTROL
              axi_rdata_r <= (2 => control_irq_en_r, others => '0');

            when 16#04# => -- STATUS
              axi_rdata_r <= (0 => status_busy_r,
                              1 => status_done_r,
                              2 => status_err_r,
                              others => '0');

            when 16#08# => -- SRC_LEN
              axi_rdata_r <= std_logic_vector(src_len_r);

            when 16#0C# => -- DST_LEN
              axi_rdata_r <= std_logic_vector(dst_len_r);

            when 16#10# => -- CYCLE_COUNT
              axi_rdata_r <= std_logic_vector(cycle_count_r);

            when 16#14# => axi_rdata_r <= std_logic_vector(key_r(0));
            when 16#18# => axi_rdata_r <= std_logic_vector(key_r(1));
            when 16#1C# => axi_rdata_r <= std_logic_vector(key_r(2));
            when 16#20# => axi_rdata_r <= std_logic_vector(key_r(3));
            when 16#24# => axi_rdata_r <= std_logic_vector(key_r(4));
            when 16#28# => axi_rdata_r <= std_logic_vector(key_r(5));
            when 16#2C# => axi_rdata_r <= std_logic_vector(key_r(6));
            when 16#30# => axi_rdata_r <= std_logic_vector(key_r(7));

            when 16#34# => axi_rdata_r <= std_logic_vector(nonce_r(0));
            when 16#38# => axi_rdata_r <= std_logic_vector(nonce_r(1));
            when 16#3C# => axi_rdata_r <= std_logic_vector(nonce_r(2));

            when 16#40# => axi_rdata_r <= std_logic_vector(block_counter_init_r);

            when others =>
              axi_rdata_r <= x"DEADBEEF";
          end case;
        elsif (axi_rvalid_r = '1' and s_axi_lite_rready = '1') then
          axi_rvalid_r <= '0';
        end if;
      end if;
    end if;
  end process p_axi_read;

  ------------------------------------------------------------------------------
  -- 2. ChaCha20 Cryptographic State Machine & Datapath
  ------------------------------------------------------------------------------
  p_engine_fsm : process(aclk)
    variable v_qr0, v_qr1, v_qr2, v_qr3 : qr_out_t;
    variable v_next_state : state_t;
    variable v_init_block : state_t;
  begin
    if rising_edge(aclk) then
      if (aresetn = '0' or control_reset_r = '1') then
        fsm_state_r        <= S_IDLE;
        status_busy_r      <= '0';
        status_done_r      <= '0';
        status_err_r       <= '0';
        dst_len_r          <= (others => '0');
        cycle_count_r      <= (others => '0');
        current_counter_r  <= to_unsigned(1, 32);
        round_cnt_r        <= 0;
        word_idx_r         <= 0;
        bytes_processed_r  <= (others => '0');
        irq_pulse_r        <= '0';
      else
        irq_pulse_r <= '0';

        -- Hardware cycle counter tracks time when core is busy
        if status_busy_r = '1' then
          cycle_count_r <= cycle_count_r + 1;
        end if;

        case fsm_state_r is

          when S_IDLE =>
            word_idx_r        <= 0;
            bytes_processed_r <= (others => '0');

            if control_start_r = '1' then
              status_busy_r     <= '1';
              status_done_r     <= '0';
              status_err_r      <= '0';
              cycle_count_r     <= (others => '0');
              dst_len_r         <= (others => '0');
              current_counter_r <= block_counter_init_r;
              fsm_state_r       <= S_LOAD_STATE;
            end if;

          when S_LOAD_STATE =>
            -- Construct initial 4x4 matrix per RFC 8439
            v_init_block(0)  := c_const_0;
            v_init_block(1)  := c_const_1;
            v_init_block(2)  := c_const_2;
            v_init_block(3)  := c_const_3;

            v_init_block(4)  := key_r(0);
            v_init_block(5)  := key_r(1);
            v_init_block(6)  := key_r(2);
            v_init_block(7)  := key_r(3);
            v_init_block(8)  := key_r(4);
            v_init_block(9)  := key_r(5);
            v_init_block(10) := key_r(6);
            v_init_block(11) := key_r(7);

            v_init_block(12) := current_counter_r;
            v_init_block(13) := nonce_r(0);
            v_init_block(14) := nonce_r(1);
            v_init_block(15) := nonce_r(2);

            state_init_r <= v_init_block;
            state_work_r <= v_init_block;
            round_cnt_r  <= 0;
            fsm_state_r  <= S_ROUNDS;

          when S_ROUNDS =>
            v_next_state := state_work_r;

            if (round_cnt_r mod 2 = 0) then
              -- Column Round: 4 Column Quarter-Rounds in parallel
              v_qr0 := chacha_qr(state_work_r(0), state_work_r(4), state_work_r(8),  state_work_r(12));
              v_qr1 := chacha_qr(state_work_r(1), state_work_r(5), state_work_r(9),  state_work_r(13));
              v_qr2 := chacha_qr(state_work_r(2), state_work_r(6), state_work_r(10), state_work_r(14));
              v_qr3 := chacha_qr(state_work_r(3), state_work_r(7), state_work_r(11), state_work_r(15));

              v_next_state(0)  := v_qr0.a;
              v_next_state(4)  := v_qr0.b;
              v_next_state(8)  := v_qr0.c;
              v_next_state(12) := v_qr0.d;

              v_next_state(1)  := v_qr1.a;
              v_next_state(5)  := v_qr1.b;
              v_next_state(9)  := v_qr1.c;
              v_next_state(13) := v_qr1.d;

              v_next_state(2)  := v_qr2.a;
              v_next_state(6)  := v_qr2.b;
              v_next_state(10) := v_qr2.c;
              v_next_state(14) := v_qr2.d;

              v_next_state(3)  := v_qr3.a;
              v_next_state(7)  := v_qr3.b;
              v_next_state(11) := v_qr3.c;
              v_next_state(15) := v_qr3.d;
            else
              -- Diagonal Round: 4 Diagonal Quarter-Rounds in parallel
              v_qr0 := chacha_qr(state_work_r(0), state_work_r(5), state_work_r(10), state_work_r(15));
              v_qr1 := chacha_qr(state_work_r(1), state_work_r(6), state_work_r(11), state_work_r(12));
              v_qr2 := chacha_qr(state_work_r(2), state_work_r(7), state_work_r(8),  state_work_r(13));
              v_qr3 := chacha_qr(state_work_r(3), state_work_r(4), state_work_r(9),  state_work_r(14));

              v_next_state(0)  := v_qr0.a;
              v_next_state(5)  := v_qr0.b;
              v_next_state(10) := v_qr0.c;
              v_next_state(15) := v_qr0.d;

              v_next_state(1)  := v_qr1.a;
              v_next_state(6)  := v_qr1.b;
              v_next_state(11) := v_qr1.c;
              v_next_state(12) := v_qr1.d;

              v_next_state(2)  := v_qr2.a;
              v_next_state(7)  := v_qr2.b;
              v_next_state(8)  := v_qr2.c;
              v_next_state(13) := v_qr2.d;

              v_next_state(3)  := v_qr3.a;
              v_next_state(4)  := v_qr3.b;
              v_next_state(9)  := v_qr3.c;
              v_next_state(14) := v_qr3.d;
            end if;

            state_work_r <= v_next_state;

            if round_cnt_r = 19 then
              fsm_state_r <= S_ADD_STATE;
            else
              round_cnt_r <= round_cnt_r + 1;
            end if;

          when S_ADD_STATE =>
            -- Add working state to initial state modulo 2^32
            for i in 0 to 15 loop
              keystream_r(i) <= state_work_r(i) + state_init_r(i);
            end loop;
            word_idx_r  <= 0;
            fsm_state_r <= S_STREAM;

          when S_STREAM =>
            -- When stream beat handshakes
            if (s_axis_tvalid = '1' and m_axis_tready = '1') then
              bytes_processed_r <= bytes_processed_r + 4;
              dst_len_r         <= dst_len_r + 4;

              if (s_axis_tlast = '1') then
                fsm_state_r <= S_DONE;
              elsif word_idx_r = 15 then
                -- Finished 64 bytes of keystream; advance counter and compute next block
                current_counter_r <= current_counter_r + 1;
                fsm_state_r       <= S_LOAD_STATE;
              else
                word_idx_r <= word_idx_r + 1;
              end if;
            end if;

          when S_DONE =>
            status_busy_r <= '0';
            status_done_r <= '1';

            if control_irq_en_r = '1' then
              irq_pulse_r <= '1';
            end if;

            fsm_state_r <= S_IDLE;

        end case;
      end if;
    end if;
  end process p_engine_fsm;

end architecture rtl;
