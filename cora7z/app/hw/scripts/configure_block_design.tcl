################################################################################
# Project: High-Performance PS/PL Acceleration on Zynq-7010 (Digilent Cora Z7)
# File:    configure_block_design.tcl
# Author:  Antigravity AI / Luis H. R. M. C.
#
# Description:
#   Modular Vivado Tcl script automating the instantiation, wiring, and address
#   mapping of the Heterogeneous Dual-Port BRAM Acceleration System:
#     - Processing System 7 (ARM Cortex-A9 Core 0 @ 667 MHz, FCLK0=50M, FCLK1=100M)
#     - AXI Quad SPI 0 (Slave Mode 0, 256-word FIFO @ 0x41E00000, Header J7)
#     - EMIO GPIO 1-bit trigger slice to PMOD JA1 (Y18)
#     - lzss_accel (Sliding-window dictionary compressor @ 0x43C00000)
#     - aes_accel (NIST SP 800-38A AES-128-CTR cryptographic engine @ 0x43C10000)
#     - 4x True Dual-Port Block RAMs (blk_mem_gen) + AXI BRAM Controllers:
#         * LZSS Input BRAM:   0x40000000 [8 KB]
#         * LZSS Output BRAM:  0x40002000 [8 KB]
#         * AES Input BRAM:    0x40010000 [8 KB]
#         * AES Output BRAM:   0x40012000 [8 KB]
################################################################################

puts "================================================================================"
puts "=== (configure_block_design.tcl) Starting Block Design Configuration ==="
puts "================================================================================"

set cur_design [current_bd_design -quiet]
if {$cur_design eq ""} {
    create_bd_design "soc_final_bd_1"
}

set repo_root [file normalize "[file dirname [info script]]/../../../.."]

# ------------------------------------------------------------------------------
# 1. Add Accelerator RTL Sources to Project and Update Compile Order
# ------------------------------------------------------------------------------
puts "--- Adding Accelerator RTL Sources (lzss_accel.vhdl, aes_accel.vhdl) ---"
set rtl_files [list \
    "$repo_root/cora7z/app/hw/src/lzss_accel.vhdl" \
    "$repo_root/cora7z/app/hw/src/aes_accel.vhdl" \
]
add_files -norecurse $rtl_files
set_property file_type {VHDL 2008} [get_files [list lzss_accel.vhdl aes_accel.vhdl]]
update_compile_order -fileset sources_1

# ------------------------------------------------------------------------------
# 2. Instantiate and Configure Processing System 7
# ------------------------------------------------------------------------------
puts "--- Instantiating and Configuring Processing System 7 ---"
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps7

set_property -dict [list \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} \
    CONFIG.PCW_EN_CLK1_PORT {1} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_EMIO_GPIO {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_IO {1} \
] $ps7

# ------------------------------------------------------------------------------
# 3. Instantiate AXI Quad SPI Core (Slave Mode 0, 256-word FIFO @ 0x41E00000)
# ------------------------------------------------------------------------------
puts "--- Instantiating AXI Quad SPI Core in Slave Mode 0 ---"
set spi [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_quad_spi:3.2 axi_quad_spi_0]
set_property -dict [list \
    CONFIG.USE_BOARD_FLOW {false} \
    CONFIG.QSPI_BOARD_INTERFACE {Custom} \
    CONFIG.Master_mode {0} \
    CONFIG.C_FIFO_DEPTH {256} \
] $spi

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins axi_quad_spi_0/AXI_LITE]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins axi_quad_spi_0/ext_spi_clk]

# Route Discrete SPI Header J7 External Ports
create_bd_port -dir I spi_sck_i
create_bd_port -dir I spi_mosi_i
create_bd_port -dir O spi_miso_o
create_bd_port -dir I spi_ss_i

connect_bd_net [get_bd_ports spi_sck_i]  [get_bd_pins axi_quad_spi_0/sck_i]
connect_bd_net [get_bd_ports spi_mosi_i] [get_bd_pins axi_quad_spi_0/io0_i]
connect_bd_net [get_bd_pins axi_quad_spi_0/io1_o] [get_bd_ports spi_miso_o]
connect_bd_net [get_bd_ports spi_ss_i]   [get_bd_pins axi_quad_spi_0/ss_i] [get_bd_pins axi_quad_spi_0/spisel]

# EMIO GPIO Trigger Slice for PMOD JA1
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

