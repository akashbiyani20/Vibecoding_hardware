// ============================================================================
// imm_gen.sv — Immediate Generator
// ----------------------------------------------------------------------------
// Purpose:
//   RISC-V instructions carry constants ("immediates") inside the instruction
//   word, but each instruction format scatters the bits differently — a
//   deliberate trade-off in the ISA so that register fields (rs1/rs2/rd)
//   always sit in the same place, which simplifies the register file path.
//   This module un-scatters those bits and sign-extends to 32 bits.
//
// The five formats:
//   I-type (ADDI, LW, JALR) : imm[11:0]  = instr[31:20]
//   S-type (SW)             : imm[11:0]  = {instr[31:25], instr[11:7]}
//   B-type (BEQ, BNE)       : imm[12:1]  = {instr[31], instr[7],
//                                           instr[30:25], instr[11:8]}, imm[0]=0
//   U-type (LUI, AUIPC)     : imm[31:12] = instr[31:12], low 12 bits = 0
//   J-type (JAL)            : imm[20:1]  = {instr[31], instr[19:12],
//                                           instr[20], instr[30:21]}, imm[0]=0
//
// Two things to notice:
//   - Sign extension always replicates instr[31]. Every format puts the sign
//     bit there, so negative offsets/constants work uniformly.
//   - B and J immediates have imm[0] forced to 0: branch/jump targets are
//     always even (instructions are 2- or 4-byte aligned), so the ISA uses
//     that free bit to double the reachable range.
//
// Timing: purely combinational.
// ============================================================================

`include "riscv_defines.svh"

module imm_gen (
    input  logic [31:0] instr_i,
    input  logic [2:0]  imm_sel_i,
    output logic [31:0] imm_o
);

  always_comb begin
    case (imm_sel_i)
      `IMM_I: imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
      `IMM_S: imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
      `IMM_B: imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                       instr_i[30:25], instr_i[11:8], 1'b0};
      `IMM_U: imm_o = {instr_i[31:12], 12'b0};
      `IMM_J: imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                       instr_i[20], instr_i[30:21], 1'b0};
      default: imm_o = 32'd0;
    endcase
  end

endmodule
