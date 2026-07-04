// ============================================================================
// alu.sv — Arithmetic Logic Unit (RV32I)
// ----------------------------------------------------------------------------
// Purpose:
//   Pure combinational block that computes one result from two 32-bit
//   operands. Supports the ten RV32I ALU operations:
//     ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
//
// Operation encoding: op_i = {funct7[5], funct3}
//   This is the instruction's own encoding, so the decoder mostly passes
//   instruction bits straight through — minimal decode logic, and each op
//   code below can be read directly out of the RISC-V spec.
//
// Notes on the interesting cases:
//   - Shifts use only b_i[4:0]: shifting a 32-bit value by >31 is meaningless,
//     and the RV32I spec says exactly this (the shamt field is 5 bits).
//   - SRA needs $signed() so Verilog performs an arithmetic shift
//     (sign bit replicated) instead of filling with zeros.
//   - SLT compares as signed, SLTU as unsigned; both produce 0 or 1.
//   - zero_o flags result == 0. The branch unit uses it: BEQ does
//     SUB and branches if zero_o is set.
//
// Timing:
//   Fully combinational — no clock, no state. Result is valid after
//   propagation delay within the same cycle.
// ============================================================================

`include "riscv_defines.svh"

module alu (
    input  logic [31:0] a_i,       // operand A (rs1)
    input  logic [31:0] b_i,       // operand B (rs2 or immediate)
    input  logic [3:0]  op_i,      // {funct7[5], funct3}
    output logic [31:0] result_o,
    output logic        zero_o     // result_o == 0 (for branches)
);

  always_comb begin
    unique case (op_i)
      `ALU_ADD:  result_o = a_i + b_i;
      `ALU_SUB:  result_o = a_i - b_i;
      `ALU_AND:  result_o = a_i & b_i;
      `ALU_OR:   result_o = a_i | b_i;
      `ALU_XOR:  result_o = a_i ^ b_i;
      `ALU_SLL:  result_o = a_i << b_i[4:0];
      `ALU_SRL:  result_o = a_i >> b_i[4:0];
      `ALU_SRA:  result_o = $signed(a_i) >>> b_i[4:0];
      `ALU_SLT:  result_o = ($signed(a_i) < $signed(b_i)) ? 32'd1 : 32'd0;
      `ALU_SLTU: result_o = (a_i < b_i) ? 32'd1 : 32'd0;
      default:   result_o = 32'd0;  // unused encodings: defined output, no latch
    endcase
  end

  assign zero_o = (result_o == 32'd0);

endmodule
