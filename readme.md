#### Prerequisites


1. Install Vivado 2019.2
1. Install the Nix package manager <https://nixos.org/nix/download.html>. It's not required to build, but handles non-Xilinx dependencies and is the only supported method.
1. For programming/flashing FPGA, make sure
   [xvcd](https://github.com/RHSResearchLLC/xvcd) is running on port 2542.

#### Flashing `picodma.bit` to FPGA flash memory

1. Run `nix-shell --command './Shakefile.hs flashFpga'`
2. Requires FPGA to be power cycled to load design, or:

#### Reprogramming running FPGA with `picodma.bit`

1. Run `nix-shell --command './Shakefile.hs programFpga'`
2. Doesn't require FPGA to be flashed first

#### Building `picodma.bit` without programming/flashing FPGA

1. Run `nix-shell --command './Shakefile.hs vivado'`

SPI op codes (defined in src/Top.hs)
===

r/w | byte code | description
--- | --- | ---
rw | 0 | address low
rw | 1 | address high
rw | 2 | PCIe write trigger
rw | 3 | search length, num 32bit chunks
rw | 4 | value low
rw | 5 | value high
rw | 6 | buffer select
r | 7 | buffer value
r | 8 | buffer offset
r | 9 | PCIe read busy
w | 10 | PCIe read trigger
r | 11 | PCIe read status
r | 12 | PCIe read stat length = number of 64bit chunks
r | 13 | debug index
r | 14 | PCIe search busy
w | 15 | PCIe search trigger
r | 16 | PCIe search done
r | 17 | PCIe search length = number of 64bit addresses
rw | 18 | search type, 0=none,1=16bit,2=32bit
rw | 19 | search value
r | 20 | debug requester
r | 21 | debug pci tx buffers count
r | 22 | debug transaction writer ready
r | 23 | debug transaction error drop
r | 24 | debug transaction sent count
r | 25 | debug tx has been ready since last message
r | 26 | debug read trigger count
r | 27 | debug search trigger count
r | 28 | debug transaction received count

### PicoEVB pins for reference

~~~
# Auxillary I/O Connector
# auxio[0] - conn pin 1
# auxio[1] - conn pin 2
# auxio[2] - conn pin 4
# auxio[3] - conn pin 5
set_property PACKAGE_PIN A14 [get_ports auxio_tri_io[0]]
set_property PACKAGE_PIN A13 [get_ports auxio_tri_io[1]]
set_property PACKAGE_PIN B12 [get_ports auxio_tri_io[2]]
set_property PACKAGE_PIN A12 [get_ports auxio_tri_io[3]]

set_property PACKAGE_PIN A14 [get_ports sel]
set_property PACKAGE_PIN A13 [get_ports mosi]
set_property PACKAGE_PIN B12 [get_ports miso]
set_property PACKAGE_PIN A12 [get_ports sclk]
set_property IOSTANDARD LVCMOS33 [get_ports sel]
set_property IOSTANDARD LVCMOS33 [get_ports mosi]
set_property IOSTANDARD LVCMOS33 [get_ports miso]
set_property IOSTANDARD LVCMOS33 [get_ports sclk]
~~~
