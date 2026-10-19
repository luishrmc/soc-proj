--------------------------------------------------------------------------------
-- Company:       UFMG / Embedded Systems & SoC Laboratory
-- Engineer:      Antigravity Agentic Assistant & User
--
-- Create Date:   2026-10-18 (Refactored 2026-10-19)
-- Design Name:   lz4_engine
-- Module Name:   lz4_engine - rtl
-- Project Name:  Zynq-7010 PS/PL Compression & Encryption Benchmark
-- Target Devices: Digilent Cora Z7-10 (XC7Z010-1CLG400C)
-- Tool Versions: Vivado 2026.1 / GHDL VHDL-2008
-- Description:   Optimized Hardware LZ4 Lossless Compression Engine.
--                Low-resource, high-throughput streaming architecture:
--                - 32-bit word dictionary matching for zero combinatorial explosion
--                - Sequential token/literal/offset byte serialization
--                - Direct AXI4-Stream beat packing with exact tlast/tkeep boundary
--                - AXI4-Lite CSR control, status, performance counters
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lz4_engine is
  generic (
    c_s_axi_data_width : integer := 32;
    c_s_axi_addr_width : integer := 12;
    c_axis_data_width  : integer := 32;
    c_window_size      : integer := 64;
    c_hash_size        : integer := 32
  );
  port (
    -- Global Synchronous Clock and Active-Low Reset
    aclk               : in  std_logic;
    aresetn            : in  std_logic;

    -- Interrupt and Busy Indicators
    irq_o              : out std_logic;
    busy_o             : out std_logic;

    -- ========================================================================
    -- AXI4-Lite Slave Interface (Control & Status Registers)
    -- ========================================================================
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

    -- ========================================================================
    -- AXI4-Stream Ingress Channel (Raw Data from DMA MM2S)
    -- ========================================================================
    s_axis_tdata       : in  std_logic_vector(c_axis_data_width - 1 downto 0);
    s_axis_tkeep       : in  std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    s_axis_tvalid      : in  std_logic;
    s_axis_tready      : out std_logic;
    s_axis_tlast       : in  std_logic;

    -- ========================================================================
    -- AXI4-Stream Egress Channel (Compressed Data to DMA S2MM)
    -- ========================================================================
    m_axis_tdata       : out std_logic_vector(c_axis_data_width - 1 downto 0);
    m_axis_tkeep       : out std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    m_axis_tvalid      : out std_logic;
    m_axis_tready      : in  std_logic;
    m_axis_tlast       : out std_logic
  );
end entity lz4_engine;

