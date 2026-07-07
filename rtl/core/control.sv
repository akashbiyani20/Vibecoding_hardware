// ============================================================================
// control.sv — Control Unit / Instruction Decoder
// ----------------------------------------------------------------------------
// Purpose:
//   Looks at an instruction word and answers, combinationally, every "which
//   way?" question in the datapath:
//     - which immediate format?              -> imm_sel_o
//     - what should the ALU compute?         -> alu_op_o
//     - what feeds ALU operand A?            -> op_a_sel_o (rs1 / PC / zero)
//     - what feeds ALU operand B?            -> op_b_sel_o (rs2 / immediate)
//     - does a register get written? which data? -> reg_write_o, wb_sel_o
//     - is memory read or written?           -> mem_read_o, mem_write_o
//     - is this a branch or a jump?          -> branch_o, jump_o, jump_reg_o
//
// Supported instructions (Phase 1):
//   R-type : ADD SUB SLL SLT SLTU XOR SRL SRA OR AND
//   I-type : ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI
//   Loads  : LB LH LW LBU LHU      Stores: SB SH SW
//   Branch : BEQ BNE BLT BGE BLTU BGEU
//   Jumps  : JAL JALR      Upper : LUI AUIPC
//   FENCE  : executes as NOP (single core, no caches — nothing to order)
//
//   JALR, LUI, AUIPC are beyond the README minimum but nearly free in decode
//   and practically required: JALR is how every function returns (`ret`),
//   LUI is how firmware forms peripheral addresses like 0x1000_0000,
//   AUIPC enables position-independent addressing. The I-type ALU ops beyond
//   ADDI cost zero extra logic (same decode path).
//
// How branches resolve (in the core):
//   cond  = funct3[2] ? alu_result[0] : alu_zero   (SLT/SLTU vs SUB-zero)
//   taken = branch_o & (cond ^ funct3[0])          (funct3[0] inverts)
//
// How jump targets form (in the core, later):
//   JAL  : target = PC + J-immediate      (dedicated adder, like branches)
//   JALR : target = rs1 + I-immediate     (computed by the ALU)
//   Both write PC+4 to rd (wb_sel = WB_PC4).
//
// illegal_o:
//   Set for anything not listed above (ECALL/EBREAK/CSR stay illegal until
//   trap support exists). The core can trap or halt on it; in simulation
//   it catches firmware/toolchain mistakes early.
//
// Timing: purely combinational.
// ============================================================================

