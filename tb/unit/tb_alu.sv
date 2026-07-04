// ============================================================================
// tb_alu.sv — self-checking testbench for the ALU
// ----------------------------------------------------------------------------
// Strategy:
//   1. Directed tests: known corner cases per operation (overflow wrap,
//      sign boundaries, shift by 0/31, shift amount masking, zero flag)
//   2. Random tests: 1000 random operand/op pairs checked against an
//      independent reference model
// ============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module tb_alu;

  logic [31:0] a, b, result;
  logic [3:0]  op;
  logic        zero;

  int errors = 0;
  int checks = 0;

  alu dut (
      .a_i     (a),
      .b_i     (b),
      .op_i    (op),
      .result_o(result),
      .zero_o  (zero)
  );

  // independent reference model
  function automatic [31:0] ref_model(input [31:0] x, input [31:0] y,
                                      input [3:0] f);
    case (f)
      `ALU_ADD:  ref_model = x + y;
      `ALU_SUB:  ref_model = x - y;
      `ALU_AND:  ref_model = x & y;
      `ALU_OR:   ref_model = x | y;
      `ALU_XOR:  ref_model = x ^ y;
      `ALU_SLL:  ref_model = x << y[4:0];
      `ALU_SRL:  ref_model = x >> y[4:0];
      `ALU_SRA:  ref_model = $signed(x) >>> y[4:0];
      `ALU_SLT:  ref_model = ($signed(x) < $signed(y)) ? 1 : 0;
      `ALU_SLTU: ref_model = (x < y) ? 1 : 0;
      default:   ref_model = 0;
    endcase
  endfunction

  task automatic test(input [31:0] x, input [31:0] y, input [3:0] f,
                      input [31:0] expected, input string what);
    a = x; b = y; op = f;
    #1;
    checks++;
    if (result !== expected) begin
      errors++;
      $display("FAIL: %s | a=0x%08h b=0x%08h op=%b | expected 0x%08h got 0x%08h",
               what, x, y, f, expected, result);
    end
    checks++;
    if (zero !== (expected == 0)) begin
      errors++;
      $display("FAIL: %s | zero flag wrong (result 0x%08h, zero=%b)",
               what, result, zero);
    end
  endtask

  logic [3:0] ops[0:9];
  logic [3:0] rop;
  logic [31:0] ra, rb;

  initial begin
    $dumpfile("tb_alu.vcd");
    $dumpvars(0, tb_alu);

    ops[0] = `ALU_ADD;  ops[1] = `ALU_SUB;  ops[2] = `ALU_AND;
    ops[3] = `ALU_OR;   ops[4] = `ALU_XOR;  ops[5] = `ALU_SLL;
    ops[6] = `ALU_SRL;  ops[7] = `ALU_SRA;  ops[8] = `ALU_SLT;
    ops[9] = `ALU_SLTU;

    // ---- ADD: basic, wraparound overflow ---------------------------------
    test(5, 10, `ALU_ADD, 15, "ADD 5+10");
    test(32'hFFFF_FFFF, 1, `ALU_ADD, 0, "ADD wrap to zero (zero flag)");
    test(32'h7FFF_FFFF, 1, `ALU_ADD, 32'h8000_0000, "ADD signed overflow wraps");

    // ---- SUB: basic, negative result, equality (branch use) ---------------
    test(10, 5, `ALU_SUB, 5, "SUB 10-5");
    test(5, 10, `ALU_SUB, -5, "SUB negative result");
    test(32'hCAFE_CAFE, 32'hCAFE_CAFE, `ALU_SUB, 0, "SUB equal -> zero flag (BEQ)");

    // ---- logic ops ---------------------------------------------------------
    test(32'hF0F0_F0F0, 32'h0FF0_0FF0, `ALU_AND, 32'h00F0_00F0, "AND");
    test(32'hF0F0_F0F0, 32'h0FF0_0FF0, `ALU_OR,  32'hFFF0_FFF0, "OR");
    test(32'hF0F0_F0F0, 32'h0FF0_0FF0, `ALU_XOR, 32'hFF00_FF00, "XOR");
    test(32'hAAAA_5555, 32'hAAAA_5555, `ALU_XOR, 0, "XOR self -> zero");

    // ---- shifts: 0, max, and shamt masking (bit 5+ ignored) ---------------
    test(32'h0000_0001, 0,  `ALU_SLL, 32'h0000_0001, "SLL by 0");
    test(32'h0000_0001, 31, `ALU_SLL, 32'h8000_0000, "SLL by 31");
    test(32'h0000_0001, 32'h0000_0020, `ALU_SLL, 32'h0000_0001,
         "SLL shamt masked to 5 bits (32 -> 0)");
    test(32'h8000_0000, 31, `ALU_SRL, 1, "SRL by 31 zero-fills");
    test(32'h8000_0000, 31, `ALU_SRA, 32'hFFFF_FFFF, "SRA by 31 sign-fills");
    test(32'h7FFF_FFFF, 4,  `ALU_SRA, 32'h07FF_FFFF, "SRA positive zero-fills");

    // ---- comparisons: sign boundary cases ----------------------------------
    test(-1, 1, `ALU_SLT, 1, "SLT -1 < 1 (signed)");
    test(-1, 1, `ALU_SLTU, 0, "SLTU 0xFFFFFFFF > 1 (unsigned)");
    test(1, -1, `ALU_SLT, 0, "SLT 1 < -1 false");
    test(32'h8000_0000, 32'h7FFF_FFFF, `ALU_SLT, 1, "SLT INT_MIN < INT_MAX");
    test(5, 5, `ALU_SLT, 0, "SLT equal -> 0 (zero flag)");

    // ---- random soak vs reference model ------------------------------------
    for (int n = 0; n < 1000; n++) begin
      ra  = $random;
      rb  = $random;
      rop = ops[{$random} % 10];
      test(ra, rb, rop, ref_model(ra, rb, rop), "random");
    end

    // ---- Summary -------------------------------------------------------------
    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
