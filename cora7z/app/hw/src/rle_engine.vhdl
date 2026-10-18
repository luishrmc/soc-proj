library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- Entity: rle_engine
-- Description:
--   Hardware acceleration engine for Run-Length Encoding (RLE) lossless data
--   compression. Features an AXI4-Lite slave interface for control/status and
--   an AXI4-Stream slave/master interface for high-throughput streaming with
--   AXI DMA or local FIFOs on the Zynq-7010 SoC.
--
-- Token Format:
--   Each compressed run is encoded as a 16-bit tuple:
--     - Bits [7:0]  : Run Count (1 to 255)
--     - Bits [15:8] : Symbol Byte (literal character)
--   Two 16-bit tokens are packed into each 32-bit AXI4-Stream word.
-- ============================================================================

entity rle_engine is
  generic (
    -- Width of the AXI4-Lite address bus (4 KB range = 12 bits)
    c_s_axi_addr_width : integer := 12;
    -- Width of the AXI4-Lite data bus
    c_s_axi_data_width : integer := 32;
    -- Width of the streaming data bus
    c_axis_data_width  : integer := 32
  );
  port (
    -- Global Synchronous Clock and Active-Low Reset
    aclk           : in  std_logic;
    aresetn        : in  std_logic;

    -- Interrupt Output (Active-high completion pulse to ARM GIC)
    irq_o          : out std_logic;

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
    -- AXI4-Stream Slave Interface (Uncompressed Ingress Stream from DMA)
    -- ========================================================================
    s_axis_tdata   : in  std_logic_vector(c_axis_data_width - 1 downto 0);
    s_axis_tkeep   : in  std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    s_axis_tvalid  : in  std_logic;
    s_axis_tready  : out std_logic;
    s_axis_tlast   : in  std_logic;

    -- ========================================================================
    -- AXI4-Stream Master Interface (Compressed Egress Stream to DMA)
    -- ========================================================================
    m_axis_tdata   : out std_logic_vector(c_axis_data_width - 1 downto 0);
    m_axis_tkeep   : out std_logic_vector((c_axis_data_width / 8) - 1 downto 0);
    m_axis_tvalid  : out std_logic;
    m_axis_tready  : in  std_logic;
    m_axis_tlast   : out std_logic
  );

  -- ==========================================================================
  -- Vivado IP Integrator Clock and Reset Association
  -- ==========================================================================
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of aclk    : signal is "ASSOCIATED_BUSIF s_axi_lite:s_axis:m_axis, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";
end entity rle_engine;

architecture rtl of rle_engine is

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

  -- Control bits
  signal ctrl_start_s      : std_logic;
  signal ctrl_reset_core_s : std_logic;
  signal ctrl_irq_en_s     : std_logic;

  -- --------------------------------------------------------------------------
  -- Compression Datapath Signals
  -- --------------------------------------------------------------------------
  type t_fsm_state is (
    ST_IDLE,
    ST_RUNNING,
    ST_FLUSH_TOKEN,
    ST_FINISH
  );
  signal state_r : t_fsm_state := ST_IDLE;

  -- Byte Unpacker (consumes 32-bit beat into four 8-bit bytes)
  signal in_word_r      : std_logic_vector(31 downto 0) := (others => '0');
  signal in_keep_r      : std_logic_vector(3 downto 0)  := (others => '0');
  signal in_last_r      : std_logic := '0';
  signal in_byte_idx_r  : integer range 0 to 4 := 0;
  signal in_valid_r     : std_logic := '0';

  -- Active Run State
  signal run_active_r   : boolean := false;
  signal run_symbol_r   : std_logic_vector(7 downto 0) := (others => '0');
  signal run_count_r    : integer range 0 to 255 := 0;

  -- Output Token Packer (packs two 16-bit tokens into one 32-bit beat)
  signal out_word_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal out_keep_r     : std_logic_vector(3 downto 0)  := (others => '0');
  signal out_slot_r     : integer range 0 to 1 := 0;
  signal out_valid_r    : std_logic := '0';
  signal out_last_r     : std_logic := '0';

  -- Counters
  signal byte_counter_in_r  : unsigned(31 downto 0) := (others => '0');
  signal byte_counter_out_r : unsigned(31 downto 0) := (others => '0');
  signal cycle_counter_r    : unsigned(31 downto 0) := (others => '0');

  -- Internal handshake
  signal s_axis_ready_s : std_logic;
  signal irq_pulse_r    : std_logic := '0';

