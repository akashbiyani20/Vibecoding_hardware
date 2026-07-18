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

## Case study: the 17-hour place & route (and what fixed it)

First compilation attempt showed `Total registers: 34,053` and
`Total block memory bits: 0` — both memories had synthesized into discrete
flip-flops instead of M10K block RAM, and the router spent 17 hours fighting
the resulting congestion (warning 16684). Sanity numbers to check on every
FPGA compile of a design with memories:

| Flow Summary line | Broken | Healthy |
|---|---|---|
| Total registers | ~34,000 | ~2,000 |
| Total block memory bits | 0 | ~65,536 |
| Fitter runtime | hours | minutes |

Two RTL causes, both fixed:

1. **RAM in an async-reset process.** Block RAM has no async reset; if the
   memory array is assigned inside `always_ff @(posedge clk or negedge rst)`,
   synthesis silently falls back to registers. Fix: the array and its read
   register live in a clean no-reset process (see axi_lite_ram.sv).
2. **Combinational-read instruction memory.** M10K reads only synchronously.
   Fix: imem reads on the FALLING clock edge — still "same cycle" from the
   core's perspective, but now inferable as block RAM (see imem.sv). The
   fetch and execute now share one clock period, so fpga_top runs the SoC
   on a divided 25 MHz clock with the SDC declaring the generated clock.

The lesson generalizes: simulators execute any legal SystemVerilog, but
synthesis pattern-matches specific TEMPLATES onto physical resources.
When a memory doesn't look exactly like a template, you don't get an
error — you get flip-flops, and the Flow Summary is where you catch it.

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
