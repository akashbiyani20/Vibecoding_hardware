## basys3.xdc — pin constraints for Digilent Basys 3
## (from the Digilent master XDC, trimmed to this design's ports)

## 100 MHz clock
set_property PACKAGE_PIN W5 [get_ports clk100_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk100_i]
create_clock -period 10.000 -name sys_clk [get_ports clk100_i]

## center button = reset
set_property PACKAGE_PIN U18 [get_ports btn_rst_i]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rst_i]

## LEDs 0..7
set_property PACKAGE_PIN U16 [get_ports {led_o[0]}]
set_property PACKAGE_PIN E19 [get_ports {led_o[1]}]
set_property PACKAGE_PIN U19 [get_ports {led_o[2]}]
set_property PACKAGE_PIN V19 [get_ports {led_o[3]}]
set_property PACKAGE_PIN W18 [get_ports {led_o[4]}]
set_property PACKAGE_PIN U15 [get_ports {led_o[5]}]
set_property PACKAGE_PIN U14 [get_ports {led_o[6]}]
set_property PACKAGE_PIN V14 [get_ports {led_o[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_o[*]}]

## USB-UART bridge
set_property PACKAGE_PIN A18 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]
set_property PACKAGE_PIN B18 [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]
