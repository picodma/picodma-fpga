###############################################################################
# Pinout and Related I/O Constraints
###############################################################################
# SYS reset (input) signal.  The sys_reset_n signal is generated
# by the PCI Express interface (PERST#).
set_property PACKAGE_PIN A10 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
set_property PULLDOWN true [get_ports sys_rst_n]

# SYS clock 100 MHz (input) signal. The sys_clk_p and sys_clk_n
# signals are the PCI Express reference clock.
set_property PACKAGE_PIN B6 [get_ports sys_clk_p]
set_property PACKAGE_PIN B5 [get_ports sys_clk_n]

# PCIe x1 link
# set_property LOC GTPE2_CHANNEL_X0Y3 [get_cells {pcie_7x_0/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
#
set_property LOC GTPE2_CHANNEL_X0Y3 [get_cells {*/pcie_7xi_inst/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
# set_property LOC GTPE2_CHANNEL_X0Y3 [get_cells {*/pcie_7x_0_inst/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
# set_property LOC GTPE2_CHANNEL_X0Y3 [get_cells {*/pcie_7x_0_inst/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
# set_property PACKAGE_PIN G3 [get_ports {pcie_mgt_rx[0]}]
# set_property PACKAGE_PIN G4 [get_ports {pcie_mgt_rx[1]}]
# set_property PACKAGE_PIN B1 [get_ports {pcie_mgt_tx[0]}]
# set_property PACKAGE_PIN B2 [get_ports {pcie_mgt_tx[1]}]
set_property PACKAGE_PIN G3 [get_ports pcie_mgt_rx_n]
set_property PACKAGE_PIN G4 [get_ports pcie_mgt_rx_p]
set_property PACKAGE_PIN B1 [get_ports pcie_mgt_tx_n]
set_property PACKAGE_PIN B2 [get_ports pcie_mgt_tx_p]

# MGT Loopback
#set_property PACKAGE_PIN C4 [get_ports loop_mgt_rxp]
#set_property PACKAGE_PIN C3 [get_ports loop_mgt_rxn]
#set_property PACKAGE_PIN D2 [get_ports loop_mgt_txp]
#set_property PACKAGE_PIN D1 [get_ports loop_mgt_txn]

###############################################################################
# Timing Constraints
###############################################################################

create_clock -period 10.000 -name sys_clk [get_ports sys_clk_p]

###############################################################################
# Physical Constraints
###############################################################################

# Input reset is resynchronized within FPGA design as necessary
set_false_path -from [get_ports sys_rst_n]
#eh
#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets sys_rst_n_IBUF]

#########################################################################################################################
# End PCIe Core Constraints
#########################################################################################################################


###############################################################################
# NanoEVB, PicoEVB common I/O
###############################################################################

set_property PACKAGE_PIN V14 [get_ports {status_leds[2]}]
set_property PACKAGE_PIN V13 [get_ports {status_leds[1]}]
set_property PACKAGE_PIN V12 [get_ports {status_leds[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_leds[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_leds[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_leds[0]}]
set_property PULLUP true [get_ports {status_leds[2]}]
set_property PULLUP true [get_ports {status_leds[1]}]
set_property PULLUP true [get_ports {status_leds[0]}]
set_property DRIVE 8 [get_ports {status_leds[2]}]
set_property DRIVE 8 [get_ports {status_leds[1]}]
set_property DRIVE 8 [get_ports {status_leds[0]}]

# clkreq_l is active low clock request for M.2 card to
# request PCI Express reference clock
set_property PACKAGE_PIN A9 [get_ports clkreq_l]
set_property IOSTANDARD LVCMOS33 [get_ports clkreq_l]
set_property PULLDOWN true [get_ports clkreq_l]

# Auxillary I/O Connector
# auxio[0] - conn pin 1
# auxio[1] - conn pin 2
# auxio[2] - conn pin 4
# auxio[3] - conn pin 5
# Note: These I/O may be re-purposed to use with XADC as analog inputs

set_property PACKAGE_PIN A14 [get_ports spi_select]
set_property PACKAGE_PIN A13 [get_ports spi_mosi]
set_property PACKAGE_PIN B12 [get_ports spi_miso]
set_property PACKAGE_PIN A12 [get_ports spi_clock]
set_property IOSTANDARD LVCMOS33 [get_ports spi_select]
set_property IOSTANDARD LVCMOS33 [get_ports spi_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports spi_miso]
set_property IOSTANDARD LVCMOS33 [get_ports spi_clock]

#set_property PULLDOWN true [get_ports spi_select]
#set_property PULLUP true [get_ports spi_clock]


###############################################################################
# PicoEVB-specific I/O
# Digital IO on PCIe edge connector (PicoEVB Rev.D and newer)
###############################################################################
# set_property PACKAGE_PIN K2 [get_ports {di_edge[0]}]
# set_property PACKAGE_PIN K1 [get_ports {di_edge[1]}]
# set_property PACKAGE_PIN V2 [get_ports {do_edge[0]}]
# set_property PACKAGE_PIN V3 [get_ports {do_edge[1]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {di_edge[0]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {di_edge[1]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {do_edge[0]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {do_edge[1]}]



# High-speed configuration so FPGA is up in time to negotiate with PCIe root complex
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

# set_property OFFCHIP_TERM NONE [get_ports TxD]

# set_input_delay -clock pcie_7x_0_user_clk_out -min 2 -max 2 [get_ports spi_select]
# set_input_delay -clock pcie_7x_0_user_clk_out -min 2 -max 2 [get_ports spi_mosi]
# set_input_delay -clock pcie_7x_0_user_clk_out -min 2 -max 2 [get_ports spi_miso]
# set_input_delay -clock pcie_7x_0_user_clk_out -min 2 -max 2 [get_ports spi_clock]
