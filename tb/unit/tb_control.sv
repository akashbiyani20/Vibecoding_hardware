// ============================================================================
// tb_control.sv — self-checking testbench for the control unit
// ----------------------------------------------------------------------------
// Strategy:
//   Assemble real instruction words with encoder functions, then check the
//   full control-signal bundle for every supported instruction, plus the
//   illegal flag for unsupported/garbage encodings.
//
//   The expect_ctrl task checks ALL outputs on every call — a decoder bug
//   that flips an unrelated signal (e.g. ADDI accidentally asserting
//   mem_write) is caught even in tests "about" something else.
// ============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module tb_control;

  logic [31:0] instr;
  logic [2:0]  imm_sel;
  logic [3:0]  alu_op;
  logic [1:0]  op_a_sel, wb_sel;
  logic        op_b_sel, reg_write, mem_read, mem_write;
  logic        branch, jump, jump_reg, illegal;

  int errors = 0;
  int checks = 0;

  control dut (
      .instr_i    (instr),
      .imm_sel_o  (imm_sel),
      .alu_op_o   (alu_op),
      .op_a_sel_o (op_a_sel),
      .op_b_sel_o (op_b_sel),
      .reg_write_o(reg_write),
      .wb_sel_o   (wb_sel),
      .mem_read_o (mem_read),
      .mem_write_o(mem_write),
      .branch_o   (branch),
      .jump_o     (jump),
      .jump_reg_o (jump_reg),
      .illegal_o  (illegal)
  );

  // ---- instruction encoders --------------------------------------------------
  function automatic [31:0] enc_r(input [6:0] f7, input [2:0] f3);
    enc_r = {f7, 5'd2, 5'd1, f3, 5'd3, `OPC_OP};          // op x3, x1, x2
  endfunction
  function automatic [31:0] enc_iop(input [2:0] f3, input [11:0] imm12);
    enc_iop = {imm12, 5'd1, f3, 5'd3, `OPC_OPIMM};        // opi x3, x1, imm
  endfunction

  // compare every output against expected values
  task automatic expect_ctrl(
      input [31:0] word,
      input [2:0]  e_imm_sel,
      input [3:0]  e_alu_op,
      input [1:0]  e_op_a,
      input        e_op_b,
      input        e_reg_write,
      input [1:0]  e_wb_sel,
      input        e_mem_read,
      input        e_mem_write,
      input        e_branch,
      input        e_jump,
      input        e_jump_reg,
      input        e_illegal,
      input string what);
    instr = word;
    #1;
    checks++;
    if ({imm_sel, alu_op, op_a_sel, op_b_sel, reg_write, wb_sel,
         mem_read, mem_write, branch, jump, jump_reg, illegal}
        !==
        {e_imm_sel, e_alu_op, e_op_a, e_op_b, e_reg_write, e_wb_sel,
         e_mem_read, e_mem_write, e_branch, e_jump, e_jump_reg, e_illegal})
    begin
      errors++;
      $display("FAIL: %s (instr=0x%08h)", what, word);
      $display("      got: imm=%b alu=%b opa=%b opb=%b rw=%b wb=%b mr=%b mw=%b br=%b j=%b jr=%b ill=%b",
               imm_sel, alu_op, op_a_sel, op_b_sel, reg_write, wb_sel,
               mem_read, mem_write, branch, jump, jump_reg, illegal);
      $display("      exp: imm=%b alu=%b opa=%b opb=%b rw=%b wb=%b mr=%b mw=%b br=%b j=%b jr=%b ill=%b",
               e_imm_sel, e_alu_op, e_op_a, e_op_b, e_reg_write, e_wb_sel,
               e_mem_read, e_mem_write, e_branch, e_jump, e_jump_reg, e_illegal);
    end
  endtask

  initial begin
    $dumpfile("tb_control.vcd");
    $dumpvars(0, tb_control);

    // ---------------- R-type: all ten ALU ops -----------------------------
    //          instruction                imm     alu_op     opA       opB      rw  wb      mr mw br j  jr il
    expect_ctrl(enc_r(7'h00, 3'b000), `IMM_I, `ALU_ADD,  `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "ADD");
    expect_ctrl(enc_r(7'h20, 3'b000), `IMM_I, `ALU_SUB,  `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "SUB");
    expect_ctrl(enc_r(7'h00, 3'b001), `IMM_I, `ALU_SLL,  `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "SLL");
    expect_ctrl(enc_r(7'h00, 3'b010), `IMM_I, `ALU_SLT,  `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "SLT");
    expect_ctrl(enc_r(7'h00, 3'b011), `IMM_I, `ALU_SLTU, `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "SLTU");
    expect_ctrl(enc_r(7'h00, 3'b100), `IMM_I, `ALU_XOR,  `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "XOR");
    expect_ctrl(enc_r(7'h00, 3'b101), `IMM_I, `ALU_SRL,  `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "SRL");
    expect_ctrl(enc_r(7'h20, 3'b101), `IMM_I, `ALU_SRA,  `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "SRA");
    expect_ctrl(enc_r(7'h00, 3'b110), `IMM_I, `ALU_OR,   `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "OR");
    expect_ctrl(enc_r(7'h00, 3'b111), `IMM_I, `ALU_AND,  `OPA_RS1, `OPB_RS2, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "AND");

    // ---------------- I-type ALU ------------------------------------------
    expect_ctrl(enc_iop(3'b000, 12'd5),    `IMM_I, `ALU_ADD,  `OPA_RS1, `OPB_IMM, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "ADDI");
    expect_ctrl(enc_iop(3'b100, 12'hFFF),  `IMM_I, `ALU_XOR,  `OPA_RS1, `OPB_IMM, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "XORI");
    // negative immediate sets bit30 — must NOT turn ADDI into SUB
    expect_ctrl(enc_iop(3'b000, -12'd1),   `IMM_I, `ALU_ADD,  `OPA_RS1, `OPB_IMM, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "ADDI -1 stays ADD");
    // ...but for shifts bit30 IS the opcode bit
    expect_ctrl(enc_iop(3'b001, 12'h004),  `IMM_I, `ALU_SLL,  `OPA_RS1, `OPB_IMM, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "SLLI");
    expect_ctrl(enc_iop(3'b101, 12'h004),  `IMM_I, `ALU_SRL,  `OPA_RS1, `OPB_IMM, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "SRLI");
    expect_ctrl(enc_iop(3'b101, 12'h404),  `IMM_I, `ALU_SRA,  `OPA_RS1, `OPB_IMM, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "SRAI");

    // ---------------- memory ------------------------------------------------
    // lw x5, 16(x2) / sw x5, -4(x2)
    expect_ctrl(32'h01012283, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_IMM, 1, `WB_MEM, 1, 0, 0, 0, 0, 0, "LW");
    expect_ctrl(32'hFE512E23, `IMM_S, `ALU_ADD, `OPA_RS1, `OPB_IMM, 0, `WB_ALU, 0, 1, 0, 0, 0, 0, "SW");

    // ---------------- branches ----------------------------------------------
    // beq x1, x2, +8 / bne x1, x2, -4
    expect_ctrl(32'h00208463, `IMM_B, `ALU_SUB, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 1, 0, 0, 0, "BEQ");
    expect_ctrl(32'hFE209EE3, `IMM_B, `ALU_SUB, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 1, 0, 0, 0, "BNE");

    // ---------------- jumps --------------------------------------------------
    // jal x1, +2048 / jalr x0, 0(x1) = 0x00008067 (this is `ret`)
    expect_ctrl(32'h001000EF, `IMM_J, `ALU_ADD, `OPA_RS1, `OPB_RS2, 1, `WB_PC4, 0, 0, 0, 1, 0, 0, "JAL");
    expect_ctrl(32'h00008067, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_IMM, 1, `WB_PC4, 0, 0, 0, 1, 1, 0, "JALR (ret)");

    // ---------------- upper immediates ----------------------------------------
    // lui x1, 0x12345 / auipc x1, 0x12345
    expect_ctrl(32'h123450B7, `IMM_U, `ALU_ADD, `OPA_ZERO, `OPB_IMM, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "LUI");
    expect_ctrl(32'h12345097, `IMM_U, `ALU_ADD, `OPA_PC,   `OPB_IMM, 1, `WB_ALU, 0, 0, 0, 0, 0, 0, "AUIPC");

    // ---------------- illegal / unsupported ------------------------------------
    // garbage opcode: all signals must stay in the safe default state
    expect_ctrl(32'hFFFF_FFFF, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 0, 0, 0, 1, "garbage word");
    expect_ctrl(32'h0000_0000, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 0, 0, 0, 1, "all-zero word");
    // lw with funct3=011 — no such load
    expect_ctrl({12'd0, 5'd2, 3'b011, 5'd5, `OPC_LOAD},  `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 0, 0, 0, 1, "load f3=011 illegal");
    // store with funct3=011 — no such store
    expect_ctrl({7'd0, 5'd5, 5'd2, 3'b011, 5'd0, `OPC_STORE}, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 0, 0, 0, 1, "store f3=011 illegal");
    // branch with funct3=010 — gap in the encoding space
    expect_ctrl({7'd0, 5'd2, 5'd1, 3'b010, 5'b01000, `OPC_BRANCH}, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 0, 0, 0, 1, "branch f3=010 illegal");

    // ---------------- Stage E: full load/store/branch sets ----------------------
    // lb x5, 0(x2) / lbu / lh / lhu — all legal now, same controls as LW
    expect_ctrl({12'd0, 5'd2, 3'b000, 5'd5, `OPC_LOAD}, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_IMM, 1, `WB_MEM, 1, 0, 0, 0, 0, 0, "LB");
    expect_ctrl({12'd0, 5'd2, 3'b100, 5'd5, `OPC_LOAD}, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_IMM, 1, `WB_MEM, 1, 0, 0, 0, 0, 0, "LBU");
    expect_ctrl({12'd0, 5'd2, 3'b001, 5'd5, `OPC_LOAD}, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_IMM, 1, `WB_MEM, 1, 0, 0, 0, 0, 0, "LH");
    expect_ctrl({12'd0, 5'd2, 3'b101, 5'd5, `OPC_LOAD}, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_IMM, 1, `WB_MEM, 1, 0, 0, 0, 0, 0, "LHU");
    // sb / sh
    expect_ctrl({7'd0, 5'd5, 5'd2, 3'b000, 5'd0, `OPC_STORE}, `IMM_S, `ALU_ADD, `OPA_RS1, `OPB_IMM, 0, `WB_ALU, 0, 1, 0, 0, 0, 0, "SB");
    expect_ctrl({7'd0, 5'd5, 5'd2, 3'b001, 5'd0, `OPC_STORE}, `IMM_S, `ALU_ADD, `OPA_RS1, `OPB_IMM, 0, `WB_ALU, 0, 1, 0, 0, 0, 0, "SH");
    // blt/bge use SLT; bltu/bgeu use SLTU
    expect_ctrl({7'd0, 5'd2, 5'd1, 3'b100, 5'b01000, `OPC_BRANCH}, `IMM_B, `ALU_SLT,  `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 1, 0, 0, 0, "BLT");
    expect_ctrl({7'd0, 5'd2, 5'd1, 3'b101, 5'b01000, `OPC_BRANCH}, `IMM_B, `ALU_SLT,  `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 1, 0, 0, 0, "BGE");
    expect_ctrl({7'd0, 5'd2, 5'd1, 3'b110, 5'b01000, `OPC_BRANCH}, `IMM_B, `ALU_SLTU, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 1, 0, 0, 0, "BLTU");
    expect_ctrl({7'd0, 5'd2, 5'd1, 3'b111, 5'b01000, `OPC_BRANCH}, `IMM_B, `ALU_SLTU, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 1, 0, 0, 0, "BGEU");
    // fence = NOP: no state-changing signal
    expect_ctrl(32'h0FF0000F, `IMM_I, `ALU_ADD, `OPA_RS1, `OPB_RS2, 0, `WB_ALU, 0, 0, 0, 0, 0, 0, "FENCE as NOP");

    // safety check: an illegal instruction must never write state
    checks++;
    if (illegal && (reg_write || mem_write || mem_read || branch || jump)) begin
      errors++;
      $display("FAIL: illegal instruction asserts a state-changing signal");
    end

    // ---- Summary ------------------------------------------------------------
    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
