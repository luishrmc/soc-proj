# add_rle_to_bd.tcl
# Instantiates rle_engine RTL module into soc_final_bd_1.bd
# - Connects AXI4-Stream MM2S (DMA -> RLE) and S2MM (RLE -> DMA)
# - Connects AXI4-Lite to axi_interconnect_0 (M02_AXI) at 0x43C00000
# - Connects interrupt irq_o to xlconcat_0 (In3)
# - Validates Block Design with zero critical warnings

set_param board.repoPaths [list "/home/luis/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards/Digilent/cora-z7-10/1.1"]
open_project cora7z/app/hw/vivado/soc-final.xpr
set_property board_part digilentinc.com:cora-z7-10:part0:1.1 [current_project]

puts "--- 1. Adding rle_engine.vhdl to project sources ---"
add_files -norecurse cora7z/app/hw/src/rle_engine.vhdl
update_compile_order -fileset sources_1

puts "--- 2. Opening Block Design ---"
open_bd_design [get_files *.bd]

puts "--- 3. Creating rle_engine_0 Module Reference ---"
if {[get_bd_cells -quiet rle_engine_0] ne ""} {
    delete_bd_objs [get_bd_cells rle_engine_0]
}
create_bd_cell -type module -reference rle_engine rle_engine_0

puts "--- 4. Connecting Clock and Reset (100 MHz Domain) ---"
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins rle_engine_0/aclk]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins rle_engine_0/aresetn]

puts "--- 5. Connecting AXI4-Stream Data Interfaces to AXI DMA ---"
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins rle_engine_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins rle_engine_0/m_axis] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

puts "--- 6. Connecting AXI4-Lite Control Interface to Interconnect ---"
set_property CONFIG.NUM_MI {3} [get_bd_cells axi_interconnect_0]
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M02_AXI] [get_bd_intf_pins rle_engine_0/s_axi_lite]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins axi_interconnect_0/M02_ACLK]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M02_ARESETN]

puts "--- 7. Connecting Interrupt to xlconcat_0 ---"
set_property CONFIG.NUM_PORTS {4} [get_bd_cells xlconcat_0]
connect_bd_net [get_bd_pins rle_engine_0/irq_o] [get_bd_pins xlconcat_0/In3]

puts "--- 8. Address Assignment ---"
assign_bd_address
set seg [get_bd_addr_segs processing_system7_0/Data/*rle*]
puts "Found RLE segment: $seg"
if {$seg ne ""} {
    set_property offset 0x43C00000 $seg
    set_property range 64K $seg
}

puts "--- 9. Validating and Saving Block Design ---"
regenerate_bd_layout
validate_bd_design
save_bd_design
puts "=== BLOCK DESIGN WITH RLE_ENGINE VALIDATED SUCCESSFULLY ==="
close_project
exit
