# CPU Core (`rtl/core/core_top.sv`)

## Purpose

This is the integration module: it wires the five verified leaf modules
(pc, control, imm_gen, regfile, alu) plus three pieces of glue logic into a
working single-cycle RV32I CPU. "Single-cycle" means each instruction is
fetched, decoded, executed, and retired within one clock period — the PC
advances every cycle.

## What happens in one cycle

```
        pc_q ──> imem ──> instr
                            │
          ┌─────────┬───────┴─────────┐
          ▼         ▼                 ▼
       control   imm_gen        regfile (read rs1, rs2)
          │         │                 │
          └───> operand muxes <───────┘
                     │
                     ▼
                    ALU ───────> dmem address / branch decision
                     │
                write-back mux ──> regfile (written at the clock edge)
                     │
               next-PC logic ────> pc (loaded at the clock edge)
```

Everything between the two clock edges is combinational; state changes (PC,
registers, memory) happen only at the edge. That's why it "just works":
there are no hazards to manage yet.

## The glue logic (the only new logic in this file)

**1. Branch decision — one XOR handles BEQ and BNE.**
The ALU computes `rs1 - rs2`; its zero flag says "equal".
`taken = branch & (alu_zero ^ funct3[0])` — funct3[0] is 0 for BEQ
(take when equal) and 1 for BNE (take when not equal).

**2. Two jump-target sources.**
Branches and JAL are *PC-relative*: `target = PC + imm` (a dedicated adder,
because the ALU is busy comparing). JALR is *register-based*: `target =
rs1 + imm`, which is exactly what the ALU computed this cycle — reused, with
bit 0 cleared as the spec requires.

**3. Write-back mux (3 sources).**
Most instructions write the ALU result; LW writes the loaded data; JAL/JALR
write PC+4 (the return address — that's the "link" in jump-and-link).

## Interfaces

Instruction side: `imem_addr_o` (= PC) out, `imem_rdata_i` (instruction) in —
combinational, as a single-cycle core requires.

Data side: `dmem_addr_o/wdata_o/we_o/re_o/rdata_i` — a deliberately simple
read/write port. In Stage C this gets wrapped by an AXI4-Lite master; keeping
the core bus-agnostic is standard practice (lowRISC Ibex does the same).

`illegal_o` flags an unsupported instruction — used by the testbench as a
run-time invariant, later by trap handling.

## Verification (`tb/integration/tb_core.sv`)

Five real RV32I programs (source in `sw/`, assembled by `sw/asm.py`), run on
the core with a behavioral 4 KB data RAM at 0x2000_0000. After each program
the testbench inspects registers and memory (white-box), and an every-cycle
watchdog fails the test if the core ever decodes an illegal instruction:

| Program | Exercises | Checked results |
|---------|-----------|-----------------|
| prog1_arith | ADDI, ADD | x3 = 15 |
| prog2_loop  | backward BNE loop | sum 1..5 = 15, counter = 5 |
| prog3_mem   | LUI, SW, LW round-trip | x3=42, x4=43, mem contents |
| prog4_func  | JAL call, JALR return | double(7)=14, ra correct |
| prog5_logic | shifts, SLT/SLTU, LUI, XOR | 7 register values |

19 checks, status: **PASS**. Run it: `sim/icarus/run.sh core` or in ModelSim
`do run_core.do` from `sim/modelsim`.

## Future improvements

- Stage C: AXI4-Lite wrapper on the data port, GPIO + UART
- Later phases: pipelining (adds hazard/forwarding logic), traps/CSRs,
  byte/halfword loads and stores
