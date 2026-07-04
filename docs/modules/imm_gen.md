# Immediate Generator (`rtl/core/imm_gen.sv`)

## Purpose

Most RISC-V instructions carry a constant ("immediate") inside the 32-bit
instruction word: the `500` in `addi x1, x2, 500`, the offset in `lw x5,
16(x2)`, the branch distance in `beq x1, x2, loop`. This module extracts that
constant and sign-extends it to 32 bits so the ALU can use it.

## Why are the bits scattered?

The ISA designers kept rs1, rs2, and rd in the **same bit positions in every
format**, so the register file can start reading before the instruction type
is even known. The price: immediate bits land wherever space is left, in a
different scatter per format. The imm_gen is the module that pays that price —
it's pure wiring (multiplexed bit rearrangement), zero arithmetic.

## The five formats

| Format | Used by       | Width  | Range                    |
|--------|---------------|--------|--------------------------|
| I      | ADDI, LW, JALR| 12 bit | −2048 … +2047            |
| S      | SW            | 12 bit | −2048 … +2047            |
| B      | BEQ, BNE      | 13 bit | −4096 … +4094, always even |
| U      | LUI, AUIPC    | 20 bit | upper 20 bits, low 12 = 0 |
| J      | JAL           | 21 bit | ±1 MB, always even       |

Key ideas worth remembering:

- **Sign bit is always instr[31]**, in every format. One wire drives all the
  sign extension, keeping the mux cheap.
- **B and J immediates have bit 0 hard-wired to 0.** Jump targets are always
  even (instructions are 2/4-byte aligned), so the ISA doesn't waste an
  encoding bit on it — that's why a 12-bit B field covers ±4 KB, not ±2 KB.
- **S-type exists so stores don't need rd.** A store has two source registers
  and no destination, so its immediate is split around the rs2 field.

## Interface

| Signal      | Dir | Width | Description                              |
|-------------|-----|-------|-------------------------------------------|
| `instr_i`   | in  | 32    | Full instruction word                     |
| `imm_sel_i` | in  | 3     | Format select (`IMM_I/S/B/U/J` defines)   |
| `imm_o`     | out | 32    | Sign-extended immediate                   |

`imm_sel_i` is driven by the control unit, which knows the format from the
opcode. Purely combinational.

## Verification (`tb/unit/tb_imm_gen.sv`)

1015 self-checks: hand-assembled real instructions (e.g. `addi x1,x0,-1` =
`0xFFF00093`), range boundary values per format, and a 200-iteration random
encode→decode round-trip per format, where the testbench places a random
immediate into instruction bits with independent encoder functions and checks
the DUT recovers it. Status: **PASS**.

## Future improvements

None expected — this module is complete for RV32I. Compressed instructions
(C extension) would need their own decoder, not changes here.
