# ============================================================================
# run_soc.do — compile everything and run the full-SoC system test
# (firmware blinks the LED and prints "Hi!\n" over UART)
# Usage (from sim/modelsim):  vsim -do "do run_soc.do"
#
# Best waveform signals: led_o, uart_tx_o, the AXI channels inside u_xbar,
# and /tb_soc/dut/u_core/pc_q with /tb_soc/dut/stall.
# ============================================================================

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -sv +incdir+../../rtl/core ../../rtl/core/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/bus/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/periph/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/soc/*.sv
vlog -sv +incdir+../../rtl/core ../../tb/system/tb_soc.sv

vsim -voptargs=+acc -onfinish stop work.tb_soc
add wave /tb_soc/led /tb_soc/uart_tx
add wave /tb_soc/dut/u_core/pc_q /tb_soc/dut/stall
run -all
wave zoom full
