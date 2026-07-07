# ============================================================================
# run_unit.do — compile all RTL + one unit testbench and run it in ModelSim
#
# Usage (from the sim/modelsim directory):
#   Console:  vsim -c -do "do run_unit.do pc"
#   GUI:      vsim -do "do run_unit.do pc"
#
# Names: pc | regfile | alu | imm_gen | control | axi_bridge | axi_gpio | axi_uart
# ============================================================================

if {[info exists 1]} { set name $1 } else { set name pc }

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -sv +incdir+../../rtl/core ../../rtl/core/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/bus/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/periph/*.sv
vlog -sv +incdir+../../rtl/core ../../rtl/soc/*.sv
vlog -sv +incdir+../../rtl/core ../../tb/unit/tb_${name}.sv

vsim -voptargs=+acc work.tb_${name}
run -all
