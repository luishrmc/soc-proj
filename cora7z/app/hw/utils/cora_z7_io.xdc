# ==============================================================================
# cora_z7_io.xdc: Physical and IO constraints for Digilent Cora Z7-10
# Target: XC7Z010-1CLG400C
# ==============================================================================

# ------------------------------------------------------------------------------
# Dedicated SPI Slave Interface from ESP32 (Dedicated SPI Header J7)
# Referenced against docs/cora7z/Cora+Z7_sch-public.pdf and INTERFACES.md
# ------------------------------------------------------------------------------

# SCK (Pin H15, Bank 35, 3.3V LVCMOS) - Dedicated SPI Header J7 Pin 3 (CK_SCK)
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { shield_spi_sck_io }];

# MOSI / IO0 (Pin T12, Bank 34, 3.3V LVCMOS) - Dedicated SPI Header J7 Pin 4 (CK_MOSI)
set_property -dict { PACKAGE_PIN T12 IOSTANDARD LVCMOS33 } [get_ports { shield_spi_io0_io }];

# MISO / IO1 (Pin W15, Bank 34, 3.3V LVCMOS) - Dedicated SPI Header J7 Pin 1 (CK_MISO)
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports { shield_spi_io1_io }];

# SS / CS_n (Pin F16, Bank 35, 3.3V LVCMOS) - Dedicated SPI Header J7 Pin 5 (CK_SS)
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 } [get_ports { shield_spi_ss_io }];
