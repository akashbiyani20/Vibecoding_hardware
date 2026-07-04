# ALU (`rtl/core/alu.sv`)

## Purpose

The ALU is the CPU's calculator: it takes two 32-bit operands and produces one
result, fully combinationally (no clock, no memory). The ten RV32I operations:
ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU.

Operand B is chosen upstream by a mux: register rs2 for R-type instructions,
the immediate for I-type. The ALU itself doesn't know or care which.

## Design decision: op encoding = `{funct7[5], funct3}`

RV32I already encodes the ALU operation inside the instruction: `funct3`
selects the operation family and instruction bit 30 (`funct7[5]`) distinguishes
ADD/SUB and SRL/SRA. By using those 4 bits directly as our `op_i`, the decoder
needs almost no logic to drive the ALU. Compare the encodings in
`riscv_defines.svh` against the RISC-V spec table — they match by construction.

## Interface

| Signal     | Dir | Width | Description                                |
|------------|-----|-------|--------------------------------------------|
| `a_i`      | in  | 32    | Operand A (always rs1)                     |
| `b_i`      | in  | 32    | Operand B (rs2 or immediate, muxed above)  |
| `op_i`     | in  | 4     | Operation select, `{funct7[5], funct3}`    |
| `result_o` | out | 32    | Result                                     |
| `zero_o`   | out | 1     | 1 when result is exactly 0                 |

## The subtle cases (worth understanding)

- **Shift amount is `b_i[4:0]` only.** The spec defines a 5-bit shamt; a shift
  by "32" therefore acts as a shift by 0. The testbench checks this exact case.
- **SRL vs SRA.** Logical right shift fills with zeros; arithmetic right shift
  replicates the sign bit, which keeps negative numbers negative
  (`-8 >>> 1 = -4`). In Verilog this requires `$signed(a) >>> shamt` — without
  `$signed`, `>>>` silently behaves like `>>`. Classic bug, explicitly tested.
- **SLT vs SLTU.** Same bit patterns, different interpretation:
  `0xFFFFFFFF < 1` is true signed (it's −1) but false unsigned (it's 4 billion).
- **`zero_o` is how branches work.** BEQ computes `rs1 - rs2` and branches when
  `zero_o` is set. BNE branches when it's clear. No separate comparator needed
  for equality branches.
- **Overflow wraps silently.** RISC-V has no arithmetic exception on overflow;
  `0x7FFFFFFF + 1 = 0x80000000` is the defined behavior.
- **`default` arm returns 0** so unused op encodings still produce a defined
  output and the combinational block never infers a latch.

## Verification (`tb/unit/tb_alu.sv`)

2042 self-checks: directed corner cases per operation (overflow wrap, sign
boundaries, shift-by-0/31, shamt masking, zero-flag cases) plus 1000 random
operand/op pairs against an independent reference model. Status: **PASS**.

## Future improvements

- Branch comparisons BLT/BGE/BLTU/BGEU (Phase 1 needs only BEQ/BNE) can reuse
  SLT/SLTU results when those branches are added
- M-extension (MUL/DIV) would be a separate unit, not part of this ALU
