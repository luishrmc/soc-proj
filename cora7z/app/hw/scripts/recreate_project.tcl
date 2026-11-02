# ==============================================================================
# recreate_project.tcl: Deterministic Vivado Project & Hardware Platform Builder
# Target: Digilent Cora Z7-10 (XC7Z010-1CLG400C)
# Authors: Antigravity AI / Luis H. R. M. C.
#
# Standard Architecture (ADR-011, ADR-012, ADR-017):
#   - Processing System 7 (ARM Cortex-A9 Core 0 @ 667 MHz, FCLK0=50M, FCLK1=100M)
#   - Dedicated Slave AXI Quad SPI Core (@ 0x41E00000) on Header J7
#   - EMIO GPIO 1-bit autonomous hardware burst trigger on PMOD JA1 (Y18)
#   - LZSS Dictionary Compression Accelerator (@ 0x43C00000) with True Dual-Port BRAM
#   - AES-128-CTR Cryptographic Accelerator (@ 0x43C10000) with True Dual-Port BRAM
#   - 4x True Dual-Port Block RAM buffers with AXI BRAM Controllers:
#       * LZSS In:   0x40000000 [8 KB]
#       * LZSS Out:  0x40002000 [8 KB]
#       * AES In:    0x40010000 [8 KB]
#       * AES Out:   0x40012000 [8 KB]
#   - Full automated implementation to bitstream and export to cora7z_top.xsa
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
puts "=== 2. Configuring Block Design via configure_block_design.tcl ==="
puts "================================================================================"
source "$script_dir/configure_block_design.tcl"

puts "================================================================================"
puts "=== 3. Adding Physical XDC Constraints ==="
puts "================================================================================"
if {[file exists $xdc_path]} {
    add_files -fileset constrs_1 -norecurse $xdc_path
    set_property target_constrs_file $xdc_path [get_filesets constrs_1]
    puts "Added XDC: $xdc_path"
}

puts "================================================================================"
puts "=== 4. Creating Top HDL Wrapper ==="
puts "================================================================================"
set bd_file [lindex [get_files *.bd] 0]
set wrapper_file [make_wrapper -files $bd_file -top -force]
add_files -norecurse $wrapper_file
set wrapper_top [file rootname [file tail $wrapper_file]]
set_property top $wrapper_top [current_fileset]
update_compile_order -fileset sources_1

puts "=== Top Wrapper Created: $wrapper_top ==="

puts "================================================================================"
puts "=== 5. Launching Implementation and Bitstream Generation ==="
puts "================================================================================"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "=== impl_1 Status: $impl_status ==="
if {![string match "*Complete*" $impl_status]} {
    puts "ERROR: Implementation failed: $impl_status"
    exit 1
}

puts "================================================================================"
puts "=== 6. Timing and Resource Utilization Audit ==="
puts "================================================================================"
open_run impl_1
report_timing_summary -file "$vivado_dir/timing_summary.rpt"
report_utilization -file "$vivado_dir/utilization.rpt"

set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "=== Timing Closure Results: WNS = $wns ns, WHS = $whs ns ==="

puts "================================================================================"
puts "=== 7. Exporting Authoritative Hardware Platform (XSA) with Bitstream ==="
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
puts "=== Vivado Heterogeneous Build Workflow Completed Successfully ==="
puts "================================================================================"
