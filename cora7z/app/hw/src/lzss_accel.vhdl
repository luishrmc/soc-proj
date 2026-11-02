--------------------------------------------------------------------------------
-- Project: High-Performance PS/PL Acceleration on Zynq-7010
-- File:    lzss_accel.vhdl
-- Entity:  lzss_accel
-- Author:  Antigravity AI / Luis H. R. M. C.
-- Standard: VHDL-2008 (IEEE 1076-2008)
--
-- Description:
--   Hardware Dictionary Compression Coprocessor implementing sliding-window
--   LZSS (Heatshrink-compatible) adapted for True Dual-Port BRAM communication
--   with the ARM Cortex-A9 Processing System (ADR-012, ADR-017).
--
-- Specifications:
--   - Window Size: 256 bytes (8-bit distance offset in token).
--   - Lookahead: 16 bytes (3 to 16 bytes match length).
--   - Minimum Match: 3 bytes.
--   - Framing: 16-bit Big-Endian uncompressed length header + 8-token flag chunks.
--   - Token format: Literal (1 byte) or Match (2 bytes: dist-1, len-3).
--   - Standard AXI4-Lite CSR register map at 0x43C00000.
--   - Dual-Port BRAM Port B (bram_in and bram_out) synchronous interfaces.
--   - 32-bit hardware cycle counter measuring compute cycles from START to DONE.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lzss_accel is
  generic (
    c_s_axi_addr_width : integer := 12;
    c_s_axi_data_width : integer := 32;
    c_window_size      : integer := 256;
    c_max_lookahead    : integer := 16;
    c_min_match        : integer := 3
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
end entity lzss_accel;

architecture rtl of lzss_accel is

  -- Register Map Storage (AXI4-Lite)
  signal reg_control_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_status_r      : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_src_len_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_dst_len_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_cycle_count_r : unsigned(31 downto 0) := (others => '0');

  -- Control pulses
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

  -- Lookahead Buffer (16 bytes = 128 FFs)
  type lookahead_t is array (0 to c_max_lookahead - 1) of std_logic_vector(7 downto 0);
  signal lookahead_r : lookahead_t := (others => (others => '0'));

  -- Compression Engine FSM States
  type fsm_state_t is (
    ST_IDLE,
    ST_WRITE_HDR_0,
    ST_WRITE_HDR_1,
    ST_INIT_LA_REQ,
    ST_INIT_LA_WAIT,
    ST_LOAD_LA_REQ,
    ST_LOAD_LA_WAIT,
    ST_START_CHUNK,
    ST_EVAL_TOKEN,
    ST_SEARCH_REQ,
    ST_SEARCH_WAIT,
    ST_CMP_REQ,
    ST_CMP_WAIT,
    ST_EMIT_MATCH_0,
    ST_EMIT_MATCH_1,
    ST_EMIT_LITERAL,
    ST_FLUSH_FLAG,
    ST_DONE
  );
  signal state_r : fsm_state_t := ST_IDLE;

  -- Indexing and Search Registers
  signal in_idx_r        : unsigned(15 downto 0) := (others => '0');
  signal out_idx_r       : unsigned(15 downto 0) := (others => '0');
  signal flag_idx_r      : unsigned(15 downto 0) := (others => '0');
  signal flag_mask_r     : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_cnt_r       : integer range 0 to 8 := 0;

  signal la_load_idx_r   : integer range 0 to c_max_lookahead := 0;
  signal la_valid_len_r  : integer range 0 to c_max_lookahead := 0;

  signal cand_idx_r      : unsigned(15 downto 0) := (others => '0');
  signal match_len_r     : integer range 0 to c_max_lookahead := 0;
  signal best_len_r      : integer range 0 to c_max_lookahead := 0;
  signal best_dist_r     : unsigned(15 downto 0) := (others => '0');
  signal bram_wait_r     : std_logic := '0';

  -- Function to extract byte from 32-bit word at given byte address
  function extract_byte(word : std_logic_vector(31 downto 0); addr : unsigned(15 downto 0)) return std_logic_vector is
  begin
    case addr(1 downto 0) is
      when "00" => return word(7 downto 0);
      when "01" => return word(15 downto 8);
      when "10" => return word(23 downto 16);
      when others => return word(31 downto 24);
    end case;
  end function extract_byte;

begin

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
        axi_awready_r <= '0';
        axi_wready_r  <= '0';
        axi_bvalid_r  <= '0';
        reg_control_r <= (others => '0');
        reg_src_len_r <= (others => '0');
        start_pulse_s <= '0';
        reset_core_s  <= '0';
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
  -- 3. Main LZSS Compression FSM & BRAM Datapath
  ------------------------------------------------------------------------------
  p_lzss_fsm : process(aclk)
    variable v_read_byte  : std_logic_vector(7 downto 0);
    variable v_rem_stream : integer;
    variable v_max_la     : integer;
    variable v_win_start  : unsigned(15 downto 0);
  begin
    if rising_edge(aclk) then
      if aresetn = '0' or reset_core_s = '1' then
        state_r           <= ST_IDLE;
        reg_status_r      <= (others => '0');
        reg_dst_len_r     <= (others => '0');
        reg_cycle_count_r <= (others => '0');
        irq_r             <= '0';
        in_idx_r          <= (others => '0');
        out_idx_r         <= (others => '0');
        flag_idx_r        <= (others => '0');
        flag_mask_r       <= (others => '0');
        bit_cnt_r         <= 0;
        la_load_idx_r     <= 0;
        la_valid_len_r    <= 0;
        cand_idx_r        <= (others => '0');
        match_len_r       <= 0;
        best_len_r        <= 0;
        best_dist_r       <= (others => '0');
        bram_wait_r       <= '0';
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

        -- Hardware cycle counter instrumentation
        if state_r /= ST_IDLE and state_r /= ST_DONE then
          reg_cycle_count_r <= reg_cycle_count_r + 1;
        end if;

        case state_r is

          ----------------------------------------------------------------------
          -- ST_IDLE: Awaiting Start Command from Cortex-A9
          ----------------------------------------------------------------------
          when ST_IDLE =>
            irq_r <= '0';
            if start_pulse_s = '1' then
              reg_status_r(0)   <= '1'; -- BUSY = 1
              reg_status_r(1)   <= '0'; -- DONE = 0
              reg_status_r(2)   <= '0'; -- ERR = 0
              reg_cycle_count_r <= (others => '0');
              in_idx_r          <= (others => '0');
              out_idx_r         <= (others => '0');

              if unsigned(reg_src_len_r) = 0 then
                -- Zero length frame
                reg_dst_len_r <= (others => '0');
                state_r       <= ST_DONE;
              else
                state_r <= ST_WRITE_HDR_0;
              end if;
            end if;

          ----------------------------------------------------------------------
          -- ST_WRITE_HDR_0: Write 16-bit Big-Endian Header MSB
          ----------------------------------------------------------------------
          when ST_WRITE_HDR_0 =>
            bram_out_addr <= (others => '0'); -- Address 0
            bram_out_din(7 downto 0) <= reg_src_len_r(15 downto 8);
            bram_out_din(31 downto 8) <= (others => '0');
            bram_out_we   <= "0001";
            bram_out_en   <= '1';
            out_idx_r     <= to_unsigned(1, 16);
            state_r       <= ST_WRITE_HDR_1;

          ----------------------------------------------------------------------
          -- ST_WRITE_HDR_1: Write 16-bit Big-Endian Header LSB
          ----------------------------------------------------------------------
          when ST_WRITE_HDR_1 =>
            bram_out_addr <= (others => '0'); -- Address 0, byte lane 1
            bram_out_din(15 downto 8) <= reg_src_len_r(7 downto 0);
            bram_out_din(7 downto 0)   <= (others => '0');
            bram_out_din(31 downto 16) <= (others => '0');
            bram_out_we   <= "0010";
            bram_out_en   <= '1';
            out_idx_r     <= to_unsigned(2, 16);

            -- Calculate lookahead capacity
            v_rem_stream := to_integer(unsigned(reg_src_len_r) - in_idx_r);
            if v_rem_stream > c_max_lookahead then
              la_valid_len_r <= c_max_lookahead;
            else
              la_valid_len_r <= v_rem_stream;
            end if;

            la_load_idx_r <= 0;
            state_r       <= ST_INIT_LA_REQ;

          ----------------------------------------------------------------------
          -- ST_INIT_LA_REQ / ST_INIT_LA_WAIT: Initial Lookahead Buffer Load
          ----------------------------------------------------------------------
          when ST_INIT_LA_REQ =>
            if la_load_idx_r < la_valid_len_r then
              bram_in_addr <= std_logic_vector(resize((in_idx_r + to_unsigned(la_load_idx_r, 16)) and x"FFFC", 32));
              bram_in_en   <= '1';
              state_r      <= ST_INIT_LA_WAIT;
            else
              state_r <= ST_START_CHUNK;
            end if;

          when ST_INIT_LA_WAIT =>
            if bram_wait_r = '0' then
              bram_wait_r <= '1';
            else
              bram_wait_r <= '0';
              v_read_byte := extract_byte(bram_in_dout, in_idx_r + to_unsigned(la_load_idx_r, 16));
              lookahead_r(la_load_idx_r) <= v_read_byte;
              la_load_idx_r <= la_load_idx_r + 1;
              state_r       <= ST_INIT_LA_REQ;
            end if;

          ----------------------------------------------------------------------
          -- ST_LOAD_LA_REQ / ST_LOAD_LA_WAIT: Reload Lookahead After Token
          ----------------------------------------------------------------------
          when ST_LOAD_LA_REQ =>
            if la_load_idx_r < la_valid_len_r then
              -- Address aligned to 32-bit word boundary
              bram_in_addr <= std_logic_vector(resize((in_idx_r + to_unsigned(la_load_idx_r, 16)) and x"FFFC", 32));
              bram_in_en   <= '1';
              state_r      <= ST_LOAD_LA_WAIT;
            else
              -- Lookahead buffer reloaded; continue evaluating tokens in chunk
              state_r <= ST_EVAL_TOKEN;
            end if;

          ----------------------------------------------------------------------
          -- ST_LOAD_LA_WAIT: Sample Byte into Lookahead Buffer
          ----------------------------------------------------------------------
          when ST_LOAD_LA_WAIT =>
            if bram_wait_r = '0' then
              bram_wait_r <= '1';
            else
              bram_wait_r <= '0';
              v_read_byte := extract_byte(bram_in_dout, in_idx_r + to_unsigned(la_load_idx_r, 16));
              lookahead_r(la_load_idx_r) <= v_read_byte;
              la_load_idx_r <= la_load_idx_r + 1;
              state_r       <= ST_LOAD_LA_REQ;
            end if;

          ----------------------------------------------------------------------
          -- ST_START_CHUNK: Reserve 1 Byte for 8-Token Flag Bitmask
          ----------------------------------------------------------------------
          when ST_START_CHUNK =>
            flag_idx_r  <= out_idx_r;
            out_idx_r   <= out_idx_r + 1;
            flag_mask_r <= (others => '0');
            bit_cnt_r   <= 0;
            state_r     <= ST_EVAL_TOKEN;

          ----------------------------------------------------------------------
          -- ST_EVAL_TOKEN: Determine Match Search vs. Chunk Boundary
          ----------------------------------------------------------------------
          when ST_EVAL_TOKEN =>
            if in_idx_r >= unsigned(reg_src_len_r) then
              -- End of input stream reached; flush active chunk
              state_r <= ST_FLUSH_FLAG;
            elsif bit_cnt_r = 8 then
              -- Current 8-token chunk completed; flush flag mask and begin new chunk
              state_r <= ST_FLUSH_FLAG;
            elsif la_valid_len_r >= c_min_match then
              -- Initialize sliding window search bounds [win_start, in_idx)
              if in_idx_r > to_unsigned(c_window_size, 16) then
                v_win_start := in_idx_r - to_unsigned(c_window_size, 16);
              else
                v_win_start := (others => '0');
              end if;

              cand_idx_r  <= v_win_start;
              best_len_r  <= 0;
              best_dist_r <= (others => '0');
              state_r     <= ST_SEARCH_REQ;
            else
              -- Fewer than 3 bytes remain in lookahead; emit literal directly
              state_r <= ST_EMIT_LITERAL;
            end if;

          ----------------------------------------------------------------------
          -- ST_SEARCH_REQ: Inspect Candidate Byte in History Window
          ----------------------------------------------------------------------
          when ST_SEARCH_REQ =>
            if cand_idx_r >= in_idx_r or best_len_r = la_valid_len_r then
              -- Search finished across all candidates
              if best_len_r >= c_min_match then
                state_r <= ST_EMIT_MATCH_0;
              else
                state_r <= ST_EMIT_LITERAL;
              end if;
            else
              -- Request candidate start byte
              bram_in_addr <= std_logic_vector(resize(cand_idx_r and x"FFFC", 32));
              bram_in_en   <= '1';
              state_r      <= ST_SEARCH_WAIT;
            end if;

          ----------------------------------------------------------------------
          -- ST_SEARCH_WAIT: Compare Initial Byte of Candidate
          ----------------------------------------------------------------------
          when ST_SEARCH_WAIT =>
            if bram_wait_r = '0' then
              bram_wait_r <= '1';
            else
              bram_wait_r <= '0';
              v_read_byte := extract_byte(bram_in_dout, cand_idx_r);
              if v_read_byte = lookahead_r(0) then
                -- Match candidate begins; compare remaining lookahead bytes
                match_len_r <= 1;
                state_r     <= ST_CMP_REQ;
              else
                -- Mismatch on first byte; advance to next candidate
                cand_idx_r <= cand_idx_r + 1;
                state_r    <= ST_SEARCH_REQ;
              end if;
            end if;

          ----------------------------------------------------------------------
          -- ST_CMP_REQ: Request match_len Byte from Candidate
          ----------------------------------------------------------------------
          when ST_CMP_REQ =>
            bram_in_addr <= std_logic_vector(resize((cand_idx_r + to_unsigned(match_len_r, 16)) and x"FFFC", 32));
            bram_in_en   <= '1';
            state_r      <= ST_CMP_WAIT;

          ----------------------------------------------------------------------
          -- ST_CMP_WAIT: Evaluate Match Extension
          ----------------------------------------------------------------------
          when ST_CMP_WAIT =>
            if bram_wait_r = '0' then
              bram_wait_r <= '1';
            else
              bram_wait_r <= '0';
              v_read_byte := extract_byte(bram_in_dout, cand_idx_r + to_unsigned(match_len_r, 16));
              if v_read_byte = lookahead_r(match_len_r) then
                if match_len_r + 1 = la_valid_len_r then
                  -- Reached maximum possible lookahead match
                  if match_len_r + 1 > best_len_r then
                    best_len_r  <= match_len_r + 1;
                    best_dist_r <= in_idx_r - cand_idx_r;
                  end if;
                  cand_idx_r <= cand_idx_r + 1;
                  state_r    <= ST_SEARCH_REQ;
                else
                  match_len_r <= match_len_r + 1;
                  state_r     <= ST_CMP_REQ;
                end if;
              else
                -- Match ends
                if match_len_r >= c_min_match and match_len_r > best_len_r then
                  best_len_r  <= match_len_r;
                  best_dist_r <= in_idx_r - cand_idx_r;
                end if;
                cand_idx_r <= cand_idx_r + 1;
                state_r    <= ST_SEARCH_REQ;
              end if;
            end if;

          ----------------------------------------------------------------------
          -- ST_EMIT_MATCH_0: Emit 2-Byte Match Token Byte 0 (dist - 1)
          ----------------------------------------------------------------------
          when ST_EMIT_MATCH_0 =>
            flag_mask_r(bit_cnt_r) <= '1'; -- Flag bit = 1 (MATCH)

            bram_out_addr <= std_logic_vector(resize(out_idx_r and x"FFFC", 32));
            bram_out_en   <= '1';

            case out_idx_r(1 downto 0) is
              when "00" =>
                bram_out_din(7 downto 0) <= std_logic_vector(best_dist_r(7 downto 0) - 1);
                bram_out_we <= "0001";
              when "01" =>
                bram_out_din(15 downto 8) <= std_logic_vector(best_dist_r(7 downto 0) - 1);
                bram_out_we <= "0010";
              when "10" =>
                bram_out_din(23 downto 16) <= std_logic_vector(best_dist_r(7 downto 0) - 1);
                bram_out_we <= "0100";
              when others =>
                bram_out_din(31 downto 24) <= std_logic_vector(best_dist_r(7 downto 0) - 1);
                bram_out_we <= "1000";
            end case;

            out_idx_r <= out_idx_r + 1;
            state_r   <= ST_EMIT_MATCH_1;

          ----------------------------------------------------------------------
          -- ST_EMIT_MATCH_1: Emit 2-Byte Match Token Byte 1 (len - 3)
          ----------------------------------------------------------------------
          when ST_EMIT_MATCH_1 =>
            bram_out_addr <= std_logic_vector(resize(out_idx_r and x"FFFC", 32));
            bram_out_en   <= '1';

            case out_idx_r(1 downto 0) is
              when "00" =>
                bram_out_din(7 downto 0) <= std_logic_vector(to_unsigned(best_len_r - c_min_match, 8));
                bram_out_we <= "0001";
              when "01" =>
                bram_out_din(15 downto 8) <= std_logic_vector(to_unsigned(best_len_r - c_min_match, 8));
                bram_out_we <= "0010";
              when "10" =>
                bram_out_din(23 downto 16) <= std_logic_vector(to_unsigned(best_len_r - c_min_match, 8));
                bram_out_we <= "0100";
              when others =>
                bram_out_din(31 downto 24) <= std_logic_vector(to_unsigned(best_len_r - c_min_match, 8));
                bram_out_we <= "1000";
            end case;

            out_idx_r <= out_idx_r + 1;
            in_idx_r  <= in_idx_r + to_unsigned(best_len_r, 16);
            bit_cnt_r <= bit_cnt_r + 1;

            -- Reload Lookahead Buffer from new in_idx position
            v_rem_stream := to_integer(unsigned(reg_src_len_r) - (in_idx_r + to_unsigned(best_len_r, 16)));
            if v_rem_stream > c_max_lookahead then
              la_valid_len_r <= c_max_lookahead;
            elsif v_rem_stream > 0 then
              la_valid_len_r <= v_rem_stream;
            else
              la_valid_len_r <= 0;
            end if;

            la_load_idx_r <= 0;
            state_r       <= ST_LOAD_LA_REQ;

          ----------------------------------------------------------------------
          -- ST_EMIT_LITERAL: Emit 1-Byte Uncompressed Literal (Flag bit = 0)
          ----------------------------------------------------------------------
          when ST_EMIT_LITERAL =>
            -- Flag bit remains 0 for literal
            bram_out_addr <= std_logic_vector(resize(out_idx_r and x"FFFC", 32));
            bram_out_en   <= '1';

            case out_idx_r(1 downto 0) is
              when "00" =>
                bram_out_din(7 downto 0) <= lookahead_r(0);
                bram_out_we <= "0001";
              when "01" =>
                bram_out_din(15 downto 8) <= lookahead_r(0);
                bram_out_we <= "0010";
              when "10" =>
                bram_out_din(23 downto 16) <= lookahead_r(0);
                bram_out_we <= "0100";
              when others =>
                bram_out_din(31 downto 24) <= lookahead_r(0);
                bram_out_we <= "1000";
            end case;

            out_idx_r <= out_idx_r + 1;
            in_idx_r  <= in_idx_r + 1;
            bit_cnt_r <= bit_cnt_r + 1;

            -- Reload Lookahead Buffer from new in_idx position
            v_rem_stream := to_integer(unsigned(reg_src_len_r) - (in_idx_r + 1));
            if v_rem_stream > c_max_lookahead then
              la_valid_len_r <= c_max_lookahead;
            elsif v_rem_stream > 0 then
              la_valid_len_r <= v_rem_stream;
            else
              la_valid_len_r <= 0;
            end if;

            la_load_idx_r <= 0;
            state_r       <= ST_LOAD_LA_REQ;

          ----------------------------------------------------------------------
          -- ST_FLUSH_FLAG: Write Back Accumulated Flag Bitmask to Chunk Header
          ----------------------------------------------------------------------
          when ST_FLUSH_FLAG =>
            bram_out_addr <= std_logic_vector(resize(flag_idx_r and x"FFFC", 32));
            bram_out_en   <= '1';

            case flag_idx_r(1 downto 0) is
              when "00" =>
                bram_out_din(7 downto 0) <= flag_mask_r;
                bram_out_we <= "0001";
              when "01" =>
                bram_out_din(15 downto 8) <= flag_mask_r;
                bram_out_we <= "0010";
              when "10" =>
                bram_out_din(23 downto 16) <= flag_mask_r;
                bram_out_we <= "0100";
              when others =>
                bram_out_din(31 downto 24) <= flag_mask_r;
                bram_out_we <= "1000";
            end case;

            if in_idx_r < unsigned(reg_src_len_r) then
              -- Stream continues; start next 8-token chunk
              state_r <= ST_START_CHUNK;
            else
              -- Compression complete!
              reg_dst_len_r <= std_logic_vector(resize(out_idx_r, 32));
              state_r       <= ST_DONE;
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
  end process p_lzss_fsm;

end architecture rtl;