begin

  -- ==========================================================================
  -- Section 1: AXI4-Lite Control & Status Registers
  -- ==========================================================================
  ctrl_start_s      <= reg_control_r(0);
  ctrl_reset_core_s <= reg_control_r(1);
  ctrl_irq_en_s     <= reg_control_r(2);

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
        -- Write Address / Write Data handshakes
        if (s_axi_lite_awvalid = '1' and axi_awready_r = '0') and
           (s_axi_lite_wvalid = '1' and axi_wready_r = '0') then
          axi_awready_r <= '1';
          axi_wready_r  <= '1';

          -- Address decode (Bits 7 downto 0)
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

        -- Write Response Channel
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

          -- Address decode for read
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
  -- Section 2: Ingress Stream Flow Control
  -- ==========================================================================
  -- Ready to accept a new 32-bit beat when unpacker is empty and output buffer is not stalled
  s_axis_ready_s <= '1' when (state_r = ST_RUNNING and in_valid_r = '0' and (out_valid_r = '0' or m_axis_tready = '1')) else '0';
  s_axis_tready  <= s_axis_ready_s;

  -- ==========================================================================
  -- Section 3: Run-Length Compression Engine & Datapath FSM
  -- ==========================================================================
  process (aclk)
    variable v_curr_byte : std_logic_vector(7 downto 0);
  begin
    if rising_edge(aclk) then
      if aresetn = '0' or ctrl_reset_core_s = '1' then
        state_r            <= ST_IDLE;
        in_valid_r         <= '0';
        in_byte_idx_r      <= 0;
        run_active_r       <= false;
        run_symbol_r       <= (others => '0');
        run_count_r        <= 0;
        out_word_r         <= (others => '0');
        out_keep_r         <= (others => '0');
        out_slot_r         <= 0;
        out_valid_r        <= '0';
        out_last_r         <= '0';
        reg_status_r       <= (others => '0');
        byte_counter_in_r  <= (others => '0');
        byte_counter_out_r <= (others => '0');
        cycle_counter_r    <= (others => '0');
        irq_pulse_r        <= '0';
      else
        irq_pulse_r <= '0';

        -- Clear out_valid_r when downstream handshake completes
        if out_valid_r = '1' and m_axis_tready = '1' then
          out_valid_r <= '0';
          out_last_r  <= '0';
        end if;

        case state_r is

          -- ------------------------------------------------------------------
          -- State: IDLE (Waiting for start trigger or incoming stream)
          -- ------------------------------------------------------------------
          when ST_IDLE =>
            reg_status_r(0) <= '0'; -- BUSY = 0
            in_valid_r      <= '0';
            in_byte_idx_r   <= 0;
            run_active_r    <= false;
            run_count_r     <= 0;
            out_slot_r      <= 0;
            out_valid_r     <= '0';
            out_last_r      <= '0';

            -- Trigger when START bit is asserted or stream valid arrives
            if ctrl_start_s = '1' or s_axis_tvalid = '1' then
              state_r            <= ST_RUNNING;
              reg_status_r(0)    <= '1'; -- BUSY = 1
              reg_status_r(1)    <= '0'; -- DONE = 0
              reg_status_r(2)    <= '0'; -- ERR = 0
              byte_counter_in_r  <= (others => '0');
              byte_counter_out_r <= (others => '0');
              cycle_counter_r    <= (others => '0');
            end if;

          -- ------------------------------------------------------------------
          -- State: RUNNING (Processing stream bytes)
          -- ------------------------------------------------------------------
          when ST_RUNNING =>
            cycle_counter_r <= cycle_counter_r + 1;

            -- 1. Ingest new 32-bit beat if unpacker is empty
            if in_valid_r = '0' then
              if s_axis_tvalid = '1' and s_axis_ready_s = '1' then
                in_word_r     <= s_axis_tdata;
                in_keep_r     <= s_axis_tkeep;
                in_last_r     <= s_axis_tlast;
                in_byte_idx_r <= 0;
                in_valid_r    <= '1';
              end if;

            -- 2. Consume one byte from the unpacker per cycle (if output slot available)
            elsif out_valid_r = '0' or m_axis_tready = '1' then

              -- Check if current byte index is valid per tkeep
              if in_byte_idx_r < 4 and in_keep_r(in_byte_idx_r) = '1' then

                -- Extract byte according to little-endian index
                case in_byte_idx_r is
                  when 0 => v_curr_byte := in_word_r(7 downto 0);
                  when 1 => v_curr_byte := in_word_r(15 downto 8);
                  when 2 => v_curr_byte := in_word_r(23 downto 16);
                  when 3 => v_curr_byte := in_word_r(31 downto 24);
                  when others => v_curr_byte := (others => '0');
                end case;

                byte_counter_in_r <= byte_counter_in_r + 1;

                -- RLE Accumulation Logic
                if not run_active_r then
                  -- First symbol in stream
                  run_symbol_r <= v_curr_byte;
                  run_count_r  <= 1;
                  run_active_r <= true;
                else
                  if v_curr_byte = run_symbol_r then
                    if run_count_r = 255 then
                      -- Saturated run: emit [255, symbol] and start new count at 1
                      if out_slot_r = 0 then
                        out_word_r(15 downto 0) <= v_curr_byte & std_logic_vector(to_unsigned(255, 8));
                        out_keep_r              <= "0011";
                        out_slot_r              <= 1;
                      else
                        out_word_r(31 downto 16) <= v_curr_byte & std_logic_vector(to_unsigned(255, 8));
                        out_keep_r               <= "1111";
                        out_valid_r              <= '1';
                        out_slot_r               <= 0;
                      end if;
                      byte_counter_out_r <= byte_counter_out_r + 2;
                      run_count_r        <= 1;
                    else
                      -- Increment run length
                      run_count_r <= run_count_r + 1;
                    end if;
                  else
                    -- Run broken: emit [run_count, run_symbol] and switch to new symbol
                    if out_slot_r = 0 then
                      out_word_r(15 downto 0) <= run_symbol_r & std_logic_vector(to_unsigned(run_count_r, 8));
                      out_keep_r              <= "0011";
                      out_slot_r              <= 1;
                    else
                      out_word_r(31 downto 16) <= run_symbol_r & std_logic_vector(to_unsigned(run_count_r, 8));
                      out_keep_r               <= "1111";
                      out_valid_r              <= '1';
                      out_slot_r               <= 0;
                    end if;
                    byte_counter_out_r <= byte_counter_out_r + 2;
                    run_symbol_r       <= v_curr_byte;
                    run_count_r        <= 1;
                  end if;
                end if;

                -- Check if this was the last valid byte of the beat
                if in_byte_idx_r = 3 or (in_byte_idx_r < 3 and in_keep_r(in_byte_idx_r + 1) = '0') then
                  in_valid_r <= '0';
                  -- If tlast was set, transition to flush pending run
                  if in_last_r = '1' then
                    state_r <= ST_FLUSH_TOKEN;
                  end if;
                else
                  in_byte_idx_r <= in_byte_idx_r + 1;
                end if;

              else
                -- Inactive byte lanes
                in_valid_r <= '0';
                if in_last_r = '1' then
                  state_r <= ST_FLUSH_TOKEN;
                end if;
              end if;
            end if;

          -- ------------------------------------------------------------------
          -- State: FLUSH_TOKEN (Flush final accumulated run tuple)
          -- ------------------------------------------------------------------
          when ST_FLUSH_TOKEN =>
            cycle_counter_r <= cycle_counter_r + 1;

            if out_valid_r = '0' or m_axis_tready = '1' then
              if run_active_r then
                if out_slot_r = 0 then
                  -- Final token is at slot 0 (half word: 2 bytes)
                  out_word_r(15 downto 0)  <= run_symbol_r & std_logic_vector(to_unsigned(run_count_r, 8));
                  out_word_r(31 downto 16) <= (others => '0');
                  out_keep_r               <= "0011";
                  out_valid_r              <= '1';
                  out_last_r               <= '1';
                else
                  -- Final token fills slot 1 (full word: 4 bytes)
                  out_word_r(31 downto 16) <= run_symbol_r & std_logic_vector(to_unsigned(run_count_r, 8));
                  out_keep_r               <= "1111";
                  out_valid_r              <= '1';
                  out_last_r               <= '1';
                end if;
                byte_counter_out_r <= byte_counter_out_r + 2;
                run_active_r       <= false;
              end if;
              state_r <= ST_FINISH;
            end if;

          -- ------------------------------------------------------------------
          -- State: FINISH (Wait for final handshake, assert DONE & IRQ)
          -- ------------------------------------------------------------------
          when ST_FINISH =>
            cycle_counter_r <= cycle_counter_r + 1;

            -- Wait until final beat is acknowledged
            if out_valid_r = '0' or m_axis_tready = '1' then
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
  m_axis_tdata  <= out_word_r;
  m_axis_tkeep  <= out_keep_r;
  m_axis_tvalid <= out_valid_r;
  m_axis_tlast  <= out_last_r;

  irq_o <= irq_pulse_r;

end architecture rtl;
