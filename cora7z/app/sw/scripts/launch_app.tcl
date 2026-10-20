connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*A9*#0"}
rst -system
after 1000
targets -set -nocase -filter {name =~ "*xc7z010*"}
fpga cora7z/app/sw/vitis/cora7z_firmware/_ide/bitstream/cora7z_top.bit
targets -set -nocase -filter {name =~ "*A9*#0"}
source cora7z/app/sw/vitis/cora7z_firmware/_ide/psinit/ps7_init.tcl
ps7_init
ps7_post_config
dow cora7z/app/sw/vitis/cora7z_firmware/build/cora7z_firmware.elf
con
exit
