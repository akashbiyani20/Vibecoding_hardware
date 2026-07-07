# ============================================================================
# run_soc_c.do — run the compiled-C firmware system test
# (C demo prints, computes, blinks the LED, echoes typed characters)
# Usage (from sim/modelsim):  vsim -do "do run_soc_c.do"
# ============================================================================

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -sv +incdir+../../rtl/core ../../rtl/core/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/bus/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/periph/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/soc/*.sv
vlog -sv +incdir+../../rtl/core ../../tb/system/tb_soc_c.sv

vsim -voptargs=+acc -onfinish stop work.tb_soc_c
add wave /tb_soc_c/led /tb_soc_c/uart_tx /tb_soc_c/uart_rx
add wave /tb_soc_c/dut/u_core/pc_q /tb_soc_c/dut/stall
run -all
wave zoom full
