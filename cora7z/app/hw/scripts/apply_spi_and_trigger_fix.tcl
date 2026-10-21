set user_home $::env(HOME)
set board_repo "$user_home/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards"
if {[file exists $board_repo]} {
    set_param board.repoPaths [list $board_repo]
}
open_project cora7z/app/hw/vivado/soc-final.xpr
open_bd_design [get_files *.bd]

puts "=== 1. Configure PS7 EMIO GPIO with xlslice for 1-bit ESP32 Trigger ==="
set ps7 [get_bd_cells processing_system7_0]
set_property -dict [list \
    CONFIG.PCW_EN_EMIO_GPIO {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_IO {1} \
] $ps7

if {[get_bd_cells -quiet trigger_slice] eq ""} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 trigger_slice
}
set_property -dict [list \
    CONFIG.DIN_WIDTH {64} \
    CONFIG.DIN_FROM {0} \
    CONFIG.DIN_TO {0} \
    CONFIG.DOUT_WIDTH {1} \
] [get_bd_cells trigger_slice]

if {[get_bd_ports -quiet esp32_trigger_o] ne ""} {
    delete_bd_objs [get_bd_ports esp32_trigger_o]
}
create_bd_port -dir O esp32_trigger_o

connect_bd_net [get_bd_pins processing_system7_0/GPIO_O] [get_bd_pins trigger_slice/Din]
connect_bd_net [get_bd_pins trigger_slice/Dout] [get_bd_ports esp32_trigger_o]

puts "=== 2. Reconfigure AXI Quad SPI with discrete ports and SPISEL connection ==="
set spi [get_bd_cells axi_quad_spi_0]

# Remove interface net and port if present
catch { delete_bd_objs [get_bd_intf_nets axi_quad_spi_0_SPI_0] }
catch { delete_bd_objs [get_bd_intf_ports shield_spi] }

set_property -dict [list \
    CONFIG.USE_BOARD_FLOW {false} \
    CONFIG.QSPI_BOARD_INTERFACE {Custom} \
    CONFIG.Master_mode {0} \
    CONFIG.C_FIFO_DEPTH {256} \
] $spi

# Clean up any existing discrete ports
foreach p {spi_sck_i spi_mosi_i spi_miso_o spi_ss_i} {
    if {[get_bd_ports -quiet $p] ne ""} {
        delete_bd_objs [get_bd_ports $p]
    }
}

# Create discrete external ports
create_bd_port -dir I spi_sck_i
create_bd_port -dir I spi_mosi_i
create_bd_port -dir O spi_miso_o
create_bd_port -dir I spi_ss_i

# Connect SPI signals
connect_bd_net [get_bd_ports spi_sck_i] [get_bd_pins axi_quad_spi_0/sck_i]
connect_bd_net [get_bd_ports spi_mosi_i] [get_bd_pins axi_quad_spi_0/io0_i]
connect_bd_net [get_bd_pins axi_quad_spi_0/io1_o] [get_bd_ports spi_miso_o]

# Crucial fix: Connect BOTH ss_i and spisel to the active-low external Chip Select
connect_bd_net [get_bd_ports spi_ss_i] [get_bd_pins axi_quad_spi_0/ss_i] [get_bd_pins axi_quad_spi_0/spisel]

puts "=== 3. Validating Block Design ==="
validate_bd_design
save_bd_design

set bd_file [lindex [get_files *.bd] 0]
set wrapper_file [make_wrapper -files $bd_file -top -force]
puts "Generated wrapper: $wrapper_file"
puts "=== BLOCK DESIGN VALIDATED AND SAVED SUCCESSFULLY ==="
exit
