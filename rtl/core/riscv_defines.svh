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

// ---- RV32I opcodes (instr[6:0]) ---------------------------------------------
`define OPC_LUI    7'b0110111  // load upper immediate
`define OPC_AUIPC  7'b0010111  // add upper immediate to PC
`define OPC_JAL    7'b1101111  // jump and link
`define OPC_JALR   7'b1100111  // jump and link register (function return)
`define OPC_BRANCH 7'b1100011  // BEQ / BNE / ...
`define OPC_LOAD   7'b0000011  // LW
`define OPC_STORE  7'b0100011  // SW
`define OPC_OPIMM  7'b0010011  // ALU with immediate (ADDI, ...)
`define OPC_OP     7'b0110011  // ALU register-register (ADD, ...)
`define OPC_FENCE  7'b0001111  // memory fence (NOP on this core)

// ---- Immediate format select (imm_gen) ----------------------------------------
`define IMM_I 3'b000  // I-type: ADDI, LW, JALR
`define IMM_S 3'b001  // S-type: SW
`define IMM_B 3'b010  // B-type: branches
`define IMM_U 3'b011  // U-type: LUI, AUIPC
`define IMM_J 3'b100  // J-type: JAL

// ---- ALU operand A select ------------------------------------------------------
`define OPA_RS1  2'b00  // normal ALU ops
`define OPA_PC   2'b01  // AUIPC
`define OPA_ZERO 2'b10  // LUI (0 + imm)

// ---- ALU operand B select ------------------------------------------------------
`define OPB_RS2 1'b0
`define OPB_IMM 1'b1

// ---- Write-back source select ---------------------------------------------------
`define WB_ALU 2'b00  // ALU result
`define WB_MEM 2'b01  // load data
`define WB_PC4 2'b10  // PC+4 (JAL/JALR link address)

// ---- Reset / boot address ---------------------------------------------------
`define RESET_PC 32'h0000_0000

`endif // RISCV_DEFINES_SVH
