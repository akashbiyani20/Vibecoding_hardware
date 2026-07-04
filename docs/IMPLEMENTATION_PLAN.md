# Phase 1 Implementation Plan

Build order is bottom-up: leaf modules first, each verified in isolation, then
integration. Nothing is integrated before its unit tests pass.

## Stage A — CPU leaf modules (current)

| # | Module | File | Status |
|---|--------|------|--------|
| 1 | Program Counter | `rtl/core/pc.sv` | done, verified |
| 2 | Register File | `rtl/core/regfile.sv` | done, verified |
| 3 | ALU | `rtl/core/alu.sv` | done, verified |
| 4 | Immediate Generator | `rtl/core/imm_gen.sv` | done, verified |
| 5 | Control Unit / Decoder | `rtl/core/control.sv` | done, verified |
| 6 | Branch Comparator | folded into ALU zero flag + control (`taken = branch & (zero ^ funct3[0])`) | resolved |

## Stage B — Single-cycle core integration (COMPLETE)

7. Instruction memory (`rtl/core/imem.sv`) — done
8. Core top (`rtl/core/core_top.sv`) — done, all leaf modules wired
9. Core-level testbench (`tb/integration/tb_core.sv`) running 5 real RV32I
   programs assembled with `sw/asm.py` — done, 19/19 checks pass
10. Data memory interface (LW/SW) — done as a simple read/write port;
    becomes the AXI4-Lite master in Stage C

## Stage C — Bus and peripherals

11. AXI4-Lite master port on the core (data side)
12. AXI4-Lite interconnect (1 master, N slaves, address-decoded)
13. GPIO peripheral (AXI4-Lite slave)
14. UART TX peripheral (AXI4-Lite slave)

## Stage D — SoC top and system tests

15. `rtl/soc_top.sv`
16. System testbenches: LED blink program, UART "Hello World"
17. FPGA port

## Key decisions made so far

- **Single-cycle CPU first.** Every instruction completes in one cycle. This is
  the easiest architecture to reason about and verify. Pipelining is a later,
  separate phase.
- **SystemVerilog**, conservative subset (`logic`, `always_ff`, `always_comb`,
  no classes/packages) so it runs identically in ModelSim and Icarus Verilog.
- **ALU op encoding = `{funct7[5], funct3}`** (4 bits). This mirrors how RV32I
  itself encodes ALU operations, so the decoder becomes almost trivial —
  an educational win and standard industry practice for small cores.
- **FPGA note:** the NXP FRDM-MCXN947 is a microcontroller board (Cortex-M33) —
  it has **no FPGA fabric**, so it cannot host custom RTL. All RTL stays
  vendor-neutral, targeting boards like Basys 3 / Arty A7 later.

## Verification flow (every module)

1. Self-checking SystemVerilog testbench in `tb/unit/` (directed + random tests,
   automatic pass/fail count, VCD waveform dump)
2. Run in ModelSim: `vsim -do sim/modelsim/<name>.do`
   or Icarus: `sim/icarus/run.sh <name>`
3. Module documentation in `docs/modules/<name>.md`

## Repository layout

```
rtl/core/       CPU modules
rtl/bus/        AXI4-Lite interconnect (Stage C)
rtl/periph/     GPIO, UART (Stage C)
tb/unit/        per-module testbenches
tb/integration/ multi-module testbenches (Stage B+)
tb/system/      full-SoC program tests (Stage D)
sim/modelsim/   .do run scripts
sim/icarus/     shell run scripts
docs/modules/   per-module documentation
sw/             test programs / firmware (Stage B+)
```
