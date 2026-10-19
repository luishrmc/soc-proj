--------------------------------------------------------------------------------
-- Company:       UFMG / Embedded Systems & SoC Laboratory
-- Engineer:      Antigravity Agentic Assistant & User
--
-- Create Date:   2026-10-18
-- Design Name:   lz4_engine
-- Module Name:   lz4_engine - rtl
-- Project Name:  Zynq-7010 PS/PL Compression & Encryption Benchmark
-- Target Devices: Digilent Cora Z7-10 (XC7Z010-1CLG400C)
-- Tool Versions: Vivado 2026.1 / GHDL VHDL-2008
-- Description:   Simplified LZ4 Lossless Hardware Compression Engine.
--                Implements dictionary-based sliding window compression with
--                a 4-byte hash table match finder, byte-aligned sequence
--                token emission, 32-bit AXI4-Stream data channels, and an
--                AXI4-Lite slave interface for control, status, and metrics.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lz4_engine is
  generic (
    c_s_axi_data_width : integer := 32;
    c_s_axi_addr_width : integer := 8;
    c_axis_data_width  : integer := 32;
    c_window_size      : integer := 64;
    c_hash_size        : integer := 32
  );
  port (
    -- Global Synchronous Clock and Active-Low Reset
    aclk               : in  std_logic;
    aresetn            : in  std_logic;

    -- Interrupt Output (Active-high completion pulse to ARM GIC)
    irq_o              : out std_logic;

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
    -- AXI4-Stream Slave Interface (Raw Ingress Stream from DMA)
    -- ========================================================================
    s_axis_tdata       : in  std_logic_vector(c_axis_data_width - 1 downto 0);
    s_axis_tkeep       : in  std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    s_axis_tvalid      : in  std_logic;
    s_axis_tready      : out std_logic;
    s_axis_tlast       : in  std_logic;

    -- ========================================================================
    -- AXI4-Stream Master Interface (Compressed Egress Stream to DMA)
    -- ========================================================================
    m_axis_tdata       : out std_logic_vector(c_axis_data_width - 1 downto 0);
    m_axis_tkeep       : out std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    m_axis_tvalid      : out std_logic;
    m_axis_tready      : in  std_logic;
    m_axis_tlast       : out std_logic
  );

  -- ==========================================================================
  -- Vivado IP Integrator Clock and Reset Association
  -- ==========================================================================
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of aclk    : signal is "ASSOCIATED_BUSIF s_axi_lite:s_axis:m_axis, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";
end entity lz4_engine;

architecture rtl of lz4_engine is

  -- --------------------------------------------------------------------------
  -- Constants: Register Offsets
  -- --------------------------------------------------------------------------
  constant c_addr_control     : std_logic_vector(7 downto 0) := x"00";
  constant c_addr_status      : std_logic_vector(7 downto 0) := x"04";
  constant c_addr_src_len     : std_logic_vector(7 downto 0) := x"08";
  constant c_addr_dst_len     : std_logic_vector(7 downto 0) := x"0C";
  constant c_addr_cycle_count : std_logic_vector(7 downto 0) := x"10";

  -- --------------------------------------------------------------------------
  -- AXI4-Lite Internal Registers
  -- --------------------------------------------------------------------------
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
  signal ctrl_irq_en_s     : std_logic;

  -- --------------------------------------------------------------------------
  -- Internal Datapath & Buffers
  -- --------------------------------------------------------------------------
  type t_fsm_state is (
    ST_IDLE,
    ST_INGEST_BEAT,
    ST_EVAL_STREAM,
    ST_EMIT_SEQUENCE,
    ST_FLUSH_REMAINING,
    ST_FINISH
  );
  signal state_r : t_fsm_state := ST_IDLE;

  -- Circular History Buffer
  type t_history_ram is array (0 to c_window_size - 1) of std_logic_vector(7 downto 0);
  signal history_ram_r : t_history_ram := (others => (others => '0'));

  -- Hash Table for 4-byte prefix matching
  type t_hash_ram is array (0 to c_hash_size - 1) of integer range 0 to c_window_size - 1;
  signal hash_ram_r   : t_hash_ram := (others => 0);
  type t_hash_valid_array is array (0 to c_hash_size - 1) of boolean;
  signal hash_valid_r : t_hash_valid_array := (others => false);

  -- Sliding Window Pointers & Position
  signal write_pos_r    : integer range 0 to 65535 := 0;
  signal stream_pos_r   : integer range 0 to 65535 := 0;

  -- Input Ingress Queue (Stores up to 8 bytes for 4-byte lookahead)
  type t_byte_queue is array (0 to 7) of std_logic_vector(7 downto 0);
  signal in_queue_r     : t_byte_queue := (others => (others => '0'));
  signal in_queue_len_r : integer range 0 to 8 := 0;
  signal in_last_seen_r : boolean := false;

  -- Pending Literals Buffer (Stores up to 32 literal bytes)
  type t_lit_buffer is array (0 to 31) of std_logic_vector(7 downto 0);
  signal lit_buf_r      : t_lit_buffer := (others => (others => '0'));
  signal lit_count_r    : integer range 0 to 31 := 0;

  -- Output Byte FIFO (Emits bytes into 32-bit beat packer)
  type t_out_queue is array (0 to 31) of std_logic_vector(7 downto 0);
  signal out_queue_r    : t_out_queue := (others => (others => '0'));
  signal out_queue_len_r: integer range 0 to 31 := 0;

  -- Match info registers
  signal match_offset_r : integer range 0 to 65535 := 0;
  signal match_len_r    : integer range 0 to 19 := 0;

  -- Egress Word Packer
  signal pack_word_r    : std_logic_vector(31 downto 0) := (others => '0');
  signal pack_keep_r    : std_logic_vector(3 downto 0)  := (others => '0');
  signal pack_count_r   : integer range 0 to 4 := 0;
  signal pack_valid_r   : std_logic := '0';
  signal pack_last_r    : std_logic := '0';

  -- Performance Counters
  signal byte_counter_in_r  : unsigned(31 downto 0) := (others => '0');
  signal byte_counter_out_r : unsigned(31 downto 0) := (others => '0');
  signal cycle_counter_r    : unsigned(31 downto 0) := (others => '0');

  signal irq_pulse_r        : std_logic := '0';
  signal s_axis_ready_s     : std_logic;

