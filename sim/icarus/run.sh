#!/bin/sh
# Run a unit or integration testbench with Icarus Verilog.
# Usage: sim/icarus/run.sh pc      -> compiles tb_pc.sv + rtl, runs it
set -e
NAME="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/sim/icarus/build"
mkdir -p "$BUILD"
cd "$BUILD"
# testbench may live in unit/ or integration/
TB="$ROOT/tb/unit/tb_$NAME.sv"
[ -f "$TB" ] || TB="$ROOT/tb/integration/tb_$NAME.sv"
iverilog -g2012 \
  -I "$ROOT/rtl/core" \
  -o "tb_$NAME.vvp" \
  "$TB" \
  "$ROOT"/rtl/core/*.sv
vvp "tb_$NAME.vvp" "+hexdir=$ROOT/sw/build"
