#!/bin/sh
# Run a unit testbench with Icarus Verilog.
# Usage: sim/icarus/run.sh pc      -> compiles tb_pc.sv + rtl, runs it
set -e
NAME="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/sim/icarus/build"
mkdir -p "$BUILD"
cd "$BUILD"
iverilog -g2012 \
  -I "$ROOT/rtl/core" \
  -o "tb_$NAME.vvp" \
  "$ROOT/tb/unit/tb_$NAME.sv" \
  "$ROOT"/rtl/core/*.sv
vvp "tb_$NAME.vvp"
