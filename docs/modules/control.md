# Control Unit (`rtl/core/control.sv`)

## Purpose

The control unit is the CPU's "traffic director". Datapath modules (ALU,
register file, imm_gen, memories) are machines that can do many things; the
control unit reads the instruction and decides, combinationally, what each
of them does *this* cycle: which immediate format, what ALU operation, what
feeds each ALU operand, whether a register is written and from where, whether
memory is accessed, and whether control flow changes.

## Supported instructions

| Group  | Instructions                                        |
|--------|------------------------------------------------------|
| R-type | ADD SUB SLL SLT SLTU XOR SRL SRA OR AND              |
| I-type | ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI          |
| Memory | LW, SW (word-only in Phase 1)                        |
| Branch | BEQ, BNE                                             |
| Jump   | JAL, JALR                                            |
| Upper  | LUI, AUIPC                                           |

Three additions beyond the README minimum, each with a reason: **JALR** is how
every function returns (`ret` = `jalr x0, 0(x1)`) — no JALR, no function calls.
**LUI** is how firmware builds 32-bit constants like the GPIO base address
0x1000_0000 (12-bit immediates can't reach it). **AUIPC** costs one mux input.
The extra I-type ALU ops share ADDI's decode path exactly — zero extra logic.

## Output signals

| Signal        | Meaning                                              |
|---------------|-------------------------------------------------------|
| `imm_sel_o`   | Immediate format for imm_gen (I/S/B/U/J)              |
| `alu_op_o`    | ALU operation (`{funct7[5], funct3}` encoding)        |
| `op_a_sel_o`  | ALU operand A: rs1 (normal), PC (AUIPC), 0 (LUI)      |
| `op_b_sel_o`  | ALU operand B: rs2 (R-type/branch) or immediate       |
| `reg_write_o` | Write rd this cycle                                   |
| `wb_sel_o`    | rd source: ALU result, memory load, or PC+4 (links)   |
| `mem_read_o`  | LW                                                    |
| `mem_write_o` | SW                                                    |
| `branch_o`    | Conditional branch (BEQ/BNE)                          |
| `jump_o`      | Unconditional jump (JAL/JALR)                         |
| `jump_reg_o`  | Target comes from ALU (JALR) instead of PC+imm (JAL)  |
| `illegal_o`   | Unsupported instruction detected                      |

## Design decisions worth understanding

- **Safe defaults.** Every output has a default assigned before the `case`.
  Two payoffs: an unhandled instruction changes no architectural state
  (no register write, no memory write, no branch), and `always_comb` can
  never infer a latch.
- **ALU op mostly passes through.** For R-type, `alu_op = {instr[30], funct3}`
  — direct wiring. One subtlety: for I-type ALU ops, instr[30] is part of the
  *immediate value* (e.g. `addi x1, x0, -1` has it set), so it must be forced
  to 0 — except for shifts (SLLI/SRLI/SRAI), where the spec makes it a real
  opcode bit again. The testbench checks exactly this trap.
- **Branch decision is split.** Control only says "this is a branch"; the
  actual take/don't-take decision lives in the core:
  `taken = branch & (alu_zero ^ funct3[0])` — BEQ (funct3=000) takes on zero,
  BNE (funct3=001) takes on not-zero. One XOR gate handles both.
- **Illegal detection now, trap later.** LB/LH/SB/SH, BLT-family, and unknown
  opcodes assert `illegal_o` and nothing else. In simulation this catches
  toolchain mistakes immediately; on hardware it becomes a trap when we add
  exception support.

## Verification (`tb/unit/tb_control.sv`)

30 bundle-checks — each one compares **all 13 outputs at once**, so a decode
bug that flips an unrelated signal is caught even in a test "about" something
else. Covers all 23 supported instructions (mostly hand-assembled real
encodings), the ADDI-with-negative-immediate trap, `ret`, and five illegal
encodings including the all-zeros and all-ones words. Status: **PASS**.

## Future improvements

- BLT/BGE/BLTU/BGEU: add funct3 cases + a comparator-based branch decision
- LB/LH/SB/SH: byte-enable logic in the memory stage, then legalize here
- Exceptions: route `illegal_o` into a trap unit (mtvec/mepc CSRs)
