# Cyclone V / Quartus Prime port

## Synthesize today (no board needed)

1. Quartus Prime → Open Project → `fpga/cyclone5/cyclone5.qpf`
2. Copy firmware into this directory so $readmemh finds it at synthesis:
   `sw/build/prog_c_text.hex` and `prog_c_data.hex`
3. Processing → Start Compilation
4. Read the two reports that matter (see below)

If RAM initialization warns about $readmemh, convert to MIF:
`python3 sw/c/hex2mif.py sw/build/prog_c_text.hex prog_c_text.mif` and use
an altsyncram instance or `ram_init_file` assignment — but try hex first;
recent Quartus versions accept $readmemh for inferred RAM.

## What to look at after compilation (the learning part)

- **Fitter → Resource Section**: ALMs used by each module (Chip Planner
  makes this visual). Expect the register file and xbar to dominate.
- **Timing Analyzer → Fmax Summary**: the single-cycle core's critical path
  is fetch → decode → register read → ALU → write-back mux, all in one
  cycle. Whatever Fmax you see, THAT is the number pipelining exists to
  improve — remember it as the "before" measurement.
- **Timing Analyzer → Report Timing** on the worst path: walk through the
  listed cells and recognize your own modules in it.

## When a board arrives

Uncomment its pin block in `cyclone5.qsf` (DE0-CV and DE1-SoC templates
included), verify every pin against the board's user manual, recompile,
and program via Tools → Programmer. UART needs a 3.3V USB-serial adapter
on the GPIO header (TX/RX/GND); any $3 FTDI/CP2102 dongle works at 115200.

## Artix-7 (Basys 3) vs Cyclone V — what actually differs

| | Basys 3 / Artix-7 | Cyclone V boards |
|---|---|---|
| Toolchain | Vivado, .xdc pins | Quartus, .qsf pins |
| Board clock | 100 MHz | 50 MHz → CLKS_PER_BIT 434 |
| Reset button | active high | active low (KEY) |
| USB-UART on board | yes | usually via GPIO header + adapter |
| Logic cell | 6-input LUT slices | ALMs (8-input adaptive) |
| Our RTL | identical | identical |

Different companies, different physical cells and tools — but synthesizable
SystemVerilog is the common language, which is why `rtl/` needed zero edits.
