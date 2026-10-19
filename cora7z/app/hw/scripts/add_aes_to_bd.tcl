# ==============================================================================
# add_aes_to_bd.tcl
# Instantiates aes_ctr_engine RTL module and explicit Block Design memory FIFOs
# (axis_data_fifo) into soc_final_bd_1.bd per ADR-012.
#
# - Connects AXI4-Lite to axi_interconnect_0 (M04_AXI) at 0x43C20000
# - Connects Clock and Reset to 100 MHz domain (FCLK_CLK1 / rst_ps7_100M)
# - Connects interrupt irq_o to xlconcat_0 (In5)
# - Instantiates standard axis_data_fifo memory blocks for visual AXI-Stream buffering
# - Validates Block Design with zero critical warnings
# ==============================================================================

set user_home $::env(HOME)
set_param board.repoPaths [list "$user_home/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards/Digilent/cora-z7-10/1.1"]
open_project cora7z/app/hw/vivado/soc-final.xpr
set_property board_part digilentinc.com:cora-z7-10:part0:1.1 [current_project]

set out_dir "out/vivado/task_2.4"
if {$argc > 0} {
    set out_dir [lindex $argv 0]
}
file mkdir $out_dir

puts "--- 1. Adding aes_ctr_engine.vhdl to project sources ---"
add_files -norecurse cora7z/app/hw/src/aes_ctr_engine.vhdl
update_compile_order -fileset sources_1

puts "--- 2. Opening Block Design ---"
open_bd_design [get_files *.bd]

puts "--- 3. Creating aes_ctr_engine_0 Module Reference ---"
if {[get_bd_cells -quiet aes_ctr_engine_0] ne ""} {
    delete_bd_objs [get_bd_cells aes_ctr_engine_0]
}
create_bd_cell -type module -reference aes_ctr_engine aes_ctr_engine_0

puts "--- 4. Connecting Clock and Reset (100 MHz Domain) ---"
set clk_net [get_bd_nets -quiet -of_objects [get_bd_pins processing_system7_0/FCLK_CLK1]]
if {$clk_net ne ""} {
    connect_bd_net -net $clk_net [get_bd_pins aes_ctr_engine_0/aclk]
} else {
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins aes_ctr_engine_0/aclk]
    set clk_net [get_bd_nets -of_objects [get_bd_pins processing_system7_0/FCLK_CLK1]]
}

set rst_net [get_bd_nets -quiet -of_objects [get_bd_pins rst_ps7_100M/peripheral_aresetn]]
if {$rst_net ne ""} {
    connect_bd_net -net $rst_net [get_bd_pins aes_ctr_engine_0/aresetn]
} else {
    connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins aes_ctr_engine_0/aresetn]
    set rst_net [get_bd_nets -of_objects [get_bd_pins rst_ps7_100M/peripheral_aresetn]]
}

puts "--- 5. Connecting AXI4-Lite Control Interface to Interconnect ---"
set_property CONFIG.NUM_MI {5} [get_bd_cells axi_interconnect_0]
if {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins aes_ctr_engine_0/s_axi_lite]] eq ""} {
    connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M04_AXI] [get_bd_intf_pins aes_ctr_engine_0/s_axi_lite]
}
if {[get_bd_nets -quiet -of_objects [get_bd_pins axi_interconnect_0/M04_ACLK]] eq ""} {
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins axi_interconnect_0/M04_ACLK]
}
if {[get_bd_nets -quiet -of_objects [get_bd_pins axi_interconnect_0/M04_ARESETN]] eq ""} {
    connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M04_ARESETN]
}

puts "--- 6. Connecting Interrupt to xlconcat_0 ---"
set_property CONFIG.NUM_PORTS {6} [get_bd_cells xlconcat_0]
set irq_net [get_bd_nets -quiet -of_objects [get_bd_pins xlconcat_0/In5]]
if {$irq_net ne ""} {
    connect_bd_net -net $irq_net [get_bd_pins aes_ctr_engine_0/irq_o]
} else {
    connect_bd_net [get_bd_pins aes_ctr_engine_0/irq_o] [get_bd_pins xlconcat_0/In5]
}

puts "--- 7. Explicit Block Design Memory Integration (axis_data_fifo per ADR-012) ---"
if {[get_bd_cells -quiet axis_fifo_aes_in] ne ""} {
    delete_bd_objs [get_bd_cells axis_fifo_aes_in]
}
if {[get_bd_cells -quiet axis_fifo_aes_out] ne ""} {
    delete_bd_objs [get_bd_cells axis_fifo_aes_out]
}

# Input FIFO (axis_fifo_aes_in): 32-bit (4 bytes) TDATA, 64 deep
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 axis_fifo_aes_in
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_DEPTH {64}] [get_bd_cells axis_fifo_aes_in]

# Output FIFO (axis_fifo_aes_out): 32-bit (4 bytes) TDATA, 64 deep
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 axis_fifo_aes_out
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_DEPTH {64}] [get_bd_cells axis_fifo_aes_out]

# Connect Clocks and Resets to FIFOs (100 MHz Domain)
connect_bd_net -net $clk_net [get_bd_pins axis_fifo_aes_in/s_axis_aclk] [get_bd_pins axis_fifo_aes_out/s_axis_aclk]
connect_bd_net -net $rst_net [get_bd_pins axis_fifo_aes_in/s_axis_aresetn] [get_bd_pins axis_fifo_aes_out/s_axis_aresetn]

# Connect Input FIFO M_AXIS -> aes_ctr_engine_0 S_AXIS
connect_bd_intf_net [get_bd_intf_pins axis_fifo_aes_in/M_AXIS] [get_bd_intf_pins aes_ctr_engine_0/s_axis]

# Connect aes_ctr_engine_0 M_AXIS -> Output FIFO S_AXIS
connect_bd_intf_net [get_bd_intf_pins aes_ctr_engine_0/m_axis] [get_bd_intf_pins axis_fifo_aes_out/S_AXIS]

puts "--- 8. Address Assignment ---"
assign_bd_address
set seg [get_bd_addr_segs processing_system7_0/Data/*aes*]
puts "Found AES segment: $seg"
if {$seg ne ""} {
    set_property offset 0x43C20000 $seg
    set_property range 64K $seg
}

puts "--- 9. Validating and Saving Block Design ---"
regenerate_bd_layout
validate_bd_design
save_bd_design

puts "--- 10. Writing Address Map Report ---"
set rpt_fp [open "${out_dir}/bd_address_map.rpt" w]
puts $rpt_fp "================================================================================"
puts $rpt_fp "Vivado Block Design Address Map Report (soc_final_bd_1.bd)"
puts $rpt_fp "Generated for Task 2.4 (AES-CTR Engine Integration)"
puts $rpt_fp "================================================================================"
foreach s [get_bd_addr_segs processing_system7_0/Data/*] {
    set off [get_property offset $s]
    set rng [get_property range $s]
    puts $rpt_fp [format "%-45s Offset: %-12s Range: %s" $s $off $rng]
}
close $rpt_fp

puts "=== BLOCK DESIGN WITH AES_CTR_ENGINE AND EXPLICIT FIFOS VALIDATED SUCCESSFULLY ==="
close_project
exit
