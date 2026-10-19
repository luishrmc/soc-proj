# ==============================================================================
# cora_z7_io.xdc: Physical and IO constraints for Digilent Cora Z7-10
# Target: XC7Z010-1CLG400C
# ==============================================================================

# ------------------------------------------------------------------------------
# Dedicated SPI Slave Interface from ESP32 (Arduino Shield Header J1)
# Referenced against docs/cora7z/Cora+Z7_sch-public.pdf and INTERFACES.md
# ------------------------------------------------------------------------------

# SCK (Pin G20, Bank 35, 3.3V LVCMOS)
set_property -dict { PACKAGE_PIN G20 IOSTANDARD LVCMOS33 } [get_ports { shield_spi_sck_io }];

# MOSI / IO0 (Pin T10, Bank 34, 3.3V LVCMOS)
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { shield_spi_io0_io }];

# MISO / IO1 (Pin V15, Bank 34, 3.3V LVCMOS)
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { shield_spi_io1_io }];

# SS / CS_n (Pin F16, Bank 35, 3.3V LVCMOS)
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 } [get_ports { shield_spi_ss_io }];
