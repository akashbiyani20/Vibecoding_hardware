// ============================================================================
// tb_pc.sv — self-checking testbench for the Program Counter
// ----------------------------------------------------------------------------
// Tests:
//   1. Reset drives pc_o to RESET_PC
//   2. Sequential increment (pc_next = pc + 4) works cycle by cycle
//   3. Branch/jump target loading works
//   4. en_i = 0 holds the current value (stall behavior)
//   5. Mid-run reset returns to RESET_PC
// Result: prints PASS/FAIL summary, non-zero error count = FAIL.
// ============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module tb_pc;

  logic        clk;
  logic        rst_n;
  logic        en;
  logic [31:0] pc_next;
  logic [31:0] pc_out;

  int errors = 0;
  int checks = 0;

  // Device under test
  pc dut (
      .clk_i    (clk),
      .rst_ni   (rst_n),
      .en_i     (en),
      .pc_next_i(pc_next),
      .pc_o     (pc_out)
  );

  // 100 MHz clock
  initial clk = 0;
  always #5 clk = ~clk;

  // Check helper: compare pc_out against expected value
  task automatic check(input [31:0] expected, input string what);
    checks++;
    if (pc_out !== expected) begin
      errors++;
      $display("FAIL: %s | expected 0x%08h, got 0x%08h (t=%0t)",
               what, expected, pc_out, $time);
    end
  endtask

  initial begin
    $dumpfile("tb_pc.vcd");
    $dumpvars(0, tb_pc);

    // ---- Test 1: reset value -------------------------------------------
    en      = 1;
    pc_next = 32'hDEAD_BEEF;  // must be ignored during reset
    rst_n   = 0;
    repeat (2) @(posedge clk);
    #1 check(`RESET_PC, "reset value");
    rst_n = 1;

    // ---- Test 2: sequential increments ---------------------------------
    for (int i = 0; i < 5; i++) begin
      pc_next = pc_out + 4;
      @(posedge clk);
      #1 check(32'h4 * (i + 1), "sequential PC+4");
    end

    // ---- Test 3: branch target load ------------------------------------
    pc_next = 32'h0000_0100;
    @(posedge clk);
    #1 check(32'h0000_0100, "branch target");

    // ---- Test 4: stall (en=0 holds value) -------------------------------
    en      = 0;
    pc_next = 32'hFFFF_FFF0;
    repeat (3) @(posedge clk);
    #1 check(32'h0000_0100, "hold while en=0");
    en = 1;

    // ---- Test 5: mid-run reset ------------------------------------------
    @(posedge clk);
    rst_n = 0;
    #1 check(`RESET_PC, "async mid-run reset");
    rst_n = 1;

    // ---- Summary ---------------------------------------------------------
    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
