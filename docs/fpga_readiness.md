# FPGA Readiness Report

Checked before any board exists, so the eventual port is a non-event.

## Checks performed

1. **Verilator 4.038 full-design lint** (`--lint-only -Wall`, top = soc_top).
   Verilator elaborates the entire design like a synthesis frontend.
   Result: zero errors, zero latch/multidriver/combinational-loop warnings.
   Two WIDTH warnings in the UART baud counter were fixed with a properly
   sized reload constant. Remaining UNUSED warnings are inherent to
   memory-mapped design (peripherals decode only low address bits; AXI resp
   inputs are unused until we add error handling) — reviewed and accepted.
2. **Construct audit** — everything used is in the synthesizable subset of
   Vivado/Quartus/ModelSim: `always_ff` with async active-low reset,
   `always_comb`, `unique case` with full defaults (no latches), typed
   parameters, `$clog2`, `$readmemh` in an initial block (Vivado infers
   BRAM initialization from this — the standard idiom).
3. **No vendor IP, no primitives, no clock trickery** — single clock domain,
   single reset. The only board-specific pieces are pin constraints and
   (optionally) a clock wizard, both isolated in `fpga/`.

## Known board-dependent items (deliberate, documented)

- **Clock frequency**: timing was not analyzed (no target device yet). The
  single-cycle core's critical path (imem → decode → ALU → writeback) will
  limit Fmax; on Artix-7 expect the 50–100 MHz range. If 100 MHz fails
  timing, halve the board clock — nothing in the design assumes a frequency
  except the UART divider parameter.
- **imem is combinational-read** — synthesizes to distributed RAM (LUTRAM),
  fine at 4 KB. Moving to block RAM would add a fetch register stage; noted
  as a future optimization, not needed to be functional.
- **Reset polarity/source**: boards give a button (active high, bouncy).
  The fpga_top wrapper handles inversion + synchronization.

## The port procedure (when the board arrives)

1. Create a Vivado project targeting your device, add `rtl/**` + `fpga/basys3/fpga_top.sv`
2. Add `fpga/basys3/basys3.xdc` (pin constraints — edit if a different board)
3. Set the firmware: parameter PROGRAM_HEX -> your `sw/build/*.hex`
4. Synthesize, implement, check timing, generate bitstream, program
5. LED blinks / terminal at 115200 baud shows your program output

Estimated effort with the provided files: an afternoon.
