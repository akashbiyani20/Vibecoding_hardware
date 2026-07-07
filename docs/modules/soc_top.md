# SoC Top (`rtl/soc/soc_top.sv`)

## Purpose

The complete chip: CPU core + instruction memory + AXI bridge + interconnect
+ RAM + GPIO + UART. Its ports are exactly what would leave an FPGA:
clock, reset, 8 LED pins, 1 serial pin (plus a debug `illegal_o`).

```
core ──fetch──> imem                      (private port, Harvard-style)
core ──data──> bridge ──AXI──> xbar ──> { RAM, GPIO, UART }
```

## How firmware gets "flashed"

The imem is initialized from a hex file (`PROGRAM_HEX` parameter — produced
by `sw/asm.py`). In simulation the testbench loads it with `$readmemh`;
on an FPGA the same memory becomes block RAM whose contents are baked into
the bitstream. Same file, same mechanism, different loader.

## Why fetch doesn't go over AXI

Instruction fetch has its own private port to imem instead of sharing the
bus. This keeps the single-cycle fetch (a fetch every cycle would saturate
the bus and stall constantly) and mirrors a real pattern — separate
instruction/data paths (Harvard architecture) are standard in
microcontrollers. Cost: instructions can't read/write imem. Fine for now.

## Parameters

| Parameter    | Meaning                          | Sim value | FPGA value |
|--------------|-----------------------------------|-----------|------------|
| PROGRAM_HEX  | firmware image                    | per-test  | your .hex  |
| CLKS_PER_BIT | UART baud divider                 | 16        | 868 (115200 @ 100 MHz) |
| GPIO_WIDTH   | number of LED pins                | 8         | board LEDs |

## Verification (`tb/system/tb_soc.sv`, 34 checks)

Pure black-box — the testbench touches only real pins:

- **prog_blink**: LED observed toggling 22 times with a cycle-exact steady
  period (the delay loop's fingerprint).
- **prog_hello**: an independent serial receiver decodes the TX pin and must
  read exactly "Hi!\n".
- Illegal-instruction watchdog armed the whole time.

Status: **PASS**. This is the simulation equivalent of flashing the board
and watching the LED + terminal.

## Future improvements

- UART receive path (keyboard input)
- Timer peripheral → accurate blink rates without delay loops
- Interrupt controller → replace polling
- FPGA port: pin constraints + clock wizard, RTL unchanged
