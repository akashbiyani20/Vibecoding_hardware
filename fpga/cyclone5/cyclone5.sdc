# ============================================================================
# cyclone5.sdc — timing constraints (TimeQuest)
# One clock, 50 MHz. Everything else is derived or asynchronous I/O.
# ============================================================================

create_clock -name clk50 -period 20.000 [get_ports clk50_i]

derive_clock_uncertainty

# asynchronous inputs/outputs: don't time them against the clock
set_false_path -from [get_ports key0_n_i]
set_false_path -from [get_ports uart_rx_i]
set_false_path -to   [get_ports uart_tx_o]
set_false_path -to   [get_ports {led_o[*]}]
