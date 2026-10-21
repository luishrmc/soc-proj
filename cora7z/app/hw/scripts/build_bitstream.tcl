# ==============================================================================
# build_bitstream.tcl: Non-interactive Vivado Synthesis, Implementation,
# Bitstream Generation and XSA Export with Bitstream for Cora Z7-10
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize "$script_dir/../../../.."]
set xpr_path "$repo_root/cora7z/app/hw/vivado/soc-final.xpr"
set xdc_path "$repo_root/cora7z/app/hw/utils/cora_z7_io.xdc"
set xsa_out "$repo_root/cora7z/app/hw/vivado/cora7z_top.xsa"
set out_dir [lindex $argv 0]
if {$out_dir eq ""} {
    set out_dir "$repo_root/out/vivado/bitstream"
}
file mkdir $out_dir

set user_home $::env(HOME)
set board_repo "$user_home/.Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards"
if {[file exists $board_repo]} {
    set_param board.repoPaths [list $board_repo]
}

puts "================================================================================"
puts "=== BITSTREAM BUILD === Opening Vivado project: $xpr_path"
puts "================================================================================"
open_project $xpr_path

# Add XDC constraints to constrs_1 if not already added
set existing_xdc [get_files -of_objects [get_filesets constrs_1] [file tail $xdc_path]]
if {[llength $existing_xdc] == 0} {
    puts "=== BITSTREAM BUILD === Adding XDC constraints: $xdc_path"
    add_files -fileset constrs_1 -norecurse $xdc_path
    set_property target_constrs_file $xdc_path [get_filesets constrs_1]
} else {
    puts "=== BITSTREAM BUILD === XDC constraints already present in constrs_1."
}

# Open and validate Block Design
set bd_file [lindex [get_files *.bd] 0]
puts "=== BITSTREAM BUILD === Opening Block Design: $bd_file"
open_bd_design $bd_file

# Refresh module references if out of date
puts "=== BITSTREAM BUILD === Updating module references..."
catch { update_module_reference [get_ips *engine*] }
catch { update_module_reference [get_ips *mux*] }

puts "=== BITSTREAM BUILD === Validating Block Design..."
validate_bd_design
save_bd_design

puts "=== BITSTREAM BUILD === Generating Block Design Targets (forced)..."
generate_target -force all $bd_file

# Ensure top wrapper is present and set as top
set wrapper_file [make_wrapper -files $bd_file -top -force]
if {[file exists $wrapper_file]} {
    add_files -norecurse $wrapper_file
    set wrapper_top [file rootname [file tail $wrapper_file]]
    set_property top $wrapper_top [current_fileset]
    update_compile_order -fileset sources_1
    puts "=== BITSTREAM BUILD === Top module set to: $wrapper_top"
}

# ------------------------------------------------------------------------------
# 1. Synthesis
# ------------------------------------------------------------------------------
puts "================================================================================"
puts "=== BITSTREAM BUILD === Resetting and Starting Synthesis Run: synth_1"
puts "================================================================================"
catch { reset_run synth_1 }
catch { reset_run impl_1 }
launch_runs synth_1 -jobs 3
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "=== BITSTREAM BUILD === synth_1 Status: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    puts "ERROR: Synthesis (synth_1) failed to complete: $synth_status"
    close_project
    exit 1
}

# ------------------------------------------------------------------------------
# 2. Implementation and Bitstream Generation
# ------------------------------------------------------------------------------
puts "================================================================================"
puts "=== BITSTREAM BUILD === Starting Implementation Run: impl_1 (to write_bitstream)"
puts "================================================================================"
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 3
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "=== BITSTREAM BUILD === impl_1 Status: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    puts "ERROR: Implementation / write_bitstream (impl_1) failed: $impl_status"
    close_project
    exit 1
}

# ------------------------------------------------------------------------------
# 3. Timing and Resource Reports
# ------------------------------------------------------------------------------
puts "================================================================================"
puts "=== BITSTREAM BUILD === Generating Implementation Reports in $out_dir"
puts "================================================================================"
open_run impl_1

report_utilization -file "$out_dir/utilization.rpt"
report_timing_summary -file "$out_dir/timing_summary.rpt"
report_drc -file "$out_dir/drc.rpt"

# Check timing slack
set wns [get_property STATS.WNS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "=== BITSTREAM BUILD === Timing Summary:"
puts "    WNS (Worst Negative Slack): $wns ns"
puts "    TNS (Total Negative Slack): $tns ns"
puts "    WHS (Worst Hold Slack):     $whs ns"

if {$wns ne "" && $wns < 0.0} {
    puts "WARNING: Timing violations detected! WNS = $wns ns"
} else {
    puts "=== BITSTREAM BUILD === Timing closed cleanly (WNS >= 0)."
}

# ------------------------------------------------------------------------------
# 4. Hardware Platform Export with Bitstream
# ------------------------------------------------------------------------------
puts "================================================================================"
puts "=== BITSTREAM BUILD === Exporting Fixed Hardware Platform with Bitstream: $xsa_out"
puts "================================================================================"
write_hw_platform -fixed -include_bit -force -file $xsa_out

puts "=== BITSTREAM BUILD === Completed successfully!"
close_project
exit 0
