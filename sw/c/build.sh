#!/bin/sh
# ============================================================================
# build.sh — one command: C source -> hex images ready to "flash"
#   usage: sw/c/build.sh [main.c] [output_name]
# Produces sw/build/<name>_text.hex (code -> imem)
#      and sw/build/<name>_data.hex (constants+globals -> RAM)
# Requires riscv64-unknown-elf-gcc (works for rv32 via -march/-mabi).
# ============================================================================
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$DIR/main.c}"
NAME="${2:-prog_c}"
OUT="$DIR/../build"
CROSS="${CROSS:-riscv64-unknown-elf-}"
mkdir -p "$OUT"

# GCC_B: optional -B dir so a relocated toolchain finds its own as/ld
${CROSS}gcc ${GCC_B:+-B "$GCC_B"} -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib \
    -Wall -Wextra -T "$DIR/link.ld" \
    "$DIR/crt0.S" "$SRC" -lgcc \
    -o "$OUT/$NAME.elf"

${CROSS}objcopy -O binary -j .text "$OUT/$NAME.elf" "$OUT/${NAME}_text.bin"
${CROSS}objcopy -O binary -j .data "$OUT/$NAME.elf" "$OUT/${NAME}_data.bin"

python3 "$DIR/bin2hex.py" "$OUT/${NAME}_text.bin" "$OUT/${NAME}_text.hex"
python3 "$DIR/bin2hex.py" "$OUT/${NAME}_data.bin" "$OUT/${NAME}_data.hex"

${CROSS}size "$OUT/$NAME.elf"
echo "flash images: $OUT/${NAME}_text.hex (imem) + $OUT/${NAME}_data.hex (ram)"
