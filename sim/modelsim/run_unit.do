# ============================================================================
# run_unit.do — compile RTL + one unit testbench and run it in ModelSim
#
# Usage (from the sim/modelsim directory):
#   Console:  vsim -c -do "do run_unit.do pc"
#   GUI:      vsim -do "do run_unit.do pc"        (then: add wave -r /*; run -all)
#
# Replace "pc" with: pc | regfile | alu
# ============================================================================

# ModelSim passes do-script arguments as $1, $2, ...
if {[info exists 1]} { set name $1 } else { set name pc }

if {[file exists work]} { vdel -lib work -all }
vlib work

# compile all core RTL + the requested testbench
vlog -sv +incdir+../../rtl/core ../../rtl/core/*.sv
vlog -sv +incdir+../../rtl/core ../../tb/unit/tb_${name}.sv

vsim -voptargs=+acc work.tb_${name}
run -all