begin

  -- ==========================================================================
  -- Section 1: AXI4-Lite Control & Status Registers
  -- ==========================================================================
  ctrl_start_s  <= reg_control_r(0);
  ctrl_irq_en_s <= reg_control_r(2);

  s_axi_lite_awready <= axi_awready_r;
  s_axi_lite_wready  <= axi_wready_r;
  s_axi_lite_bresp   <= "00"; -- OKAY
  s_axi_lite_bvalid  <= axi_bvalid_r;

  s_axi_lite_arready <= axi_arready_r;
  s_axi_lite_rdata   <= axi_rdata_r;
  s_axi_lite_rresp   <= "00"; -- OKAY
  s_axi_lite_rvalid  <= axi_rvalid_r;

  -- Process: AXI4-Lite Write Channel
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

        -- Self-clearing start bit
        if ctrl_start_s = '1' and state_r /= ST_IDLE then
          reg_control_r(0) <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Process: AXI4-Lite Read Channel
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

  -- ==========================================================================
  -- Section 2: Ingress Flow Control
  -- ==========================================================================
  -- Accept new 32-bit beat if internal queue has room for 4 bytes
  s_axis_ready_s <= '1' when (state_r = ST_INGEST_BEAT or state_r = ST_EVAL_STREAM)
                         and in_queue_len_r <= 4
                         and not in_last_seen_r else '0';
  s_axis_tready  <= s_axis_ready_s;

  -- ==========================================================================
  -- Section 3: LZ4 Compression Core FSM & Datapath
  -- ==========================================================================
  process (aclk)
    variable v_hash         : integer range 0 to c_hash_size - 1;
    variable v_cand_pos     : integer range 0 to c_window_size - 1;
    variable v_offset       : integer range 0 to 65535;
    variable v_match_found  : boolean;
    variable v_token        : std_logic_vector(7 downto 0);
    variable v_lit_nibble   : unsigned(3 downto 0);
    variable v_match_nibble : unsigned(3 downto 0);
    variable v_hash_16      : unsigned(15 downto 0);
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        state_r            <= ST_IDLE;
        reg_status_r       <= (others => '0');
        byte_counter_in_r  <= (others => '0');
        byte_counter_out_r <= (others => '0');
        cycle_counter_r    <= (others => '0');
        irq_pulse_r        <= '0';
        in_queue_len_r     <= 0;
        in_last_seen_r     <= false;
        lit_count_r        <= 0;
        out_queue_len_r    <= 0;
        pack_count_r       <= 0;
        pack_valid_r       <= '0';
        pack_last_r        <= '0';
        write_pos_r        <= 0;
        stream_pos_r       <= 0;
        hash_valid_r       <= (others => false);
      else
        irq_pulse_r <= '0';

        -- --------------------------------------------------------------------
        -- Sub-engine A: Ingress Beat Ingestion into Queue
        -- --------------------------------------------------------------------
        if s_axis_tvalid = '1' and s_axis_ready_s = '1' then
          -- Unpack 32-bit beat (little-endian byte lanes)
          if s_axis_tkeep(0) = '1' then
            in_queue_r(in_queue_len_r) <= s_axis_tdata(7 downto 0);
          end if;
          if s_axis_tkeep(1) = '1' then
            in_queue_r(in_queue_len_r + 1) <= s_axis_tdata(15 downto 8);
          end if;
          if s_axis_tkeep(2) = '1' then
            in_queue_r(in_queue_len_r + 2) <= s_axis_tdata(23 downto 16);
          end if;
          if s_axis_tkeep(3) = '1' then
            in_queue_r(in_queue_len_r + 3) <= s_axis_tdata(31 downto 24);
          end if;

          if s_axis_tkeep = "1111" then
            in_queue_len_r    <= in_queue_len_r + 4;
            byte_counter_in_r <= byte_counter_in_r + 4;
          elsif s_axis_tkeep = "0111" then
            in_queue_len_r    <= in_queue_len_r + 3;
            byte_counter_in_r <= byte_counter_in_r + 3;
          elsif s_axis_tkeep = "0011" then
            in_queue_len_r    <= in_queue_len_r + 2;
            byte_counter_in_r <= byte_counter_in_r + 2;
          else
            in_queue_len_r    <= in_queue_len_r + 1;
            byte_counter_in_r <= byte_counter_in_r + 1;
          end if;

          if s_axis_tlast = '1' then
            in_last_seen_r <= true;
          end if;
        end if;

        -- --------------------------------------------------------------------
        -- Sub-engine B: Egress Word Packer (Emits 32-bit beats to m_axis)
        -- --------------------------------------------------------------------
        if pack_valid_r = '1' and m_axis_tready = '1' then
          pack_valid_r <= '0';
          pack_last_r  <= '0';
        end if;

        if (pack_valid_r = '0' or m_axis_tready = '1') and out_queue_len_r > 0 then
          -- Pack up to 4 bytes into 32-bit beat
          if out_queue_len_r >= 4 then
            pack_word_r <= out_queue_r(3) & out_queue_r(2) & out_queue_r(1) & out_queue_r(0);
            pack_keep_r <= "1111";
            pack_valid_r <= '1';
            byte_counter_out_r <= byte_counter_out_r + 4;

            -- Shift out queue by 4
            for i in 0 to 27 loop
              out_queue_r(i) <= out_queue_r(i + 4);
            end loop;
            out_queue_len_r <= out_queue_len_r - 4;

          elsif in_last_seen_r and state_r = ST_FINISH then
            -- Emit final partial word with tlast
            case out_queue_len_r is
              when 1 =>
                pack_word_r <= x"000000" & out_queue_r(0);
                pack_keep_r <= "0001";
                byte_counter_out_r <= byte_counter_out_r + 1;
              when 2 =>
                pack_word_r <= x"0000" & out_queue_r(1) & out_queue_r(0);
                pack_keep_r <= "0011";
                byte_counter_out_r <= byte_counter_out_r + 2;
              when 3 =>
                pack_word_r <= x"00" & out_queue_r(2) & out_queue_r(1) & out_queue_r(0);
                pack_keep_r <= "0111";
                byte_counter_out_r <= byte_counter_out_r + 3;
              when others =>
                null;
            end case;
            pack_valid_r    <= '1';
            pack_last_r     <= '1';
            out_queue_len_r <= 0;
          end if;
        end if;

        -- --------------------------------------------------------------------
        -- Sub-engine C: Main Compression FSM
        -- --------------------------------------------------------------------
        case state_r is

          -- ------------------------------------------------------------------
          -- State: IDLE (Wait for start bit or valid incoming stream)
          -- ------------------------------------------------------------------
          when ST_IDLE =>
            reg_status_r(0)    <= '0'; -- BUSY = 0
            in_queue_len_r     <= 0;
            in_last_seen_r     <= false;
            lit_count_r        <= 0;
            out_queue_len_r    <= 0;
            write_pos_r        <= 0;
            stream_pos_r       <= 0;
            pack_valid_r       <= '0';
            pack_last_r        <= '0';

            if ctrl_start_s = '1' or s_axis_tvalid = '1' then
              state_r            <= ST_INGEST_BEAT;
              reg_status_r(0)    <= '1'; -- BUSY = 1
              reg_status_r(1)    <= '0'; -- DONE = 0
              reg_status_r(2)    <= '0'; -- ERR = 0
              byte_counter_in_r  <= (others => '0');
              byte_counter_out_r <= (others => '0');
              cycle_counter_r    <= (others => '0');
              hash_valid_r       <= (others => false);
            end if;

          -- ------------------------------------------------------------------
          -- State: INGEST_BEAT (Buffer bytes into lookahead queue)
          -- ------------------------------------------------------------------
          when ST_INGEST_BEAT =>
            cycle_counter_r <= cycle_counter_r + 1;

            if in_queue_len_r >= 4 or (in_last_seen_r and in_queue_len_r > 0) then
              state_r <= ST_EVAL_STREAM;
            end if;

          -- ------------------------------------------------------------------
          -- State: EVAL_STREAM (Match evaluation via hash table lookup)
          -- ------------------------------------------------------------------
          when ST_EVAL_STREAM =>
            cycle_counter_r <= cycle_counter_r + 1;

            -- Check if we have at least 4 lookahead bytes to evaluate match
            if in_queue_len_r >= 4 then
              -- Compute 10-bit hash on 4 bytes: [B0, B1, B2, B3]
              v_hash_16 := resize(unsigned(in_queue_r(0)), 16) xor
                           shift_left(resize(unsigned(in_queue_r(1)), 16), 2) xor
                           shift_left(resize(unsigned(in_queue_r(2)), 16), 4) xor
                           shift_left(resize(unsigned(in_queue_r(3)), 16), 6);
              v_hash := to_integer(v_hash_16(4 downto 0));

              v_cand_pos := hash_ram_r(v_hash);
              v_match_found := false;

              if hash_valid_r(v_hash) then
                -- Calculate distance
                if stream_pos_r >= v_cand_pos then
                  v_offset := stream_pos_r - v_cand_pos;
                else
                  v_offset := (65536 + stream_pos_r) - v_cand_pos;
                end if;

                -- Check if candidate position is within sliding window and bytes match
                if v_offset > 0 and v_offset < c_window_size then
                  if history_ram_r(v_cand_pos mod c_window_size)       = in_queue_r(0) and
                     history_ram_r((v_cand_pos + 1) mod c_window_size) = in_queue_r(1) and
                     history_ram_r((v_cand_pos + 2) mod c_window_size) = in_queue_r(2) and
                     history_ram_r((v_cand_pos + 3) mod c_window_size) = in_queue_r(3) then
                    v_match_found := true;
                  end if;
                end if;
              end if;

              if v_match_found and out_queue_len_r <= 20 then
                -- MATCH HIT: Register match and transition to emit sequence
                match_offset_r <= v_offset;
                match_len_r    <= 4; -- Initial 4-byte match
                state_r        <= ST_EMIT_SEQUENCE;

              else
                -- LITERAL: Append byte 0 to literal buffer, store position in hash table
                lit_buf_r(lit_count_r) <= in_queue_r(0);
                lit_count_r            <= lit_count_r + 1;

                -- Write byte 0 to history buffer
                history_ram_r(stream_pos_r mod c_window_size) <= in_queue_r(0);
                hash_ram_r(v_hash)   <= stream_pos_r;
                hash_valid_r(v_hash) <= true;

                stream_pos_r <= (stream_pos_r + 1) mod 65536;

                -- Shift input queue by 1 byte
                for i in 0 to 6 loop
                  in_queue_r(i) <= in_queue_r(i + 1);
                end loop;
                in_queue_len_r <= in_queue_len_r - 1;

                -- If literal buffer is nearly full (15 bytes), flush as literal-only sequence
                if lit_count_r = 14 then
                  match_offset_r <= 0;
                  match_len_r    <= 0;
                  state_r        <= ST_EMIT_SEQUENCE;
                end if;
              end if;

            elsif in_last_seen_r then
              -- End of input stream: transition to flush remaining literals
              state_r <= ST_FLUSH_REMAINING;
            else
              -- Wait for more bytes
              state_r <= ST_INGEST_BEAT;
            end if;

          -- ------------------------------------------------------------------
          -- State: EMIT_SEQUENCE (Emit LZ4 Sequence Token, Literals, Offset)
          -- ------------------------------------------------------------------
          when ST_EMIT_SEQUENCE =>
            cycle_counter_r <= cycle_counter_r + 1;

            if out_queue_len_r <= 20 then
              -- Format Token: [LitLen (4 bits) | MatchLen-4 (4 bits)]
              if lit_count_r >= 15 then
                v_lit_nibble := x"F";
              else
                v_lit_nibble := to_unsigned(lit_count_r, 4);
              end if;

              if match_len_r >= 4 then
                v_match_nibble := to_unsigned(match_len_r - 4, 4);
              else
                v_match_nibble := x"0";
              end if;

              v_token := std_logic_vector(v_lit_nibble) & std_logic_vector(v_match_nibble);

              -- Append Token to out queue
              out_queue_r(out_queue_len_r) <= v_token;

              -- Append Literal Bytes
              for i in 0 to 14 loop
                if i < lit_count_r then
                  out_queue_r(out_queue_len_r + 1 + i) <= lit_buf_r(i);
                end if;
              end loop;

              -- Append Offset (16-bit little-endian) if match occurred
              if match_len_r >= 4 then
                out_queue_r(out_queue_len_r + 1 + lit_count_r)     <= std_logic_vector(to_unsigned(match_offset_r mod 256, 8));
                out_queue_r(out_queue_len_r + 1 + lit_count_r + 1) <= std_logic_vector(to_unsigned(match_offset_r / 256, 8));
                out_queue_len_r <= out_queue_len_r + 1 + lit_count_r + 2;

                -- Advance stream past matched bytes (4 bytes)
                for m in 0 to 3 loop
                  history_ram_r((stream_pos_r + m) mod c_window_size) <= in_queue_r(m);
                end loop;
                stream_pos_r <= (stream_pos_r + 4) mod 65536;

                -- Shift input queue by 4
                for k in 0 to 3 loop
                  in_queue_r(k) <= in_queue_r(k + 4);
                end loop;
                in_queue_len_r <= in_queue_len_r - 4;
              else
                out_queue_len_r <= out_queue_len_r + 1 + lit_count_r;
              end if;

              lit_count_r <= 0;
              state_r     <= ST_EVAL_STREAM;
            end if;

          -- ------------------------------------------------------------------
          -- State: FLUSH_REMAINING (Flush trailing literals at end of stream)
          -- ------------------------------------------------------------------
          when ST_FLUSH_REMAINING =>
            cycle_counter_r <= cycle_counter_r + 1;

            if out_queue_len_r <= 20 then
              -- Transfer any remaining bytes in in_queue to literal buffer
              if in_queue_len_r > 0 and lit_count_r < 15 then
                lit_buf_r(lit_count_r) <= in_queue_r(0);
                lit_count_r <= lit_count_r + 1;
                for i in 0 to 6 loop
                  in_queue_r(i) <= in_queue_r(i + 1);
                end loop;
                in_queue_len_r <= in_queue_len_r - 1;
              else
                -- Emit final literal sequence token (match length = 0, no offset)
                if lit_count_r > 0 then
                  v_lit_nibble := to_unsigned(lit_count_r, 4);
                  v_token := std_logic_vector(v_lit_nibble) & x"0";
                  out_queue_r(out_queue_len_r) <= v_token;
                  for j in 0 to 14 loop
                    if j < lit_count_r then
                      out_queue_r(out_queue_len_r + 1 + j) <= lit_buf_r(j);
                    end if;
                  end loop;
                  out_queue_len_r <= out_queue_len_r + 1 + lit_count_r;
                  lit_count_r     <= 0;
                end if;
                state_r <= ST_FINISH;
              end if;
            end if;

          -- ------------------------------------------------------------------
          -- State: FINISH (Wait for egress packer to drain, assert DONE & IRQ)
          -- ------------------------------------------------------------------
          when ST_FINISH =>
            cycle_counter_r <= cycle_counter_r + 1;

            if out_queue_len_r = 0 and pack_valid_r = '0' then
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
  -- Section 4: Output Port Assignments
  -- ==========================================================================
  m_axis_tdata  <= pack_word_r;
  m_axis_tkeep  <= pack_keep_r;
  m_axis_tvalid <= pack_valid_r;
  m_axis_tlast  <= pack_last_r;

  irq_o <= irq_pulse_r;

end architecture rtl;
