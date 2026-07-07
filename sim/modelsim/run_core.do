# ============================================================================
# run_core.do — compile everything and run the CPU integration test
# Usage (from sim/modelsim):  vsim -do "do run_core.do"
# ============================================================================

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -sv +incdir+../../rtl/core ../../rtl/core/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/bus/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/periph/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/soc/*.sv
vlog -sv +incdir+../../rtl/core ../../tb/integration/tb_core.sv

vsim -voptargs=+acc -onfinish stop work.tb_core
add wave -r /tb_core/dut/*
run -all
wave zoom full
