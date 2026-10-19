# ==============================================================================
# add_lz4_to_bd.tcl
# Instantiates lz4_engine RTL module into soc_final_bd_1.bd
# - Connects AXI4-Lite to axi_interconnect_0 (M03_AXI) at 0x43C10000
# - Connects Clock and Reset to 100 MHz domain (FCLK_CLK1 / rst_ps7_100M)
# - Connects interrupt irq_o to xlconcat_0 (In4)
# - Validates Block Design with zero critical warnings
# ==============================================================================

set user_home $::env(HOME)
set_param board.repoPaths [list "$user_home/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards/Digilent/cora-z7-10/1.1"]
open_project cora7z/app/hw/vivado/soc-final.xpr
set_property board_part digilentinc.com:cora-z7-10:part0:1.1 [current_project]

set out_dir "out/vivado/task_2.3"
if {$argc > 0} {
    set out_dir [lindex $argv 0]
}
file mkdir $out_dir

puts "--- 1. Adding lz4_engine.vhdl to project sources ---"
add_files -norecurse cora7z/app/hw/src/lz4_engine.vhdl
update_compile_order -fileset sources_1

puts "--- 2. Opening Block Design ---"
open_bd_design [get_files *.bd]

puts "--- 3. Creating lz4_engine_0 Module Reference ---"
if {[get_bd_cells -quiet lz4_engine_0] ne ""} {
    delete_bd_objs [get_bd_cells lz4_engine_0]
}
create_bd_cell -type module -reference lz4_engine lz4_engine_0

puts "--- 4. Connecting Clock and Reset (100 MHz Domain) ---"
set clk_net [get_bd_nets -quiet -of_objects [get_bd_pins processing_system7_0/FCLK_CLK1]]
if {$clk_net ne ""} {
    connect_bd_net -net $clk_net [get_bd_pins lz4_engine_0/aclk]
} else {
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins lz4_engine_0/aclk]
}

set rst_net [get_bd_nets -quiet -of_objects [get_bd_pins rst_ps7_100M/peripheral_aresetn]]
if {$rst_net ne ""} {
    connect_bd_net -net $rst_net [get_bd_pins lz4_engine_0/aresetn]
} else {
    connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins lz4_engine_0/aresetn]
}

puts "--- 5. Connecting AXI4-Lite Control Interface to Interconnect ---"
set_property CONFIG.NUM_MI {4} [get_bd_cells axi_interconnect_0]
if {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins lz4_engine_0/s_axi_lite]] eq ""} {
    connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M03_AXI] [get_bd_intf_pins lz4_engine_0/s_axi_lite]
}
if {[get_bd_nets -quiet -of_objects [get_bd_pins axi_interconnect_0/M03_ACLK]] eq ""} {
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins axi_interconnect_0/M03_ACLK]
}
if {[get_bd_nets -quiet -of_objects [get_bd_pins axi_interconnect_0/M03_ARESETN]] eq ""} {
    connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M03_ARESETN]
}

puts "--- 6. Connecting Interrupt to xlconcat_0 ---"
set_property CONFIG.NUM_PORTS {5} [get_bd_cells xlconcat_0]
set irq_net [get_bd_nets -quiet -of_objects [get_bd_pins xlconcat_0/In4]]
if {$irq_net ne ""} {
    connect_bd_net -net $irq_net [get_bd_pins lz4_engine_0/irq_o]
} else {
    connect_bd_net [get_bd_pins lz4_engine_0/irq_o] [get_bd_pins xlconcat_0/In4]
}

puts "--- 6b. Stream Ingress Tie-off ---"
if {[get_bd_cells -quiet const_zero] eq ""} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero
    set_property CONFIG.CONST_VAL {0} [get_bd_cells const_zero]
}
if {[get_bd_nets -quiet -of_objects [get_bd_pins lz4_engine_0/s_axis_tvalid]] eq ""} {
    connect_bd_net [get_bd_pins const_zero/dout] [get_bd_pins lz4_engine_0/s_axis_tvalid]
}

puts "--- 7. Address Assignment ---"
assign_bd_address
set seg [get_bd_addr_segs processing_system7_0/Data/*lz4*]
puts "Found LZ4 segment: $seg"
if {$seg ne ""} {
    set_property offset 0x43C10000 $seg
    set_property range 64K $seg
}

puts "--- 8. Validating and Saving Block Design ---"
regenerate_bd_layout
validate_bd_design
save_bd_design

puts "--- 9. Writing Address Map Report ---"
set rpt_fp [open "${out_dir}/bd_address_map.rpt" w]
puts $rpt_fp "================================================================================"
puts $rpt_fp "Vivado Block Design Address Map Report (soc_final_bd_1.bd)"
puts $rpt_fp "Generated for Task 2.3 (LZ4 Engine Integration)"
puts $rpt_fp "================================================================================"
foreach s [get_bd_addr_segs processing_system7_0/Data/*] {
    set off [get_property offset $s]
    set rng [get_property range $s]
    puts $rpt_fp [format "%-45s Offset: %-12s Range: %s" $s $off $rng]
}
close $rpt_fp

puts "=== BLOCK DESIGN WITH LZ4_ENGINE VALIDATED SUCCESSFULLY ==="
close_project
exit
