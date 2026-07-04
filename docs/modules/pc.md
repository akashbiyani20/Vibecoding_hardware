# Program Counter (`rtl/core/pc.sv`)

## Purpose

The Program Counter (PC) is a single 32-bit register that holds the address of
the instruction currently being fetched. It is the "bookmark" of the CPU:
everything else in the fetch stage is derived from this one value.

## Design decision: keep the PC dumb

The PC does **not** decide what the next address is. It just stores whatever
`pc_next_i` presents. The decision "PC+4, branch target, or jump target?" is a
mux that lives in the core's next-PC logic. This separation means:

- the PC is trivially verifiable (it's just a register with enable + reset)
- branch/jump logic can evolve without touching this module
- adding stalls later (pipelining) only requires driving `en_i`

## Interface

| Signal      | Dir | Width | Description                                    |
|-------------|-----|-------|------------------------------------------------|
| `clk_i`     | in  | 1     | Clock, rising-edge active                      |
| `rst_ni`    | in  | 1     | Async reset, active low → PC = 0x0000_0000     |
| `en_i`      | in  | 1     | 1 = load `pc_next_i`, 0 = hold (stall). Tie 1. |
| `pc_next_i` | in  | 32    | Address to load on the next clock edge         |
| `pc_o`      | out | 32    | Current instruction address                    |

## Timing behavior

```
clk      _/‾\_/‾\_/‾\_/‾\_
pc_next   X  A   B   C
pc_o     RST  A   B   C     (each value appears one edge after pc_next)
```

`pc_o` is purely registered — no combinational path through the module. Reset
is asynchronous (takes effect immediately) and release is sampled on the next
edge, the most common industry convention for FPGA/ASIC.

## Why active-low async reset?

`rst_ni` (the `_n` = active low, `_i` = input) follows the lowRISC/industry
naming style. Async assert / sync release works on both FPGA and ASIC flows.

## Verification (`tb/unit/tb_pc.sv`)

9 self-checks: reset value, five sequential PC+4 steps, branch target load,
hold under `en_i=0`, and async mid-run reset. Status: **PASS**.

## Future improvements

- `en_i` will be driven by hazard/stall logic when the core is pipelined
- Reset vector could become a parameter if boot address ever moves
