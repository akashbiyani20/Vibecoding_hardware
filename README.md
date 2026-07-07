# RISC-V SoC From Scratch

A complete, working **RV32I System-on-Chip built from scratch in SystemVerilog** — CPU, AXI4-Lite bus, peripherals, and a bare-metal C toolchain — developed module by module with every block documented, unit-tested, and verified before integration.

**It runs compiled C code.** This is the actual output of `sw/c/main.c`, compiled with riscv-gcc, executed on the SoC in simulation, and decoded off the serial pin by the testbench:

```
hello from C!      <- string literals (.rodata), byte loads
answer=42          <- initialized globals (.data)
counter=0          <- zeroed globals (.bss, crt0)
7*7=49             <- multiply on a CPU with no multiplier (libgcc __mulsi3)
blink done         <- GPIO LED blinked with timer-accurate delays
B2                 <- testbench typed "A1", firmware echoed each char +1 (UART RX)
bye
```

---

## What this project can do

- **Execute the full RV32I base ISA** (37 instructions of the RV32I base ISA — all except ECALL/EBREAK/CSR, which await trap support; FENCE executes as NOP): arithmetic, logic, shifts, comparisons, byte/halfword/word loads and stores, all six conditional branches, jumps, function calls
- **Run programs written in C** — a complete bare-metal toolchain (`sw/c/`): linker script matching the memory map, crt0 startup, board support header, one-command build to flashable hex images
- **Run programs written in assembly** — a self-contained two-pass assembler (`sw/asm.py`), no toolchain install needed
- **Talk to the world**: drive LEDs over memory-mapped GPIO, print and receive text over a real 8N1 UART, measure time with a 64-bit cycle counter
- **Communicate over an industry-standard bus**: the CPU reaches all peripherals through AXI4-Lite with full valid/ready handshaking
- **Drop onto an FPGA**: Verilator-lint-clean, vendor-neutral RTL with a ready Basys 3 wrapper and pin constraints (`fpga/`)

Verification status: **12 self-checking testbenches, ~3,950 checks, all passing** — unit tests for every module, integration tests running real programs on the core, and black-box system tests that only observe the chip's physical pins.

---

## Architecture

```
                    +--------------------------------------------------+
                    |                     soc_top                      |
                    |   +--------+          +--------------+           |
   clk, rst_n ----->|   |  imem  |<--fetch--|   core_top   |           |
                    |   | (4 KB) |          | RV32I 1-cycle|           |
                    |   +--------+          +------+-------+           |
                    |                              | load/store        |
                    |                     +--------+---------+         |
                    |                     | axi_lite_master  |         |
                    |                     |  (bus bridge)    |         |
                    |                     +--------+---------+         |
                    |                              | AXI4-Lite         |
                    |                     +--------+---------+         |
                    |                     |  axi_lite_xbar   |         |
                    |                     | (1 master/4 slv) |         |
                    |                     +--+----+----+---+-+         |
                    |                        |    |    |   |           |
                    |                   +----+ +--+-+ +-+--+ +----+    |
                    |                   |RAM | |GPIO| |UART| |TIMER|   |
                    |                   |4 KB| +--+-+ ++--++ +----+    |
                    |                   +----+    |    |  |            |
                    +-----------------------------|----|--|------------+
                                              led[7:0] tx rx
```

### The CPU core (`rtl/core/`)

A single-cycle RV32I processor — every instruction fetches, decodes, executes, and retires in one clock (stretching automatically when the bus needs longer). Built from small, individually verified modules:

| Module | Role |
|--------|------|
| `pc.sv` | Program counter register |
| `imem.sv` | Instruction memory (4 KB, hex-initialized) |
| `control.sv` | Decoder: instruction → control signals for the whole datapath |
| `regfile.sv` | 32 × 32-bit registers, x0 hard-wired to zero |
| `imm_gen.sv` | Extracts + sign-extends all five immediate formats |
| `alu.sv` | 10 operations; op encoding taken directly from the instruction bits |
| `lsu.sv` | Byte/halfword alignment, sign/zero extension, misalignment detection |
| `core_top.sv` | Wires everything + branch decision, write-back and next-PC logic |

