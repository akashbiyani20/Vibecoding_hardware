# RISC-V SoC from scratch

I built a complete RV32I system-on-chip in SystemVerilog: CPU core, AXI4-Lite bus, peripherals, and a bare-metal C toolchain. Every module was written from scratch, documented, and verified before integration. It runs compiled C code and synthesizes for a Cyclone V FPGA.

This is the output of `sw/c/main.c`, compiled with riscv-gcc, running on the SoC — decoded off the UART pin by the testbench:

```
hello from C!
answer=42        globals initialized from the .data image
counter=0        .bss zeroed by my crt0
7*7=49           software multiply from libgcc (the core has no multiplier)
blink done       LED blinked using timer delays
B2               I typed "A1" into the serial line, firmware echoed each char +1
bye
```

## Architecture

```
                 +---------------------------------------------+
                 |                  soc_top                    |
                 |  +--------+         +--------------+        |
  clk, rst_n --->|  |  imem  |<-fetch--|  RV32I core  |        |
                 |  |  4 KB  |         | single-cycle |        |
                 |  +--------+         +------+-------+        |
                 |                            | load/store     |
                 |                    +-------+--------+       |
                 |                    | AXI4-Lite      |       |
                 |                    | bridge + xbar  |       |
                 |                    +--+---+---+---+-+       |
                 |                       |   |   |   |         |
                 |                     RAM GPIO UART TIMER     |
                 |                    4 KB   |   |  |          |
                 +---------------------------|---|--|----------+
                                        led[7:0] tx rx
```

The core executes one instruction per clock. Fetch, decode, register read, ALU, and write-back all settle within a single cycle; the PC just steps. When a load or store goes out on the bus, the bridge stalls the whole core until the AXI handshake completes, so bus latency stretches the instruction instead of breaking it.

Memory map: RAM at `0x2000_0000`, GPIO at `0x1000_0000`, UART at `0x1000_1000`, timer at `0x1000_2000`. Register maps are in [docs/memory_map.md](docs/memory_map.md), and every module has its own write-up in `docs/modules/`.

## What it can do

- Execute the RV32I base ISA: 37 instructions, everything except ECALL/EBREAK/CSR (those wait for trap support). Byte and halfword memory access included, so gcc output just works.
- Run C: linker script, crt0, and a board-support header in `sw/c/`. One command (`sh sw/c/build.sh`) turns `main.c` into hex images for the memories.
- Run assembly through `sw/asm.py`, a small two-pass assembler I wrote so tests don't need a toolchain.
- Print and read text over a real 8N1 UART, drive LEDs, measure time with a 64-bit cycle counter.

## Running it

ModelSim, from `sim/modelsim`:

```tcl
do run_soc_c.do      # the C demo above
do run_soc.do        # assembly firmware: blink + hello
do run_unit.do alu   # any single module (pc, regfile, control, ...)
```

Same tests run under Icarus Verilog via `sim/icarus/run.sh <name>`. All 12 testbenches are self-checking (about 3,950 checks total) and print PASS/FAIL, so waveforms are for understanding, not for verifying by eye.

## FPGA

Synthesizes on Cyclone V with Quartus Prime (`fpga/cyclone5/`, project included): ~2,000 registers, 65,536 block-memory bits, place and route in about 7 minutes, SoC clocked at 25 MHz. Basys 3 files exist too (`fpga/basys3/`); the RTL itself is vendor-neutral.

Getting there was a lesson. My first compile ran the fitter for 17 hours because both memories had silently synthesized into 32,768 flip-flops instead of block RAM — the array sat in an async-reset process, and my byte-enable style didn't match Quartus's inference template. The full post-mortem is in [fpga/cyclone5/README.md](fpga/cyclone5/README.md); the short version is that block RAM inference is template matching, and the Flow Summary's "block memory bits" line is where you catch it.

## Future work

Paused here for my thesis. Next steps, roughly in order:

- Machine-mode traps and interrupts (mtvec/mepc/mcause + timer interrupt) — removes the busy-polling and unlocks ECALL
- 5-stage pipeline, then compare Fmax against the single-cycle baseline from the Quartus timing report
- M extension in hardware, UART FIFO
- Board bring-up once I have physical hardware (pin templates for DE0-CV and DE1-SoC are ready in the qsf)
