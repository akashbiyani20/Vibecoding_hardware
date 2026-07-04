// ============================================================================
// tb_regfile.sv — self-checking testbench for the register file
// ----------------------------------------------------------------------------
// Tests:
//   1. x0 always reads zero, even after a write attempt to x0
//   2. Write then read back, all 31 real registers
//   3. Dual read ports return independent, correct data
//   4. we_i = 0 blocks writes
//   5. Read-during-write returns OLD value (documented behavior)
//   6. Random write/read soak test against a software model
// ============================================================================

`timescale 1ns / 1ps

module tb_regfile;

  logic        clk;
  logic        we;
  logic [4:0]  waddr, raddr_a, raddr_b;
  logic [31:0] wdata, rdata_a, rdata_b;

  int errors = 0;
  int checks = 0;

  // software reference model
  logic [31:0] model[0:31];

  regfile dut (
      .clk_i    (clk),
      .we_i     (we),
      .waddr_i  (waddr),
      .wdata_i  (wdata),
      .raddr_a_i(raddr_a),
      .rdata_a_o(rdata_a),
      .raddr_b_i(raddr_b),
      .rdata_b_o(rdata_b)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic check(input [31:0] got, input [31:0] expected, input string what);
    checks++;
    if (got !== expected) begin
      errors++;
      $display("FAIL: %s | expected 0x%08h, got 0x%08h (t=%0t)",
               what, expected, got, $time);
    end
  endtask

  // write one register through the DUT and mirror it in the model
  task automatic write_reg(input [4:0] a, input [31:0] d);
    @(negedge clk);
    we    = 1;
    waddr = a;
    wdata = d;
    @(posedge clk);
    #1 we = 0;
    if (a != 0) model[a] = d;
  endtask

  initial begin
    $dumpfile("tb_regfile.vcd");
    $dumpvars(0, tb_regfile);
    we = 0; waddr = 0; wdata = 0; raddr_a = 0; raddr_b = 0;
    for (int i = 0; i < 32; i++) model[i] = 0;

    // ---- Test 1: x0 behavior --------------------------------------------
    write_reg(5'd0, 32'hFFFF_FFFF);   // attempt write to x0
    raddr_a = 0; raddr_b = 0;
    #1;
    check(rdata_a, 32'd0, "x0 reads zero on port A");
    check(rdata_b, 32'd0, "x0 reads zero on port B");

    // ---- Test 2: write/readback all registers ---------------------------
    for (int i = 1; i < 32; i++) write_reg(i[4:0], 32'hA000_0000 + i);
    for (int i = 1; i < 32; i++) begin
      raddr_a = i[4:0];
      #1 check(rdata_a, 32'hA000_0000 + i, $sformatf("readback x%0d", i));
    end

    // ---- Test 3: independent dual read ----------------------------------
    raddr_a = 5'd3; raddr_b = 5'd17;
    #1;
    check(rdata_a, 32'hA000_0003, "dual read port A (x3)");
    check(rdata_b, 32'hA000_0011, "dual read port B (x17)");

    // ---- Test 4: we=0 blocks writes --------------------------------------
    @(negedge clk);
    we = 0; waddr = 5'd5; wdata = 32'h1234_5678;
    @(posedge clk);
    #1 raddr_a = 5'd5;
    #1 check(rdata_a, 32'hA000_0005, "we=0 blocks write to x5");

    // ---- Test 5: read-during-write returns old value ---------------------
    @(negedge clk);
    we = 1; waddr = 5'd9; wdata = 32'hCAFE_F00D; raddr_a = 5'd9;
    #1 check(rdata_a, 32'hA000_0009, "read-during-write sees OLD value");
    @(posedge clk);
    #1 we = 0;
    model[9] = 32'hCAFE_F00D;
    check(rdata_a, 32'hCAFE_F00D, "new value visible after edge");

    // ---- Test 6: random soak vs model -------------------------------------
    for (int n = 0; n < 200; n++) begin
      write_reg($random, $random);
      raddr_a = $random;
      raddr_b = $random;
      #1;
      check(rdata_a, (raddr_a == 0) ? 0 : model[raddr_a], "random port A");
      check(rdata_b, (raddr_b == 0) ? 0 : model[raddr_b], "random port B");
    end

    // ---- Summary -----------------------------------------------------------
    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
