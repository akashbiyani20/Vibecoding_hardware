// ============================================================================
// riscv_defines.svh — shared constants for the RV32I core
// ----------------------------------------------------------------------------
// ALU operation encoding: {funct7[5], funct3}
// This is exactly how RV32I encodes register-register ALU ops in the
// instruction itself, so the decoder can mostly pass these bits through.
// ============================================================================

`ifndef RISCV_DEFINES_SVH
`define RISCV_DEFINES_SVH

// ---- ALU operations: {instr[30], funct3} -----------------------------------
`define ALU_ADD  4'b0000  // add
`define ALU_SUB  4'b1000  // subtract        (instr[30] set)
`define ALU_SLL  4'b0001  // shift left logical
`define ALU_SLT  4'b0010  // set if less than (signed)
`define ALU_SLTU 4'b0011  // set if less than (unsigned)
`define ALU_XOR  4'b0100  // exclusive or
`define ALU_SRL  4'b0101  // shift right logical
`define ALU_SRA  4'b1101  // shift right arithmetic (instr[30] set)
`define ALU_OR   4'b0110  // or
`define ALU_AND  4'b0111  // and

// ---- Reset / boot address ---------------------------------------------------
`define RESET_PC 32'h0000_0000

`endif // RISCV_DEFINES_SVH