# ------------------------------------------------------------------------------
# 4. Instantiate Accelerator RTL Module References
# ------------------------------------------------------------------------------
puts "--- Instantiating Accelerator RTL Cores (lzss_accel_0, aes_accel_0) ---"
set lzss_cell [create_bd_cell -type module -reference lzss_accel lzss_accel_0]
set aes_cell  [create_bd_cell -type module -reference aes_accel aes_accel_0]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/processing_system7_0/M_AXI_GP0" Clk "/processing_system7_0/FCLK_CLK1 (100 MHz)"} [get_bd_intf_pins lzss_accel_0/s_axi]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/processing_system7_0/M_AXI_GP0" Clk "/processing_system7_0/FCLK_CLK1 (100 MHz)"} [get_bd_intf_pins aes_accel_0/s_axi]

# Relocate Accelerator CSRs out of 0x40000000 range immediately
set_property offset 0x43C00000 [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *lzss_accel_0*}]
set_property range  64K        [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *lzss_accel_0*}]

set_property offset 0x43C10000 [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *aes_accel_0*}]
set_property range  64K        [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *aes_accel_0*}]

# ------------------------------------------------------------------------------
# 5. Instantiate 4x True Dual-Port Block RAM Subsystems (ADR-012, ADR-017)
# ------------------------------------------------------------------------------
puts "--- Creating 4x True Dual-Port Block RAM Subsystems ---"

proc create_bram_subsystem {name accel_cell port_prefix} {
    # 1. AXI BRAM Controller (32-bit single port to BRAM Port A)
    set ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 "axi_bram_ctrl_${name}"]
    set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1} CONFIG.DATA_WIDTH {32}] $ctrl
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
        -config {Master "/processing_system7_0/M_AXI_GP0" Clk "/processing_system7_0/FCLK_CLK1 (100 MHz)"} [get_bd_intf_pins $ctrl/S_AXI]

    # 2. Block Memory Generator (True Dual Port RAM)
    set bmg [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 "bmg_${name}"]
    set_property -dict [list \
        CONFIG.Memory_Type {True_Dual_Port_RAM} \
        CONFIG.Enable_B {Use_ENB_Pin} \
        CONFIG.use_bram_block {BRAM_Controller} \
    ] $bmg

    # Connect Port A bus interface between Controller and BMG
    connect_bd_intf_net [get_bd_intf_pins $ctrl/BRAM_PORTA] [get_bd_intf_pins $bmg/BRAM_PORTA]

    # Connect Port B discrete memory bus to Accelerator RTL Core
    connect_bd_net [get_bd_pins ${accel_cell}/${port_prefix}_addr] [get_bd_pins $bmg/addrb]
    connect_bd_net [get_bd_pins ${accel_cell}/${port_prefix}_en]   [get_bd_pins $bmg/enb]
    connect_bd_net [get_bd_pins ${accel_cell}/${port_prefix}_we]   [get_bd_pins $bmg/web]
    connect_bd_net [get_bd_pins ${accel_cell}/${port_prefix}_din]  [get_bd_pins $bmg/dinb]
    connect_bd_net [get_bd_pins $bmg/doutb] [get_bd_pins ${accel_cell}/${port_prefix}_dout]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1]    [get_bd_pins $bmg/clkb]
    connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_reset]  [get_bd_pins $bmg/rstb]
}

create_bram_subsystem "lzss_in"  "lzss_accel_0" "bram_in"
create_bram_subsystem "lzss_out" "lzss_accel_0" "bram_out"
create_bram_subsystem "aes_in"   "aes_accel_0"  "bram_in"
create_bram_subsystem "aes_out"  "aes_accel_0"  "bram_out"

# ------------------------------------------------------------------------------
# 6. Apply Standard AXI Address Offsets and Range Boundaries
# ------------------------------------------------------------------------------
puts "--- Assigning Standard AXI Memory Address Map ---"

set_property offset 0x40000000 [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *axi_bram_ctrl_lzss_in*}]
set_property range  8K         [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *axi_bram_ctrl_lzss_in*}]

set_property offset 0x40002000 [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *axi_bram_ctrl_lzss_out*}]
set_property range  8K         [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *axi_bram_ctrl_lzss_out*}]

set_property offset 0x40010000 [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *axi_bram_ctrl_aes_in*}]
set_property range  8K         [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *axi_bram_ctrl_aes_in*}]

set_property offset 0x40012000 [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *axi_bram_ctrl_aes_out*}]
set_property range  8K         [get_bd_addr_segs -of_objects [get_bd_addr_spaces /processing_system7_0/Data] -filter {NAME =~ *axi_bram_ctrl_aes_out*}]

# ------------------------------------------------------------------------------
# 7. Validate and Save Block Design
# ------------------------------------------------------------------------------
puts "--- Validating Block Design ---"
validate_bd_design
save_bd_design
puts "=== (configure_block_design.tcl) Completed Successfully ==="
