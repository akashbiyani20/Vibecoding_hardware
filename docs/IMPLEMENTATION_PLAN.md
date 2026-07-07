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

## Stage C — Bus and peripherals (COMPLETE)

11. AXI4-Lite master bridge (`rtl/bus/axi_lite_master.sv`) — done; core
    gained a `stall_i` input so bus transactions can take multiple cycles
12. AXI4-Lite interconnect (`rtl/bus/axi_lite_xbar.sv`, 1 master, 3 slaves,
    DECERR default responder) — done
13. Data RAM slave (`rtl/periph/axi_lite_ram.sv`) — done
14. GPIO slave (`rtl/periph/axi_lite_gpio.sv`) — done
15. UART TX slave (`rtl/periph/axi_lite_uart.sv`) — done

## Stage D — SoC top and system tests (SoC COMPLETE, FPGA pending)

16. `rtl/soc/soc_top.sv` — done
17. System testbench `tb/system/tb_soc.sv` — done: firmware blinks the LED
    (steady period verified) and prints "Hi!\n" over UART (decoded off the
    pin by an independent serial receiver). Black-box, pins only.
18. FPGA port — board files ready (`fpga/basys3/`), design lint-clean
    (Verilator -Wall, docs/fpga_readiness.md); waiting for hardware

## Stage E — Full RV32I + timer + UART RX + C toolchain (COMPLETE)

Goal achieved: C code compiles and runs on the SoC — see
tb/system/tb_soc_c.sv and docs/c_toolchain.md. All items below done.

19. Load/store unit (`rtl/core/lsu.sv`): byte/halfword loads and stores
    (LB/LH/LBU/LHU/SB/SH) via wstrb byte lanes + load sign extension.
    C compilers emit these constantly (chars, shorts, strings, structs).
20. Remaining branches BLT/BGE/BLTU/BGEU: control drives the ALU to
    SLT/SLTU for these; take-decision generalized to one XOR.
21. Timer peripheral (0x1000_2000): free-running 64-bit cycle counter —
    accurate delays without calibrated loops.
22. UART receive path: RX register + data-available status bit; firmware
    can now read keyboard input from a terminal.
23. asm.py support for the new instructions (for tests; C replaces it as
    the main workflow).
24. C toolchain (`sw/c/`): riscv gcc (-march=rv32i), linker script matching
    the memory map, crt0 (stack setup + call main), elf-to-hex converter,
    one-command build script.
25. C demo firmware verified on the SoC in simulation.
26. FENCE/ECALL/EBREAK handling: FENCE as NOP (single core needs no
    ordering), ECALL/EBREAK stay illegal until traps exist.

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
