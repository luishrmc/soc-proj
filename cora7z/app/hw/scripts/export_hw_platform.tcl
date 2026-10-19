# ==============================================================================
# export_hw_platform.tcl: Generate BD targets, create wrapper, and export fixed XSA
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize "$script_dir/../../../.."]
set xpr_path "$repo_root/cora7z/app/hw/vivado/soc-final.xpr"
set xsa_out "$repo_root/cora7z/app/hw/vivado/cora7z_top.xsa"
set user_home $::env(HOME)
set board_repo "$user_home/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards"

puts "================================================================================"
puts "=== EXPORT XSA === Opening Vivado project: $xpr_path"
puts "================================================================================"

if {[file exists $board_repo]} {
    set_param board.repoPaths [list $board_repo]
}

open_project $xpr_path

set bd_files [get_files *.bd]
if {[llength $bd_files] == 0} {
    puts "ERROR: No block design found in project."
    exit 1
}

set bd_file [lindex $bd_files 0]
puts "=== EXPORT XSA === Opening Block Design: $bd_file"
open_bd_design $bd_file

puts "=== EXPORT XSA === Validating Block Design..."
validate_bd_design
save_bd_design

puts "=== EXPORT XSA === Generating BD Output Products (generate_target all)..."
generate_target all $bd_file

puts "=== EXPORT XSA === Creating Top HDL Wrapper..."
set wrapper_file [make_wrapper -files $bd_file -top]
if {[file exists $wrapper_file]} {
    add_files -norecurse $wrapper_file
    set wrapper_top [file rootname [file tail $wrapper_file]]
    set_property top $wrapper_top [current_fileset]
    update_compile_order -fileset sources_1
    puts "=== EXPORT XSA === Set top wrapper to: $wrapper_top"
}

puts "=== EXPORT XSA === Writing Hardware Platform (XSA): $xsa_out"
write_hw_platform -fixed -force -file $xsa_out

puts "=== EXPORT XSA === Completed successfully."
close_project
exit 0
