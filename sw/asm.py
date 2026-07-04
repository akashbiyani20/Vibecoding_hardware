#!/usr/bin/env python3
"""
asm.py - minimal two-pass RV32I assembler for this project.

Supports exactly the instructions the core supports:
  R:  add sub sll slt sltu xor srl sra or and
  I:  addi slti sltiu xori ori andi slli srli srai
  M:  lw sw
  B:  beq bne
  J:  jal jalr
  U:  lui auipc
Plus labels, comments (# or //), and the 'nop' pseudo-instruction.

Register names: x0..x31 or ABI names (zero, ra, sp, a0-a7, t0-t6, s0-s11).

Usage:
  python3 asm.py prog.s -o prog.hex        # verilog $readmemh format
  python3 asm.py prog.s --list             # print listing with encodings
"""
import re
import sys

# ---- register names ---------------------------------------------------------
REGS = {f"x{i}": i for i in range(32)}
ABI = ("zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 "
       "s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6").split()
REGS.update({name: i for i, name in enumerate(ABI)})
REGS["fp"] = 8

# ---- instruction tables: name -> (funct7, funct3) or funct3 ------------------
R_OPS = {"add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
         "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
         "or": (0x00, 6), "and": (0x00, 7)}
I_OPS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFT_OPS = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
BRANCH_OPS = {"beq": 0, "bne": 1}


def reg(name):
    name = name.strip().lower()
    if name not in REGS:
        sys.exit(f"error: unknown register '{name}'")
    return REGS[name]


def imm_value(tok, labels=None, pc=None):
    """Parse an immediate: decimal, hex, or a label (-> pc-relative offset)."""
    tok = tok.strip()
    if labels is not None and tok in labels:
        return labels[tok] - pc
    try:
        return int(tok, 0)
    except ValueError:
        sys.exit(f"error: bad immediate or unknown label '{tok}'")


# ---- encoders (bit layouts straight from the RV32I spec) ----------------------
def enc_r(f7, rs2, rs1, f3, rd, opc=0x33):
    return f7 << 25 | rs2 << 20 | rs1 << 15 | f3 << 12 | rd << 7 | opc


def enc_i(imm, rs1, f3, rd, opc):
    if not -2048 <= imm <= 2047:
        sys.exit(f"error: I-immediate {imm} out of range [-2048, 2047]")
    return (imm & 0xFFF) << 20 | rs1 << 15 | f3 << 12 | rd << 7 | opc


def enc_s(imm, rs2, rs1, f3):
    if not -2048 <= imm <= 2047:
        sys.exit(f"error: S-immediate {imm} out of range")
    return ((imm >> 5) & 0x7F) << 25 | rs2 << 20 | rs1 << 15 | f3 << 12 \
        | (imm & 0x1F) << 7 | 0x23


def enc_b(imm, rs2, rs1, f3):
    if not -4096 <= imm <= 4094 or imm % 2:
        sys.exit(f"error: branch offset {imm} invalid")
    return ((imm >> 12) & 1) << 31 | ((imm >> 5) & 0x3F) << 25 | rs2 << 20 \
        | rs1 << 15 | f3 << 12 | ((imm >> 1) & 0xF) << 8 \
        | ((imm >> 11) & 1) << 7 | 0x63


def enc_u(imm20, rd, opc):
    if not 0 <= imm20 <= 0xFFFFF:
        sys.exit(f"error: U-immediate {imm20:#x} out of range (20 bits)")
    return (imm20 & 0xFFFFF) << 12 | rd << 7 | opc


def enc_j(imm, rd):
    if not -(1 << 20) <= imm <= (1 << 20) - 2 or imm % 2:
        sys.exit(f"error: jump offset {imm} invalid")
    return ((imm >> 20) & 1) << 31 | ((imm >> 1) & 0x3FF) << 21 \
        | ((imm >> 11) & 1) << 20 | ((imm >> 12) & 0xFF) << 12 | rd << 7 | 0x6F


# ---- assembler ------------------------------------------------------------------
MEM_RE = re.compile(r"^\s*(-?\w+)\s*\(\s*(\w+)\s*\)\s*$")  # "imm(rs1)"


def parse_lines(text):
    """Strip comments, split labels, return list of (label|None, stmt|None)."""
    out = []
    for raw in text.splitlines():
        line = re.split(r"#|//", raw)[0].strip()
        while line:
            m = re.match(r"^(\w+)\s*:\s*(.*)$", line)
            if m:
                out.append((m.group(1), None))
                line = m.group(2).strip()
            else:
                out.append((None, line))
                line = ""
    return out


def assemble(text):
    items = parse_lines(text)

    # pass 1: label addresses
    labels, addr = {}, 0
    for label, stmt in items:
        if label is not None:
            if label in labels:
                sys.exit(f"error: duplicate label '{label}'")
            labels[label] = addr
        elif stmt:
            addr += 4

    # pass 2: encode
    words, listing, pc = [], [], 0
    for label, stmt in items:
        if stmt is None or not stmt:
            continue
        parts = stmt.replace(",", " ").split()
        op, args = parts[0].lower(), parts[1:]

        if op == "nop":
            word = enc_i(0, 0, 0, 0, 0x13)                      # addi x0,x0,0
        elif op in R_OPS:
            f7, f3 = R_OPS[op]
            word = enc_r(f7, reg(args[2]), reg(args[1]), f3, reg(args[0]))
        elif op in I_OPS:
            word = enc_i(imm_value(args[2]), reg(args[1]), I_OPS[op],
                         reg(args[0]), 0x13)
        elif op in SHIFT_OPS:
            f7, f3 = SHIFT_OPS[op]
            shamt = imm_value(args[2])
            if not 0 <= shamt <= 31:
                sys.exit(f"error: shift amount {shamt} out of range")
            word = enc_i((f7 << 5) | shamt, reg(args[1]), f3, reg(args[0]), 0x13)
        elif op == "lw":
            m = MEM_RE.match(" ".join(args[1:]))
            word = enc_i(imm_value(m.group(1)), reg(m.group(2)), 2,
                         reg(args[0]), 0x03)
        elif op == "sw":
            m = MEM_RE.match(" ".join(args[1:]))
            word = enc_s(imm_value(m.group(1)), reg(args[0]), reg(m.group(2)), 2)
        elif op in BRANCH_OPS:
            off = imm_value(args[2], labels, pc)
            word = enc_b(off, reg(args[1]), reg(args[0]), BRANCH_OPS[op])
        elif op == "jal":
            off = imm_value(args[1], labels, pc)
            word = enc_j(off, reg(args[0]))
        elif op == "jalr":
            m = MEM_RE.match(" ".join(args[1:]))
            word = enc_i(imm_value(m.group(1)), reg(m.group(2)), 0,
                         reg(args[0]), 0x67)
        elif op == "lui":
            word = enc_u(imm_value(args[1]), reg(args[0]), 0x37)
        elif op == "auipc":
            word = enc_u(imm_value(args[1]), reg(args[0]), 0x17)
        else:
            sys.exit(f"error: unsupported instruction '{op}'")

        words.append(word)
        listing.append(f"{pc:08x}:  {word:08x}   {stmt}")
        pc += 4

    return words, listing


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    src = args[0]
    out = None
    if "-o" in args:
        out = args[args.index("-o") + 1]
    with open(src) as f:
        words, listing = assemble(f.read())
    if "--list" in args or out is None:
        print("\n".join(listing))
    if out:
        with open(out, "w") as f:
            f.write("\n".join(f"{w:08x}" for w in words) + "\n")
        print(f"{src}: {len(words)} instructions -> {out}")


if __name__ == "__main__":
    main()
