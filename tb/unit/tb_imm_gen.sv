// ============================================================================
// tb_imm_gen.sv — self-checking testbench for the immediate generator
// ----------------------------------------------------------------------------
// Strategy:
//   1. Directed tests with hand-assembled real instructions (values checked
//      against the RISC-V spec / an assembler)
//   2. Random tests: build instruction words from random immediates using
//      ENCODER functions (imm -> instruction bits), then check the DUT
//      DECODES them back to the original immediate. Encode->decode round-trip
//      with independent code paths catches scrambled-bit bugs.
// ============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module tb_imm_gen;

  logic [31:0] instr, imm;
  logic [2:0]  sel;

  int errors = 0;
  int checks = 0;

  imm_gen dut (
      .instr_i  (instr),
      .imm_sel_i(sel),
      .imm_o    (imm)
  );

  task automatic check(input [31:0] word, input [2:0] s,
                       input [31:0] expected, input string what);
    instr = word;
    sel   = s;
    #1;
    checks++;
    if (imm !== expected) begin
      errors++;
      $display("FAIL: %s | instr=0x%08h expected 0x%08h got 0x%08h",
               what, word, expected, imm);
    end
  endtask

  // ---- encoders: place an immediate into instruction bit positions ---------
  function automatic [31:0] enc_i(input [31:0] v);
    enc_i = {v[11:0], 20'b0};
  endfunction
  function automatic [31:0] enc_s(input [31:0] v);
    enc_s = {v[11:5], 13'b0, v[4:0], 7'b0};
  endfunction
  function automatic [31:0] enc_b(input [31:0] v);
    enc_b = {v[12], v[10:5], 13'b0, v[4:1], v[11], 7'b0};
  endfunction
  function automatic [31:0] enc_u(input [31:0] v);
    enc_u = {v[31:12], 12'b0};
  endfunction
  function automatic [31:0] enc_j(input [31:0] v);
    enc_j = {v[20], v[10:1], v[11], v[19:12], 12'b0};
  endfunction

  // sign-extend helpers for expected values
  function automatic [31:0] sext12(input [31:0] v);
    sext12 = {{20{v[11]}}, v[11:0]};
  endfunction

  logic [31:0] r;

  initial begin
    $dumpfile("tb_imm_gen.vcd");
    $dumpvars(0, tb_imm_gen);

    // ---- directed: real assembled instructions ---------------------------
    // addi x1, x0, -1        = 0xFFF00093 -> imm = -1
    check(32'hFFF00093, `IMM_I, 32'hFFFF_FFFF, "addi x1,x0,-1");
    // addi x2, x1, 2047      = 0x7FF08113 -> imm = 2047 (I max positive)
    check(32'h7FF08113, `IMM_I, 32'd2047, "addi max +2047");
    // lw x5, 16(x2)          = 0x01012283 -> imm = 16
    check(32'h01012283, `IMM_I, 32'd16, "lw offset 16");
    // sw x5, -4(x2)          = 0xFE512E23 -> imm = -4
    check(32'hFE512E23, `IMM_S, 32'hFFFF_FFFC, "sw offset -4");
    // beq x1, x2, +8         = 0x00208463 -> imm = 8
    check(32'h00208463, `IMM_B, 32'd8, "beq +8");
    // bne x1, x2, -4         = 0xFE209EE3 -> imm = -4
    check(32'hFE209EE3, `IMM_B, 32'hFFFF_FFFC, "bne -4");
    // lui x1, 0x12345        = 0x123450B7 -> imm = 0x12345000
    check(32'h123450B7, `IMM_U, 32'h1234_5000, "lui 0x12345");
    // jal x1, +2048          = 0x001000EF -> imm = 2048
    check(32'h001000EF, `IMM_J, 32'd2048, "jal +2048");
    // jal x0, -8             = 0xFF9FF06F -> imm = -8 (backward loop jump)
    check(32'hFF9FF06F, `IMM_J, 32'hFFFF_FFF8, "jal -8");

    // ---- boundary values ---------------------------------------------------
    check(enc_i(-2048), `IMM_I, -2048, "I min -2048");
    check(enc_s(2047),  `IMM_S, 2047, "S max +2047");
    check(enc_b(-4096), `IMM_B, -4096, "B min -4096");
    check(enc_b(4094),  `IMM_B, 4094, "B max +4094");
    check(enc_j(-32'd1048576), `IMM_J, -32'd1048576, "J min -1M");
    check(enc_u(32'hFFFF_F000), `IMM_U, 32'hFFFF_F000, "U all ones");

    // ---- random round-trip: 200 per format ---------------------------------
    for (int n = 0; n < 200; n++) begin
      r = $random;
      check(enc_i(r), `IMM_I, sext12(r), "random I");
      check(enc_s(r), `IMM_S, sext12(r), "random S");
      check(enc_b(r), `IMM_B, {{19{r[12]}}, r[12:1], 1'b0}, "random B");
      check(enc_u(r), `IMM_U, {r[31:12], 12'b0}, "random U");
      check(enc_j(r), `IMM_J, {{11{r[20]}}, r[20:1], 1'b0}, "random J");
    end

    // ---- Summary -------------------------------------------------------------
    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
