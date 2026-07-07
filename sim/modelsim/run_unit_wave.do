# ============================================================================
# run_unit_wave.do — same as run_unit.do but opens the waveform window
# Usage (ModelSim GUI, from sim/modelsim):  do run_unit_wave.do alu
# ============================================================================

if {[info exists 1]} { set name $1 } else { set name pc }

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -sv +incdir+../../rtl/core ../../rtl/core/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/bus/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/periph/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/soc/*.sv
vlog -sv +incdir+../../rtl/core ../../tb/unit/tb_${name}.sv

vsim -voptargs=+acc -onfinish stop work.tb_${name}
add wave -r /*
run -all
wave zoom full
