# The C Toolchain (`sw/c/`)

## What it does

```
main.c --gcc--> prog_c.elf --objcopy--> .bin --bin2hex--> two hex images
                                    prog_c_text.hex -> instruction memory
                                    prog_c_data.hex -> data RAM
```

One command: `sh sw/c/build.sh` (or `build.sh mycode.c myname`).
The hex images are "flashed" by the testbench ($readmemh) — and by BRAM
initialization in an FPGA bitstream later. Same files, same idea.

## The pieces and why each exists

- **link.ld** — tells the linker our memory map: code into IMEM (0x0),
  constants/globals/stack into RAM (0x2000_0000). Key subtlety: string
  literals (.rodata) must live in RAM because our Harvard-style core cannot
  load data from instruction memory.
- **crt0.S** — the 20 instructions before main(): set the stack pointer,
  set the global pointer, zero .bss, call main. This is what "the C runtime"
  actually means at the bottom.
- **bsp.h** — peripheral registers as volatile pointers, plus uart_putc/
  puts/getc, number printing, and timer delays. `volatile` is what turns
  a C assignment into a guaranteed bus transaction.
- **bin2hex.py** — raw binary to $readmemh format (32-bit LE words).

## Compiler flags that matter

- `-march=rv32i -mabi=ilp32` — exactly our hardware: no multiply, no float.
  C multiplication still works: gcc links `__mulsi3` from libgcc, a software
  multiply built from adds and shifts (`-lgcc`).
- `-nostdlib -ffreestanding` — no OS, no libc; bsp.h is our "library".
- `-O2` — realistic code, and it fits: the demo is 876 bytes.

## Installing the compiler (Windows)

Any riscv gcc works. Easiest: xPack GNU RISC-V Embedded GCC
(https://xpack.github.io/dev-tools/riscv-none-elf-gcc/) — download, unzip,
add to PATH, then `CROSS=riscv-none-elf- sh sw/c/build.sh`.
Prebuilt hex images are committed in sw/build/, so the system test runs in
ModelSim even without a compiler installed.

## Proof it works (`tb/system/tb_soc_c.sv`)

The compiled demo runs on the SoC in simulation; the testbench plays
terminal and checks the whole session byte-for-byte:

```
hello from C!     <- string literal via .rodata + LBU byte loads
answer=42         <- .data preload
counter=0         <- .bss zeroing by crt0
7*7=49            <- __mulsi3 software multiply
blink done        <- GPIO + timer-based delay
B2                <- we typed "A1", firmware echoed +1 (UART RX)
bye
```

Plus 6 LED toggles observed on the pins. Status: PASS.