`include "riscv_defines.svh"

module control (
    input  logic [31:0] instr_i,
    // immediate format
    output logic [2:0]  imm_sel_o,
    // ALU control
    output logic [3:0]  alu_op_o,
    output logic [1:0]  op_a_sel_o,   // OPA_RS1 / OPA_PC / OPA_ZERO
    output logic        op_b_sel_o,   // OPB_RS2 / OPB_IMM
    // register writeback
    output logic        reg_write_o,
    output logic [1:0]  wb_sel_o,     // WB_ALU / WB_MEM / WB_PC4
    // data memory
    output logic        mem_read_o,
    output logic        mem_write_o,
    // control flow
    output logic        branch_o,     // conditional: BEQ/BNE
    output logic        jump_o,       // unconditional: JAL/JALR
    output logic        jump_reg_o,   // 1 = JALR (target from ALU, not PC+imm)
    // error detect
    output logic        illegal_o
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic       bit30;    // instr[30] = funct7[5], the ADD/SUB & SRL/SRA selector

  assign opcode = instr_i[6:0];
  assign funct3 = instr_i[14:12];
  assign bit30  = instr_i[30];

  always_comb begin
    // ---- safe defaults: an unknown instruction changes no state ------------
    imm_sel_o   = `IMM_I;
    alu_op_o    = `ALU_ADD;
    op_a_sel_o  = `OPA_RS1;
    op_b_sel_o  = `OPB_RS2;
    reg_write_o = 1'b0;
    wb_sel_o    = `WB_ALU;
    mem_read_o  = 1'b0;
    mem_write_o = 1'b0;
    branch_o    = 1'b0;
    jump_o      = 1'b0;
    jump_reg_o  = 1'b0;
    illegal_o   = 1'b0;

    case (opcode)

      // ---- register-register ALU: op encoding passes straight through ------
      `OPC_OP: begin
        reg_write_o = 1'b1;
        alu_op_o    = {bit30, funct3};
      end

      // ---- ALU with immediate ------------------------------------------------
      `OPC_OPIMM: begin
        reg_write_o = 1'b1;
        op_b_sel_o  = `OPB_IMM;
        imm_sel_o   = `IMM_I;
        // bit30 is a real opcode bit only for shifts (SLLI/SRLI/SRAI);
        // for the others it belongs to the immediate value -> force 0
        if (funct3 == 3'b001 || funct3 == 3'b101)
          alu_op_o = {bit30, funct3};
        else
          alu_op_o = {1'b0, funct3};
      end

      // ---- loads: address = rs1 + imm, writeback from memory (via LSU) --------
      `OPC_LOAD: begin
        // legal funct3: LB=000 LH=001 LW=010 LBU=100 LHU=101
        if (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010 ||
            funct3 == 3'b100 || funct3 == 3'b101) begin
          reg_write_o = 1'b1;
          op_b_sel_o  = `OPB_IMM;
          imm_sel_o   = `IMM_I;
          mem_read_o  = 1'b1;
          wb_sel_o    = `WB_MEM;
        end else begin
          illegal_o = 1'b1;
        end
      end

      // ---- stores: address = rs1 + imm, no writeback (LSU sets byte lanes) ----
      `OPC_STORE: begin
        if (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010) begin
          op_b_sel_o  = `OPB_IMM;         // SB=000 SH=001 SW=010
          imm_sel_o   = `IMM_S;
          mem_write_o = 1'b1;
        end else begin
          illegal_o = 1'b1;
        end
      end

      // ---- branches: the ALU computes the comparison, the core decides --------
      // BEQ/BNE (00x): SUB, look at the zero flag
      // BLT/BGE (10x): SLT, look at result bit 0 (1 = less-than)
      // BLTU/BGEU(11x): SLTU, same but unsigned
      // funct3[0] inverts the sense (BNE/BGE/BGEU take when condition FALSE)
      `OPC_BRANCH: begin
        if (funct3 != 3'b010 && funct3 != 3'b011) begin
          branch_o  = 1'b1;
          imm_sel_o = `IMM_B;
          unique case (funct3[2:1])
            2'b00:   alu_op_o = `ALU_SUB;
            2'b10:   alu_op_o = `ALU_SLT;
            default: alu_op_o = `ALU_SLTU;
          endcase
        end else begin
          illegal_o = 1'b1;               // funct3 010/011 don't exist
        end
      end

      // ---- FENCE: memory ordering hint — a NOP on a single in-order core ------
      `OPC_FENCE: ;                       // safe defaults already = NOP

      // ---- JAL: rd = PC+4, target = PC + J-imm --------------------------------
      `OPC_JAL: begin
        jump_o      = 1'b1;
        reg_write_o = 1'b1;
        wb_sel_o    = `WB_PC4;
        imm_sel_o   = `IMM_J;
      end

      // ---- JALR: rd = PC+4, target = rs1 + I-imm (via ALU) ---------------------
      `OPC_JALR: begin
        if (funct3 == 3'b000) begin
          jump_o      = 1'b1;
          jump_reg_o  = 1'b1;
          reg_write_o = 1'b1;
          wb_sel_o    = `WB_PC4;
          op_b_sel_o  = `OPB_IMM;
          imm_sel_o   = `IMM_I;           // ALU computes rs1 + imm = target
        end else begin
          illegal_o = 1'b1;
        end
      end

      // ---- LUI: rd = imm (ALU computes 0 + imm) ---------------------------------
      `OPC_LUI: begin
        reg_write_o = 1'b1;
        op_a_sel_o  = `OPA_ZERO;
        op_b_sel_o  = `OPB_IMM;
        imm_sel_o   = `IMM_U;
      end

      // ---- AUIPC: rd = PC + imm ---------------------------------------------------
      `OPC_AUIPC: begin
        reg_write_o = 1'b1;
        op_a_sel_o  = `OPA_PC;
        op_b_sel_o  = `OPB_IMM;
        imm_sel_o   = `IMM_U;
      end

      default: illegal_o = 1'b1;
    endcase
  end

endmodule
