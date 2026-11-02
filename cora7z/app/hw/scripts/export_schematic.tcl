open_project cora7z/app/hw/vivado/soc-final.xpr
open_run impl_1
file mkdir docs/diagrams
write_schematic -format pdf -force docs/diagrams/cora7z_top_schematic.pdf
write_schematic -format svg -force docs/diagrams/cora7z_top_schematic.svg
puts "[OK] Exported Vivado schematics to docs/diagrams/"
exit