### The bus (`rtl/bus/`)

AXI4-Lite throughout — the same protocol used to attach peripherals in most commercial SoCs. `axi_lite_master.sv` converts the core's simple memory port into handshaked bus transactions and stalls the core until each completes. `axi_lite_xbar.sv` decodes addresses, routes to the right peripheral, and answers unmapped accesses with DECERR instead of hanging.

### Peripherals (`rtl/periph/`)

| Peripheral | Base address | Function |
|------------|--------------|----------|
| Data RAM | `0x2000_0000` | 4 KB working memory (globals, stack) |
| GPIO | `0x1000_0000` | 8 output pins (LEDs) |
| UART | `0x1000_1000` | 8N1 serial, transmit + receive, poll-driven |
| Timer | `0x1000_2000` | Free-running 64-bit cycle counter, rollover-safe reads |

Full register maps: [`docs/memory_map.md`](docs/memory_map.md).

---

## Quick start

Simulation works with **ModelSim/Questa** (scripts provided) or **Icarus Verilog**.

Run the flagship demo — compiled C firmware on the full SoC:

```tcl
# ModelSim, from sim/modelsim:
do run_soc_c.do
```

```sh
# or Icarus:
sh sim/icarus/run.sh soc_c
```

Other targets: `run_soc.do` (assembly firmware: LED blink + UART hello), `run_core.do` (8 assembly programs on the bare core), `run_unit.do <name>` (any single module: `pc`, `alu`, `regfile`, `imm_gen`, `control`, `axi_bridge`, `axi_gpio`, `axi_uart`, `axi_timer`). Every testbench is self-checking and ends with `RESULT: PASS/FAIL`.

### Write your own firmware in C

```sh
# edit sw/c/main.c (bsp.h gives you uart_puts, GPIO_OUT, delay_cycles, ...)
sh sw/c/build.sh            # -> sw/build/prog_c_text.hex + prog_c_data.hex
# rerun run_soc_c.do — the testbench flashes those images
```

Needs any riscv-gcc (`-march=rv32i`); install pointers and design details in [`docs/c_toolchain.md`](docs/c_toolchain.md). Prebuilt hex images are committed, so the demo runs without a compiler.

### Or in assembly

```sh
python3 sw/asm.py sw/prog1_arith.s -o sw/build/prog1_arith.hex   # or --list
```

---

## Repository layout

```
rtl/core/     CPU modules            docs/modules/   one document per module
rtl/bus/      AXI4-Lite bridge+xbar  docs/           memory map, plan, toolchain,
rtl/periph/   RAM, GPIO, UART, timer                 FPGA readiness report
rtl/soc/      soc_top (the chip)     sim/modelsim/   .do run scripts
tb/unit/      per-module testbenches sim/icarus/     shell runner
tb/integration/ programs on the core sw/             assembler + asm programs
tb/system/    pins-only SoC tests    sw/c/           C toolchain + demo
fpga/basys3/  board wrapper + XDC
```

---

## Design philosophy

Every module was **understood before it was implemented, and verified before it was integrated**: written module by module, each with its own documentation (`docs/modules/`) explaining purpose, interface, timing, and the design decisions — written for someone learning digital design. Verification mirrors industry practice: self-checking unit testbenches (directed + random against reference models), integration tests executing real programs, black-box system tests that treat the SoC as a sealed chip, and an every-cycle illegal-instruction watchdog.

Deliberate simplifications, documented where they live: single-cycle core (no pipeline yet), one outstanding bus transaction, poll-driven I/O (no interrupts yet), Harvard-style split with fetch on a private port.

## FPGA status

The design is lint-clean (Verilator `-Wall`), uses only the standard synthesizable subset, and `fpga/basys3/` contains a ready top-level wrapper (reset synchronizer, 115200-baud config) plus pin constraints. See [`docs/fpga_readiness.md`](docs/fpga_readiness.md). Awaiting hardware for the bring-up.

## Roadmap (short version)

Interrupts + trap handling (unlocks ECALL/EBREAK), UART FIFO, hardware multiply (M extension), 5-stage pipeline, FPGA bring-up. Full history and staged plan: [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).