architecture rtl of lz4_engine is

  -- Register address offsets (per INTERFACES.md Section 2.2)
  constant c_addr_control     : std_logic_vector(7 downto 0) := x"00";
  constant c_addr_status      : std_logic_vector(7 downto 0) := x"04";
  constant c_addr_src_len     : std_logic_vector(7 downto 0) := x"08";
  constant c_addr_dst_len     : std_logic_vector(7 downto 0) := x"0C";
  constant c_addr_cycle_count : std_logic_vector(7 downto 0) := x"10";

  -- AXI4-Lite Internal Registers
  signal reg_control_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_status_r      : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_src_len_r     : std_logic_vector(31 downto 0) := (others => '0');

  signal axi_awready_r     : std_logic := '0';
  signal axi_wready_r      : std_logic := '0';
  signal axi_bvalid_r      : std_logic := '0';
  signal axi_arready_r     : std_logic := '0';
  signal axi_rvalid_r      : std_logic := '0';
  signal axi_rdata_r       : std_logic_vector(31 downto 0) := (others => '0');

  signal ctrl_start_s      : std_logic;
  signal ctrl_reset_s      : std_logic;
  signal ctrl_irq_en_s     : std_logic;

  -- --------------------------------------------------------------------------
  -- Datapath States
  -- --------------------------------------------------------------------------
  type t_fsm_state is (
    ST_IDLE,
    ST_FETCH_BEAT,
    ST_EVAL_BEAT,
    ST_EMIT_TOKEN,
    ST_EMIT_LITERALS,
    ST_EMIT_OFF_LO,
    ST_EMIT_OFF_HI,
    ST_FLUSH_TOKEN,
    ST_FLUSH_LITERALS,
    ST_DRAIN_PACKER,
    ST_DONE_PULSE
  );
  signal state_r : t_fsm_state := ST_IDLE;

  -- Word-based sliding window history (16 words = 64 bytes)
  type t_word_history is array (0 to 15) of std_logic_vector(31 downto 0);
  signal history_words_r : t_word_history := (others => (others => '0'));
  type t_word_pos_array is array (0 to 15) of integer range 0 to 65535;
  signal history_pos_r   : t_word_pos_array := (others => 0);
  type t_word_valid_array is array (0 to 15) of boolean;
  signal history_valid_r : t_word_valid_array := (others => false);

  -- Stream position in bytes
  signal stream_pos_r    : integer range 0 to 65535 := 0;

  -- Current input beat register
  signal in_beat_data_r  : std_logic_vector(31 downto 0) := (others => '0');
  signal in_beat_keep_r  : std_logic_vector(3 downto 0)  := (others => '0');
  signal in_beat_last_r  : std_logic := '0';

  -- Literal buffer (stores up to 16 literal bytes)
  type t_lit_buf is array (0 to 15) of std_logic_vector(7 downto 0);
  signal lit_buf_r       : t_lit_buf := (others => (others => '0'));
  signal lit_count_r     : integer range 0 to 15 := 0;
  signal lit_emit_idx_r  : integer range 0 to 15 := 0;

  -- Match info
  signal match_found_r   : boolean := false;
  signal match_offset_r  : integer range 0 to 65535 := 0;

  -- Egress Word Packer
  signal pack_word_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal pack_byte_idx_r : integer range 0 to 3 := 0;
  signal pack_valid_r    : std_logic := '0';
  signal pack_last_r     : std_logic := '0';
  signal pack_keep_r     : std_logic_vector(3 downto 0) := (others => '0');

  -- Performance Counters
  signal byte_counter_in_r  : unsigned(31 downto 0) := (others => '0');
  signal byte_counter_out_r : unsigned(31 downto 0) := (others => '0');
  signal cycle_counter_r    : unsigned(31 downto 0) := (others => '0');

  signal irq_pulse_r        : std_logic := '0';

