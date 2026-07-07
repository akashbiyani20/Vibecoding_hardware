#!/bin/sh
# Run a unit / integration / system testbench with Icarus Verilog.
# Usage: sim/icarus/run.sh <name>   e.g.  run.sh pc | core | axi_bridge | soc
set -e
NAME="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/sim/icarus/build"
mkdir -p "$BUILD"
cd "$BUILD"
# testbench may live in unit/, integration/ or system/
for d in unit integration system; do
  [ -f "$ROOT/tb/$d/tb_$NAME.sv" ] && TB="$ROOT/tb/$d/tb_$NAME.sv"
done
# compile all RTL directories that exist
SRCS="$ROOT/rtl/core/*.sv"
[ -d "$ROOT/rtl/bus" ]    && SRCS="$SRCS $ROOT/rtl/bus/*.sv"
[ -d "$ROOT/rtl/periph" ] && SRCS="$SRCS $ROOT/rtl/periph/*.sv"
[ -d "$ROOT/rtl/soc" ]    && SRCS="$SRCS $ROOT/rtl/soc/*.sv"
iverilog -g2012 -I "$ROOT/rtl/core" -o "tb_$NAME.vvp" "$TB" $SRCS
vvp "tb_$NAME.vvp" "+hexdir=$ROOT/sw/build"
