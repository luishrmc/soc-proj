# configure_block_design.tcl
# Configures the hardware block design in cora7z/app/hw/vivado/soc-final.xpr:
# - Fixes Cora Z7-10 board repo path and unsets negative DDR DQS skew warnings
# - Configures processing_system7 (S_AXI_HP0, IRQ_F2P, FCLK_CLK1 @ 100 MHz)
# - Configures axi_quad_spi_0 in SLAVE mode (C_FIFO_DEPTH=256, ext_spi_clk=100MHz)
# - Connects SPI interrupt to PS7 IRQ_F2P
# - Adds AXI DMA (Simple DMA mode: MM2S + S2MM) connected to S_AXI_HP0 and M_AXI_GP0
# - Validates Block Design and saves it

set_param board.repoPaths [list "/home/luis/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards/Digilent/cora-z7-10/1.1"]
open_project cora7z/app/hw/vivado/soc-final.xpr
set_property board_part digilentinc.com:cora-z7-10:part0:1.1 [current_project]
open_bd_design [get_files *.bd]

set ps7 [get_bd_cells processing_system7_0]
set spi [get_bd_cells axi_quad_spi_0]
set ic_gp0 [get_bd_cells axi_interconnect_0]

puts "--- 1. Reconfiguring PS7 ---"
# Eliminate negative DQS delay warnings on unused byte lanes 2 and 3
# Enable S_AXI_HP0 (for DMA), Fabric Interrupts, and FCLK_CLK1 (100 MHz)
set_property -dict [list \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_EN_CLK1_PORT {1} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {100} \
] $ps7

puts "--- 2. Reconfiguring AXI Quad SPI as Slave ---"
set_property -dict [list \
    CONFIG.Master_mode {0} \
    CONFIG.C_FIFO_DEPTH {256} \
] $spi

# Connect ext_spi_clk to 100 MHz FCLK_CLK1 for fast SPI sampling (up to 25 MHz)
disconnect_bd_net /processing_system7_0_FCLK_CLK0 [get_bd_pins axi_quad_spi_0/ext_spi_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins axi_quad_spi_0/ext_spi_clk]

puts "--- 3. Adding AXI DMA Engine (Simple Mode) ---"
if {[get_bd_cells -quiet axi_dma_0] eq ""} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
}
set dma [get_bd_cells axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_include_s2mm {1} \
] $dma

# Connect DMA S_AXI_LITE to AXI Interconnect GP0
# We need 2 master ports on axi_interconnect_0: M00 -> SPI, M01 -> DMA
set_property CONFIG.NUM_MI {2} $ic_gp0
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M01_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_interconnect_0/M01_ACLK] [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M01_ARESETN] [get_bd_pins axi_dma_0/axi_resetn]

puts "--- 4. Connecting AXI DMA to S_AXI_HP0 via SmartConnect ---"
# Clocks and resets for DMA memory streaming
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]

if {[get_bd_cells -quiet smartconnect_hp0] eq ""} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_hp0
}
set smc_hp0 [get_bd_cells smartconnect_hp0]
set_property CONFIG.NUM_SI {2} $smc_hp0

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins smartconnect_hp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins smartconnect_hp0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_hp0/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# SmartConnect clocks and resets (100 MHz domain)
# Create a reset block for 100 MHz domain if not present
if {[get_bd_cells -quiet rst_ps7_100M] eq ""} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_100M
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins rst_ps7_100M/slowest_sync_clk]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_100M/ext_reset_in]
}
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins smartconnect_hp0/aclk]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins smartconnect_hp0/aresetn]

puts "--- 5. Connecting Interrupts via xlconcat ---"
if {[get_bd_cells -quiet xlconcat_0] eq ""} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
}
# In0: SPI interrupt, In1: DMA MM2S, In2: DMA S2MM
set_property CONFIG.NUM_PORTS {3} [get_bd_cells xlconcat_0]
connect_bd_net [get_bd_pins axi_quad_spi_0/ip2intc_irpt] [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins xlconcat_0/In2]
connect_bd_net [get_bd_pins xlconcat_0/dout] [get_bd_pins processing_system7_0/IRQ_F2P]

puts "--- 6. Address Map Assignment ---"
assign_bd_address
# Align base addresses with INTERFACES.md:
# DMA: 0x40400000 (range 64K)
# SPI: 0x41E00000 (standard Vivado default, range 64K)
set_property offset 0x40400000 [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_dma_0_Reg}]
set_property range 64K [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_dma_0_Reg}]

puts "--- 7. Validating and Saving Block Design ---"
regenerate_bd_layout
validate_bd_design
save_bd_design
puts "=== BLOCK DESIGN CONFIGURED AND VALIDATED SUCCESSFULLY ==="
close_project
exit