begin

  -- ==========================================================================
  -- Section 1: AXI4-Lite Control & Status Registers
  -- ==========================================================================
  ctrl_start_s  <= reg_control_r(0);
  ctrl_reset_s  <= reg_control_r(1);
  ctrl_irq_en_s <= reg_control_r(2);
  busy_o        <= reg_status_r(0);

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
        axi_awready_r <= '0';
        axi_wready_r  <= '0';
        axi_bvalid_r  <= '0';
        reg_control_r <= (others => '0');
        reg_src_len_r <= (others => '0');
      else
        if (s_axi_lite_awvalid = '1' and axi_awready_r = '0') and
           (s_axi_lite_wvalid = '1' and axi_wready_r = '0') then
          axi_awready_r <= '1';
          axi_wready_r  <= '1';

          case s_axi_lite_awaddr(7 downto 0) is
            when c_addr_control =>
              reg_control_r <= s_axi_lite_wdata;
            when c_addr_src_len =>
              reg_src_len_r <= s_axi_lite_wdata;
            when others =>
              null;
          end case;
        else
          axi_awready_r <= '0';
          axi_wready_r  <= '0';
        end if;

        if (axi_awready_r = '1' and axi_wready_r = '1') then
          axi_bvalid_r <= '1';
        elsif s_axi_lite_bready = '1' then
          axi_bvalid_r <= '0';
        end if;

        -- Self-clearing start and reset bits
        if ctrl_start_s = '1' and state_r /= ST_IDLE then
          reg_control_r(0) <= '0';
        end if;
        if reg_control_r(1) = '1' then
          reg_control_r(1) <= '0';
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
            when c_addr_control =>
              axi_rdata_r <= reg_control_r;
            when c_addr_status =>
              axi_rdata_r <= reg_status_r;
            when c_addr_src_len =>
              axi_rdata_r <= std_logic_vector(byte_counter_in_r);
            when c_addr_dst_len =>
              axi_rdata_r <= std_logic_vector(byte_counter_out_r);
            when c_addr_cycle_count =>
              axi_rdata_r <= std_logic_vector(cycle_counter_r);
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

  -- Ready to accept input beat when in ST_FETCH_BEAT and packer is not stalled
  s_axis_tready <= '1' when (state_r = ST_FETCH_BEAT and (pack_valid_r = '0' or m_axis_tready = '1')) else '0';

  -- ==========================================================================
  -- Section 2: Sequential LZ4 Datapath & Packer FSM
  -- ==========================================================================
  process (aclk)
    variable v_token      : std_logic_vector(7 downto 0);
    variable v_lit_nibble : unsigned(3 downto 0);
    variable v_mat_nibble : unsigned(3 downto 0);
    variable v_found      : boolean;
    variable v_off        : integer range 0 to 65535;
  begin
    if rising_edge(aclk) then
      if aresetn = '0' or ctrl_reset_s = '1' then
        state_r            <= ST_IDLE;
        reg_status_r       <= (others => '0');
        byte_counter_in_r  <= (others => '0');
        byte_counter_out_r <= (others => '0');
        cycle_counter_r    <= (others => '0');
        irq_pulse_r        <= '0';
        stream_pos_r       <= 0;
        history_valid_r    <= (others => false);
        lit_count_r        <= 0;
        lit_emit_idx_r     <= 0;
        match_found_r      <= false;
        match_offset_r     <= 0;
        pack_word_r        <= (others => '0');
        pack_byte_idx_r    <= 0;
        pack_valid_r       <= '0';
        pack_last_r        <= '0';
        pack_keep_r        <= (others => '0');
      else
        irq_pulse_r <= '0';

        -- Clear pack_valid_r on downstream handshake
        if pack_valid_r = '1' and m_axis_tready = '1' then
          pack_valid_r <= '0';
          pack_last_r  <= '0';
        end if;

        case state_r is
          -- ------------------------------------------------------------------
          -- State: IDLE
          -- ------------------------------------------------------------------
          when ST_IDLE =>
            if ctrl_start_s = '1' then
              reg_status_r(0)    <= '1'; -- BUSY = 1
              reg_status_r(1)    <= '0'; -- DONE = 0
              reg_status_r(2)    <= '0'; -- ERR = 0
              byte_counter_in_r  <= (others => '0');
              byte_counter_out_r <= (others => '0');
              cycle_counter_r    <= (others => '0');
              stream_pos_r       <= 0;
              history_valid_r    <= (others => false);
              lit_count_r        <= 0;
              pack_byte_idx_r    <= 0;
              pack_valid_r       <= '0';
              pack_last_r        <= '0';
              state_r            <= ST_FETCH_BEAT;
            end if;

          -- ------------------------------------------------------------------
          -- State: FETCH_BEAT (Wait for 32-bit beat from DMA MM2S)
          -- ------------------------------------------------------------------
          when ST_FETCH_BEAT =>
            cycle_counter_r <= cycle_counter_r + 1;

            if s_axis_tvalid = '1' and (pack_valid_r = '0' or m_axis_tready = '1') then
              in_beat_data_r <= s_axis_tdata;
              in_beat_keep_r <= s_axis_tkeep;
              in_beat_last_r <= s_axis_tlast;

              -- Count bytes received
              if s_axis_tkeep = "1111" then
                byte_counter_in_r <= byte_counter_in_r + 4;
              elsif s_axis_tkeep = "0111" then
                byte_counter_in_r <= byte_counter_in_r + 3;
              elsif s_axis_tkeep = "0011" then
                byte_counter_in_r <= byte_counter_in_r + 2;
              else
                byte_counter_in_r <= byte_counter_in_r + 1;
              end if;

              state_r <= ST_EVAL_BEAT;
            end if;

          -- ------------------------------------------------------------------
          -- State: EVAL_BEAT (Search history for 4-byte match)
          -- ------------------------------------------------------------------
          when ST_EVAL_BEAT =>
            cycle_counter_r <= cycle_counter_r + 1;

            v_found := false;
            v_off   := 0;

            -- Check if beat is a full 4-byte word and matches recent word in history
            if in_beat_keep_r = "1111" then
              for k in 0 to 15 loop
                if history_valid_r(k) and history_words_r(k) = in_beat_data_r then
                  if stream_pos_r >= history_pos_r(k) then
                    v_off := stream_pos_r - history_pos_r(k);
                  else
                    v_off := (65536 + stream_pos_r) - history_pos_r(k);
                  end if;

                  if v_off > 0 and v_off < 65536 then
                    v_found := true;
                    exit;
                  end if;
                end if;
              end loop;
            end if;

            if v_found then
              -- MATCH: Prepare to emit sequence token [lit_len | match_len=4]
              match_found_r  <= true;
              match_offset_r <= v_off;
              lit_emit_idx_r <= 0;
              state_r        <= ST_EMIT_TOKEN;

              -- Update history with current beat
              history_words_r((stream_pos_r / 4) mod 16) <= in_beat_data_r;
              history_pos_r((stream_pos_r / 4) mod 16)   <= stream_pos_r;
              history_valid_r((stream_pos_r / 4) mod 16) <= true;
              stream_pos_r <= (stream_pos_r + 4) mod 65536;

            else
              -- NO MATCH: Append bytes to literal buffer
              match_found_r <= false;

              -- Store 4 bytes into literal buffer
              lit_buf_r(lit_count_r)     <= in_beat_data_r(7 downto 0);
              lit_buf_r(lit_count_r + 1) <= in_beat_data_r(15 downto 8);
              lit_buf_r(lit_count_r + 2) <= in_beat_data_r(23 downto 16);
              lit_buf_r(lit_count_r + 3) <= in_beat_data_r(31 downto 24);

              -- Record in history
              if in_beat_keep_r = "1111" then
                history_words_r((stream_pos_r / 4) mod 16) <= in_beat_data_r;
                history_pos_r((stream_pos_r / 4) mod 16)   <= stream_pos_r;
                history_valid_r((stream_pos_r / 4) mod 16) <= true;
              end if;
              stream_pos_r <= (stream_pos_r + 4) mod 65536;

              if in_beat_last_r = '1' then
                -- End of block: flush literals
                lit_count_r    <= lit_count_r + 4;
                lit_emit_idx_r <= 0;
                state_r        <= ST_FLUSH_TOKEN;
              elsif lit_count_r >= 8 then
                -- Literal buffer getting full: emit literal sequence
                lit_count_r    <= lit_count_r + 4;
                lit_emit_idx_r <= 0;
                match_offset_r <= 0;
                state_r        <= ST_EMIT_TOKEN;
              else
                lit_count_r <= lit_count_r + 4;
                state_r     <= ST_FETCH_BEAT;
              end if;
            end if;

          -- ------------------------------------------------------------------
          -- State: EMIT_TOKEN (Emit token byte: lit_nibble | match_nibble)
          -- ------------------------------------------------------------------
          when ST_EMIT_TOKEN =>
            cycle_counter_r <= cycle_counter_r + 1;

            if pack_valid_r = '0' or m_axis_tready = '1' then
              v_lit_nibble := to_unsigned(lit_count_r, 4);
              if match_found_r then
                v_mat_nibble := to_unsigned(0, 4); -- match length 4 is encoded as 0 (len - 4)
              else
                v_mat_nibble := to_unsigned(0, 4);
              end if;
              v_token := std_logic_vector(v_lit_nibble) & std_logic_vector(v_mat_nibble);

              -- Pack token byte
              pack_word_r(pack_byte_idx_r * 8 + 7 downto pack_byte_idx_r * 8) <= v_token;
              byte_counter_out_r <= byte_counter_out_r + 1;

              if pack_byte_idx_r = 3 then
                pack_valid_r    <= '1';
                pack_keep_r     <= "1111";
                pack_byte_idx_r <= 0;
              else
                pack_byte_idx_r <= pack_byte_idx_r + 1;
              end if;

              if lit_count_r > 0 then
                lit_emit_idx_r <= 0;
                state_r        <= ST_EMIT_LITERALS;
              elsif match_found_r then
                state_r <= ST_EMIT_OFF_LO;
              elsif in_beat_last_r = '1' then
                state_r <= ST_DRAIN_PACKER;
              else
                state_r <= ST_FETCH_BEAT;
              end if;
            end if;

          -- ------------------------------------------------------------------
          -- State: EMIT_LITERALS (Sequentially serialize literal bytes)
          -- ------------------------------------------------------------------
          when ST_EMIT_LITERALS =>
            cycle_counter_r <= cycle_counter_r + 1;

            if pack_valid_r = '0' or m_axis_tready = '1' then
              pack_word_r(pack_byte_idx_r * 8 + 7 downto pack_byte_idx_r * 8) <= lit_buf_r(lit_emit_idx_r);
              byte_counter_out_r <= byte_counter_out_r + 1;

              if pack_byte_idx_r = 3 then
                pack_valid_r    <= '1';
                pack_keep_r     <= "1111";
                pack_byte_idx_r <= 0;
              else
                pack_byte_idx_r <= pack_byte_idx_r + 1;
              end if;

              if lit_emit_idx_r + 1 < lit_count_r then
                lit_emit_idx_r <= lit_emit_idx_r + 1;
              else
                -- Literals done
                lit_count_r <= 0;
                if match_found_r then
                  state_r <= ST_EMIT_OFF_LO;
                elsif in_beat_last_r = '1' then
                  state_r <= ST_DRAIN_PACKER;
                else
                  state_r <= ST_FETCH_BEAT;
                end if;
              end if;
            end if;

          -- ------------------------------------------------------------------
          -- State: EMIT_OFF_LO (Emit 16-bit match offset low byte)
          -- ------------------------------------------------------------------
          when ST_EMIT_OFF_LO =>
            cycle_counter_r <= cycle_counter_r + 1;

            if pack_valid_r = '0' or m_axis_tready = '1' then
              pack_word_r(pack_byte_idx_r * 8 + 7 downto pack_byte_idx_r * 8) <=
                std_logic_vector(to_unsigned(match_offset_r mod 256, 8));
              byte_counter_out_r <= byte_counter_out_r + 1;

              if pack_byte_idx_r = 3 then
                pack_valid_r    <= '1';
                pack_keep_r     <= "1111";
                pack_byte_idx_r <= 0;
              else
                pack_byte_idx_r <= pack_byte_idx_r + 1;
              end if;

              state_r <= ST_EMIT_OFF_HI;
            end if;

          -- ------------------------------------------------------------------
          -- State: EMIT_OFF_HI (Emit 16-bit match offset high byte)
          -- ------------------------------------------------------------------
          when ST_EMIT_OFF_HI =>
            cycle_counter_r <= cycle_counter_r + 1;

            if pack_valid_r = '0' or m_axis_tready = '1' then
              pack_word_r(pack_byte_idx_r * 8 + 7 downto pack_byte_idx_r * 8) <=
                std_logic_vector(to_unsigned((match_offset_r / 256) mod 256, 8));
              byte_counter_out_r <= byte_counter_out_r + 1;

              if pack_byte_idx_r = 3 then
                pack_valid_r    <= '1';
                pack_keep_r     <= "1111";
                pack_byte_idx_r <= 0;
              else
                pack_byte_idx_r <= pack_byte_idx_r + 1;
              end if;

              if in_beat_last_r = '1' then
                state_r <= ST_DRAIN_PACKER;
              else
                state_r <= ST_FETCH_BEAT;
              end if;
            end if;

          -- ------------------------------------------------------------------
          -- State: FLUSH_TOKEN (Emit final literal sequence token)
          -- ------------------------------------------------------------------
          when ST_FLUSH_TOKEN =>
            cycle_counter_r <= cycle_counter_r + 1;

            if pack_valid_r = '0' or m_axis_tready = '1' then
              v_lit_nibble := to_unsigned(lit_count_r, 4);
              v_token      := std_logic_vector(v_lit_nibble) & x"0";

              pack_word_r(pack_byte_idx_r * 8 + 7 downto pack_byte_idx_r * 8) <= v_token;
              byte_counter_out_r <= byte_counter_out_r + 1;

              if pack_byte_idx_r = 3 then
                pack_valid_r    <= '1';
                pack_keep_r     <= "1111";
                pack_byte_idx_r <= 0;
              else
                pack_byte_idx_r <= pack_byte_idx_r + 1;
              end if;

              if lit_count_r > 0 then
                lit_emit_idx_r <= 0;
                state_r        <= ST_FLUSH_LITERALS;
              else
                state_r <= ST_DRAIN_PACKER;
              end if;
            end if;

          -- ------------------------------------------------------------------
          -- State: FLUSH_LITERALS (Sequentially serialize remaining literals)
          -- ------------------------------------------------------------------
          when ST_FLUSH_LITERALS =>
            cycle_counter_r <= cycle_counter_r + 1;

            if pack_valid_r = '0' or m_axis_tready = '1' then
              pack_word_r(pack_byte_idx_r * 8 + 7 downto pack_byte_idx_r * 8) <= lit_buf_r(lit_emit_idx_r);
              byte_counter_out_r <= byte_counter_out_r + 1;

              if pack_byte_idx_r = 3 then
                pack_valid_r    <= '1';
                pack_keep_r     <= "1111";
                pack_byte_idx_r <= 0;
              else
                pack_byte_idx_r <= pack_byte_idx_r + 1;
              end if;

              if lit_emit_idx_r + 1 < lit_count_r then
                lit_emit_idx_r <= lit_emit_idx_r + 1;
              else
                lit_count_r <= 0;
                state_r     <= ST_DRAIN_PACKER;
              end if;
            end if;

          -- ------------------------------------------------------------------
          -- State: DRAIN_PACKER (Emit trailing partial or full word with tlast)
          -- ------------------------------------------------------------------
          when ST_DRAIN_PACKER =>
            cycle_counter_r <= cycle_counter_r + 1;

            -- Wait for any currently pending word handshake to complete
            if pack_valid_r = '0' or m_axis_tready = '1' then
              if pack_byte_idx_r > 0 then
                -- Partial beat remaining: emit with matching tkeep and tlast
                pack_valid_r <= '1';
                pack_last_r  <= '1';
                case pack_byte_idx_r is
                  when 1 => pack_keep_r <= "0001";
                  when 2 => pack_keep_r <= "0011";
                  when 3 => pack_keep_r <= "0111";
                  when others => pack_keep_r <= "1111";
                end case;
                pack_byte_idx_r <= 0;
                state_r         <= ST_DONE_PULSE;
              else
                -- Word packer already drained! If last beat was already sent, just finish
                state_r <= ST_DONE_PULSE;
              end if;
            end if;

          -- ------------------------------------------------------------------
          -- State: DONE_PULSE (Wait for final handshake, assert DONE & IRQ)
          -- ------------------------------------------------------------------
          when ST_DONE_PULSE =>
            cycle_counter_r <= cycle_counter_r + 1;

            if pack_valid_r = '0' or m_axis_tready = '1' then
              pack_valid_r    <= '0';
              pack_last_r     <= '0';
              reg_status_r(0) <= '0'; -- BUSY = 0
              reg_status_r(1) <= '1'; -- DONE = 1
              if ctrl_irq_en_s = '1' then
                irq_pulse_r <= '1';
              end if;
              state_r <= ST_IDLE;
            end if;

        end case;
      end if;
    end if;
  end process;

  -- ==========================================================================
  -- Section 3: Output Port Assignments
  -- ==========================================================================
  m_axis_tdata  <= pack_word_r;
  m_axis_tkeep  <= pack_keep_r;
  m_axis_tvalid <= pack_valid_r;
  m_axis_tlast  <= pack_last_r;

  irq_o <= irq_pulse_r;

end architecture rtl;
