# ==============================================================================
# recreate_project.tcl: Deterministic Vivado Project & Block Design Builder
# Target: Digilent Cora Z7-10 (XC7Z010-1CLG400C)
# Creates soc-final.xpr, configures PS7, AXI Quad SPI Slave, PMOD trigger,
# adds XDC constraints, validates BD, builds bitstream, and exports fixed XSA.
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize "$script_dir/../../../.."]
set vivado_dir "$repo_root/cora7z/app/hw/vivado"
set xdc_path "$repo_root/cora7z/app/hw/utils/cora_z7_io.xdc"
set user_home $::env(HOME)
set board_repo "$user_home/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards/Digilent/cora-z7-10/1.1"

file mkdir $vivado_dir

if {[file exists $board_repo]} {
    set_param board.repoPaths [list $board_repo]
}

puts "================================================================================"
puts "=== 1. Creating Vivado Project: soc-final ==="
puts "================================================================================"
create_project -force soc-final "$vivado_dir" -part xc7z010clg400-1
set_property board_part digilentinc.com:cora-z7-10:part0:1.1 [current_project]

puts "================================================================================"
puts "=== 2. Creating Block Design: soc_final_bd_1 ==="
puts "================================================================================"
create_bd_design "soc_final_bd_1"

# Instantiate Processing System 7
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable" } $ps7

# Configure PS7: Clocks, EMIO GPIO, and eliminate DQS skew warnings
set_property -dict [list \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} \
    CONFIG.PCW_EN_CLK1_PORT {1} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_EMIO_GPIO {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_IO {1} \
] $ps7

# Instantiate AXI Quad SPI Core in Slave Mode with 256-word FIFO
set spi [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_quad_spi:3.2 axi_quad_spi_0]
set_property -dict [list \
    CONFIG.USE_BOARD_FLOW {false} \
    CONFIG.QSPI_BOARD_INTERFACE {Custom} \
    CONFIG.Master_mode {0} \
    CONFIG.C_FIFO_DEPTH {256} \
] $spi

# Apply AXI Interconnect Automation for AXI_LITE -> M_AXI_GP0
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" } [get_bd_intf_pins axi_quad_spi_0/AXI_LITE]

# Connect fast 100 MHz sampling clock (ext_spi_clk) from PS7 FCLK_CLK1
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins axi_quad_spi_0/ext_spi_clk]

puts "================================================================================"
puts "=== 3. Routing Discrete SPI Header J7 Ports and SPISEL Connection ==="
puts "================================================================================"
create_bd_port -dir I spi_sck_i
create_bd_port -dir I spi_mosi_i
create_bd_port -dir O spi_miso_o
create_bd_port -dir I spi_ss_i

connect_bd_net [get_bd_ports spi_sck_i] [get_bd_pins axi_quad_spi_0/sck_i]
connect_bd_net [get_bd_ports spi_mosi_i] [get_bd_pins axi_quad_spi_0/io0_i]
connect_bd_net [get_bd_pins axi_quad_spi_0/io1_o] [get_bd_ports spi_miso_o]

# Connect both ss_i and spisel to spi_ss_i for active-low framing
connect_bd_net [get_bd_ports spi_ss_i] [get_bd_pins axi_quad_spi_0/ss_i] [get_bd_pins axi_quad_spi_0/spisel]

puts "================================================================================"
puts "=== 4. Adding 1-bit PS EMIO GPIO Trigger Slice for PMOD JA1 ==="
puts "================================================================================"
set trigger_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 trigger_slice]
set_property -dict [list \
    CONFIG.DIN_WIDTH {64} \
    CONFIG.DIN_FROM {0} \
    CONFIG.DIN_TO {0} \
    CONFIG.DOUT_WIDTH {1} \
] $trigger_slice

create_bd_port -dir O esp32_trigger_o
connect_bd_net [get_bd_pins processing_system7_0/GPIO_O] [get_bd_pins trigger_slice/Din]
connect_bd_net [get_bd_pins trigger_slice/Dout] [get_bd_ports esp32_trigger_o]

puts "================================================================================"
puts "=== 5. Adding Physical XDC Constraints ==="
puts "================================================================================"
if {[file exists $xdc_path]} {
    add_files -fileset constrs_1 -norecurse $xdc_path
    set_property target_constrs_file $xdc_path [get_filesets constrs_1]
    puts "Added XDC: $xdc_path"
}

puts "================================================================================"
puts "=== 6. Validating Block Design & Creating HDL Wrapper ==="
puts "================================================================================"
validate_bd_design
save_bd_design

set bd_file [lindex [get_files *.bd] 0]
set wrapper_file [make_wrapper -files $bd_file -top -force]
add_files -norecurse $wrapper_file
set wrapper_top [file rootname [file tail $wrapper_file]]
set_property top $wrapper_top [current_fileset]
update_compile_order -fileset sources_1

puts "=== Block Design created and validated: $wrapper_top ==="

puts "================================================================================"
puts "=== 7. Starting Synthesis and Implementation Run to Bitstream ==="
puts "================================================================================"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "=== impl_1 Status: $impl_status ==="
if {![string match "*Complete*" $impl_status]} {
    puts "ERROR: Implementation failed: $impl_status"
    exit 1
}

puts "================================================================================"
puts "=== 8. Exporting Fixed Hardware Platform (XSA) with Bitstream ==="
puts "================================================================================"
set xsa_out "$vivado_dir/cora7z_top.xsa"
write_hw_platform -fixed -include_bit -force -file $xsa_out
puts "=== Exported Hardware Platform: $xsa_out ==="

set vitis_bit_dir "$repo_root/cora7z/app/sw/vitis/cora7z_firmware/_ide/bitstream"
file mkdir $vitis_bit_dir
set bit_file [lindex [glob -nocomplain "$vivado_dir/soc-final.runs/impl_1/*.bit"] 0]
if {[file exists $bit_file]} {
    file copy -force $bit_file "$vitis_bit_dir/cora7z_top.bit"
    puts "=== Copied bitstream to Vitis workspace: $vitis_bit_dir/cora7z_top.bit ==="
}

puts "================================================================================"
puts "=== Vivado Rebuild Workflow Completed Successfully ==="
puts "================================================================================"
