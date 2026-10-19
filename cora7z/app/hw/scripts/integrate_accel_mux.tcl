# ==============================================================================
# integrate_accel_mux.tcl: Integrates axis_accel_mux into soc_final_bd_1.bd
#
# - Sets axi_dma_0 buffer length width to 23 bits (up to 8 MB, covers 64 KB)
# - Adds axis_accel_mux.vhdl to project sources
# - Instantiates axis_accel_mux_0 module reference in the Block Design
# - Connects AXI-Lite control port (M06_AXI @ 0x43C40000)
# - Connects core busy indicators (busy_o from RLE, LZ4, AES, ChaCha)
# - Connects AXI DMA MM2S / S2MM through the mux to all 4 accelerators:
#     * RLE: direct stream connection
#     * LZ4: direct stream connection (removes const_zero tie-off)
#     * AES-CTR: routed through axis_fifo_aes_in / axis_fifo_aes_out (ADR-012)
#     * ChaCha20: routed through axis_fifo_chacha_in / axis_fifo_chacha_out (ADR-012)
# - Validates Block Design and saves it
# ==============================================================================

set user_home $::env(HOME)
set board_repo "$user_home/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards"
if {[file exists $board_repo]} {
    set_param board.repoPaths [list $board_repo]
}

open_project cora7z/app/hw/vivado/soc-final.xpr
set_property board_part digilentinc.com:cora-z7-10:part0:1.1 [current_project]

puts "--- 1. Adding axis_accel_mux.vhdl to project sources ---"
catch { add_files -norecurse cora7z/app/hw/src/axis_accel_mux.vhdl }
update_compile_order -fileset sources_1

puts "--- 2. Opening Block Design ---"
open_bd_design [get_files *.bd]

puts "--- 2b. Updating module references to reflect new RTL ports ---"
update_module_reference [get_ips *engine*]

# Get common clock and reset nets (100 MHz Domain)
set clk_net [get_bd_nets -of_objects [get_bd_pins processing_system7_0/FCLK_CLK1]]
set rst_net [get_bd_nets -of_objects [get_bd_pins rst_ps7_100M/peripheral_aresetn]]

puts "--- 3. Configuring AXI DMA Buffer Length Width (23 bits = 8 MB) ---"
set_property -dict [list CONFIG.c_sg_length_width {23}] [get_bd_cells axi_dma_0]

puts "--- 4. Cleaning up previous temporary stream connections ---"
# Disconnect direct DMA to RLE connections if present
catch { delete_bd_objs [get_bd_intf_nets -of_objects [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S]] }
catch { delete_bd_objs [get_bd_intf_nets -of_objects [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]] }
catch { delete_bd_objs [get_bd_intf_nets -of_objects [get_bd_intf_pins rle_engine_0/s_axis]] }
catch { delete_bd_objs [get_bd_intf_nets -of_objects [get_bd_intf_pins rle_engine_0/m_axis]] }

# Disconnect const_zero from LZ4 and remove const_zero
catch { delete_bd_objs [get_bd_nets -of_objects [get_bd_pins lz4_engine_0/s_axis_tvalid]] }
if {[get_bd_cells -quiet const_zero] ne ""} {
    delete_bd_objs [get_bd_cells const_zero]
}

puts "--- 5. Instantiating axis_accel_mux_0 ---"
if {[get_bd_cells -quiet axis_accel_mux_0] ne ""} {
    delete_bd_objs [get_bd_cells axis_accel_mux_0]
}
create_bd_cell -type module -reference axis_accel_mux axis_accel_mux_0

# Connect Clock and Reset (100 MHz Domain)
connect_bd_net -net $clk_net [get_bd_pins axis_accel_mux_0/aclk]
connect_bd_net -net $rst_net [get_bd_pins axis_accel_mux_0/aresetn]

puts "--- 6. Connecting Core BUSY Indicators to Multiplexer ---"
connect_bd_net [get_bd_pins rle_engine_0/busy_o]      [get_bd_pins axis_accel_mux_0/busy_rle_i]
connect_bd_net [get_bd_pins lz4_engine_0/busy_o]      [get_bd_pins axis_accel_mux_0/busy_lz4_i]
connect_bd_net [get_bd_pins aes_ctr_engine_0/busy_o]  [get_bd_pins axis_accel_mux_0/busy_aes_i]
connect_bd_net [get_bd_pins chacha20_engine_0/busy_o] [get_bd_pins axis_accel_mux_0/busy_chacha_i]

puts "--- 7. Connecting AXI-Lite Slave Interface (M06_AXI @ 0x43C40000) ---"
set_property CONFIG.NUM_MI {7} [get_bd_cells axi_interconnect_0]
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M06_AXI] [get_bd_intf_pins axis_accel_mux_0/s_axi_lite]
connect_bd_net -net $clk_net [get_bd_pins axi_interconnect_0/M06_ACLK]
connect_bd_net -net $rst_net [get_bd_pins axi_interconnect_0/M06_ARESETN]

puts "--- 8. Connecting DMA Streams to Multiplexer ---"
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins axis_accel_mux_0/s_axis_dma]
connect_bd_intf_net [get_bd_intf_pins axis_accel_mux_0/m_axis_dma] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

puts "--- 9. Connecting Accelerator Streams ---"
# RLE
connect_bd_intf_net [get_bd_intf_pins axis_accel_mux_0/m_axis_rle] [get_bd_intf_pins rle_engine_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins rle_engine_0/m_axis] [get_bd_intf_pins axis_accel_mux_0/s_axis_rle]

# LZ4
connect_bd_intf_net [get_bd_intf_pins axis_accel_mux_0/m_axis_lz4] [get_bd_intf_pins lz4_engine_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins lz4_engine_0/m_axis] [get_bd_intf_pins axis_accel_mux_0/s_axis_lz4]

# AES-CTR (via axis_fifo_aes_in / axis_fifo_aes_out per ADR-012)
connect_bd_intf_net [get_bd_intf_pins axis_accel_mux_0/m_axis_aes] [get_bd_intf_pins axis_fifo_aes_in/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_fifo_aes_out/M_AXIS] [get_bd_intf_pins axis_accel_mux_0/s_axis_aes]

# ChaCha20 (via axis_fifo_chacha_in / axis_fifo_chacha_out per ADR-012)
connect_bd_intf_net [get_bd_intf_pins axis_accel_mux_0/m_axis_chacha] [get_bd_intf_pins axis_fifo_chacha_in/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_fifo_chacha_out/M_AXIS] [get_bd_intf_pins axis_accel_mux_0/s_axis_chacha]

puts "--- 10. Address Assignment ---"
assign_bd_address
set seg [get_bd_addr_segs processing_system7_0/Data/*mux*]
puts "Found MUX segment: $seg"
if {$seg ne ""} {
    set_property offset 0x43C40000 $seg
    set_property range 64K $seg
}

puts "--- 11. Validating and Saving Block Design ---"
regenerate_bd_layout
validate_bd_design
save_bd_design

puts "=== BLOCK DESIGN WITH ALL 4 ACCELERATORS AND STREAM MUX VALIDATED SUCCESSFULLY ==="
close_project
exit
