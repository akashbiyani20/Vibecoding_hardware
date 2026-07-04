# Register File (`rtl/core/regfile.sv`)

## Purpose

The register file is the CPU's fast working storage: 32 registers (x0–x31),
32 bits each, defined by the RV32I spec. Almost every instruction reads one or
two registers and writes one, so this module has **two combinational read
ports** (rs1, rs2) and **one synchronous write port** (rd).

## The x0 rule

RISC-V hard-wires x0 to zero. This is not a convention — hardware must enforce
it, because compiled code depends on it (`mv`, `nop`, zero-comparisons are all
encoded using x0). Implementation here:

- storage array is `regs[1:31]` — x0 physically doesn't exist
- writes with `waddr == 0` are discarded
- reads with `raddr == 0` return a constant 0 via a mux

## Interface

| Signal      | Dir | Width | Description                          |
|-------------|-----|-------|--------------------------------------|
| `clk_i`     | in  | 1     | Clock; writes on rising edge         |
| `we_i`      | in  | 1     | Write enable                         |
| `waddr_i`   | in  | 5     | Destination register rd              |
| `wdata_i`   | in  | 32    | Write data                           |
| `raddr_a_i` | in  | 5     | rs1 index                            |
| `rdata_a_o` | out | 32    | rs1 data (combinational)             |
| `raddr_b_i` | in  | 5     | rs2 index                            |
| `rdata_b_o` | out | 32    | rs2 data (combinational)             |

## Timing behavior

- **Reads are combinational**: address in → data out in the same cycle. The
  single-cycle core needs this (decode and execute happen within one cycle).
- **Writes are synchronous**: data is stored at the rising edge.
- **Read-during-write** to the same register returns the **old** value. The
  single-cycle core never reads and writes the same register within one
  instruction's readable window, so this is safe. When we pipeline the core
  later, this exact property is what creates the classic "register file
  hazard" — solved then with forwarding or a write-through read port.

## Why no reset?

The RISC-V spec leaves register contents undefined at reset (except x0).
Resetting 31×32 flip-flops costs area/routing and prevents FPGA tools from
mapping the file into block RAM or LUT-RAM. Software (the C runtime or boot
code) initializes registers it cares about. Industry cores (e.g. lowRISC
Ibex's default config) do the same.

## Verification (`tb/unit/tb_regfile.sv`)

438 self-checks: x0 write/read behavior on both ports, write/readback sweep of
all 31 registers, dual-port independence, `we=0` write blocking, old-value
read-during-write semantics, and a 200-iteration random soak test against a
software reference model. Status: **PASS**.

## Future improvements

- Pipelined core: add forwarding or internal write-through
- Optional second write port is never needed for RV32I — keep it simple
