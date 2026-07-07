// ============================================================================
// tb_core.sv — integration testbench: run real RV32I programs on the core
// ----------------------------------------------------------------------------
// Setup:
//   core_top + imem (program from sw/build/*.hex) + a behavioral data RAM
//   at 0x2000_0000 (see docs/memory_map.md).
//
// Method (white-box, per the README's verification strategy):
//   Each program runs for a fixed number of cycles — every program ends in a
//   "jal x0, done" self-loop, so extra cycles are harmless. Afterwards the
//   testbench peeks INSIDE the core (hierarchical references to the register
//   file and the data RAM) and compares against expected results computed
//   by hand from the assembly source.
//
//   The testbench also watches illegal_o on every cycle: if the core ever
//   decodes garbage (e.g. PC runs away into empty memory), the test fails
//   immediately — a cheap, powerful invariant.
//
// Hex file location:
//   Pass +hexdir=<path> on the simulator command line to point at sw/build.
//   Defaults to "../../sw/build" which works when running from sim/modelsim.
// ============================================================================

`timescale 1ns / 1ps

module tb_core;

  logic        clk, rst_n;
  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]  dmem_wstrb;
  logic        dmem_we, dmem_re, illegal;

  int errors = 0;
  int checks = 0;
  string hexdir = "../../sw/build";

  // ---- device under test -----------------------------------------------------
  core_top dut (
      .clk_i       (clk),
      .rst_ni      (rst_n),
      .stall_i     (1'b0),        // TB memories answer in the same cycle

      .imem_addr_o (imem_addr),
      .imem_rdata_i(imem_rdata),
      .dmem_addr_o (dmem_addr),
      .dmem_wdata_o(dmem_wdata),
      .dmem_wstrb_o(dmem_wstrb),
      .dmem_we_o   (dmem_we),
      .dmem_re_o   (dmem_re),
      .dmem_rdata_i(dmem_rdata),
      .illegal_o   (illegal)
  );

  // ---- instruction memory (reloaded per program) --------------------------------
  imem #(
      .DEPTH_WORDS(1024)
  ) u_imem (
      .addr_i (imem_addr),
      .rdata_o(imem_rdata)
  );

  // ---- behavioral data RAM: 4 KB at 0x2000_0000 ----------------------------------
  logic [31:0] dram[0:1023];

  assign dmem_rdata = (dmem_re && dmem_addr[31:28] == 4'h2)
                      ? dram[dmem_addr[11:2]] : 32'd0;

  always_ff @(posedge clk) begin
    if (dmem_we && dmem_addr[31:28] == 4'h2) begin
      if (dmem_wstrb[0]) dram[dmem_addr[11:2]][7:0]   <= dmem_wdata[7:0];
      if (dmem_wstrb[1]) dram[dmem_addr[11:2]][15:8]  <= dmem_wdata[15:8];
      if (dmem_wstrb[2]) dram[dmem_addr[11:2]][23:16] <= dmem_wdata[23:16];
      if (dmem_wstrb[3]) dram[dmem_addr[11:2]][31:24] <= dmem_wdata[31:24];
    end
  end

  // ---- clock and illegal-instruction watchdog --------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst_n && illegal) begin
      errors++;
      $display("FAIL: illegal instruction decoded at PC=0x%08h (instr=0x%08h)",
               imem_addr, imem_rdata);
    end
  end

  // ---- helpers -------------------------------------------------------------------------
  task automatic check_reg(input [4:0] r, input [31:0] expected, input string what);
    logic [31:0] got;
    got = (r == 0) ? 32'd0 : dut.u_regfile.regs[r];
    checks++;
    if (got !== expected) begin
      errors++;
      $display("FAIL: %s | x%0d expected 0x%08h, got 0x%08h", what, r, expected, got);
    end
  endtask

  task automatic check_dram(input int word_idx, input [31:0] expected, input string what);
    checks++;
    if (dram[word_idx] !== expected) begin
      errors++;
      $display("FAIL: %s | dram[%0d] expected 0x%08h, got 0x%08h",
               what, word_idx, dram[word_idx], expected);
    end
  endtask

  // load a program, reset the core, run it for `cycles` clocks
  task automatic run_prog(input string name, input int cycles);
    string path;
    path = {hexdir, "/", name, ".hex"};
    $display("---- running %s ----", name);
    for (int i = 0; i < 1024; i++) begin
      u_imem.mem[i] = 32'h0000006F;  // fill: jal x0, 0 (safe self-loop)
      dram[i]       = 32'd0;
    end
    $readmemh(path, u_imem.mem);
    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n = 1;
    repeat (cycles) @(posedge clk);
    #1;
  endtask

  // ---- test sequence ------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_core.vcd");
    $dumpvars(0, tb_core);
    if ($value$plusargs("hexdir=%s", hexdir)) ;  // optional override
    rst_n = 0;

    // -- program 1: a=5, b=10, c=a+b ------------------------------------------
    run_prog("prog1_arith", 20);
    check_reg(1, 5,  "prog1: a");
    check_reg(2, 10, "prog1: b");
    check_reg(3, 15, "prog1: c = a+b");

    // -- program 2: loop, sum 1..5 ----------------------------------------------
    run_prog("prog2_loop", 40);
    check_reg(5, 15, "prog2: sum 1..5");
    check_reg(6, 5,  "prog2: loop counter");

    // -- program 3: store/load round-trip ------------------------------------------
    run_prog("prog3_mem", 20);
    check_reg(3, 42, "prog3: loaded value");
    check_reg(4, 43, "prog3: loaded+1");
    check_dram(0, 42, "prog3: mem[0]");
    check_dram(1, 43, "prog3: mem[4]");

    // -- program 4: function call and return ------------------------------------------
    run_prog("prog4_func", 20);
    check_reg(10, 14, "prog4: double(7) result in a0");
    check_reg(6,  14, "prog4: copied after return (t1)");
    check_reg(1,  8,  "prog4: ra = return address");

    // -- program 5: shifts, comparisons, upper immediates ---------------------------------
    run_prog("prog5_logic", 20);
    check_reg(1, 32'hFFFF_F000, "prog5: lui");
    check_reg(2, 32'hFFFF_FFFF, "prog5: srai sign-fill");
    check_reg(3, 32'h000F_FFFF, "prog5: srli zero-fill");
    check_reg(4, 32'h00FF_FFF0, "prog5: slli");
    check_reg(5, 1, "prog5: slt signed");
    check_reg(6, 0, "prog5: sltu unsigned");
    check_reg(7, 32'hFFF0_0000, "prog5: xor");

	// ---Prog 6 Mul 10*7 test
	run_prog("prog6_mul", 60);
	check_reg(3, 70, "prog6: 10*7");
	//check_reg(3, 71, ...)

    // -- program 7: byte/halfword loads and stores (Stage E) ------------------------------
    run_prog("prog7_bytes", 40);
    check_reg(3,  32'hFFFF_FFEF, "prog7: lb sign-extends");
    check_reg(4,  32'h0000_00EF, "prog7: lbu zero-extends");
    check_reg(5,  32'hFFFF_FFDE, "prog7: lb from offset 3");
    check_reg(6,  32'hFFFF_BEEF, "prog7: lh sign-extends");
    check_reg(7,  32'h0000_DEAD, "prog7: lhu from offset 2");
    check_reg(9,  32'h0000_4241, "prog7: two sb then lhu");
    check_reg(11, 32'h0000_5678, "prog7: sh writes only its half");
    check_dram(1, 32'h0000_4241, "prog7: mem word 1 byte lanes");
    check_dram(2, 32'h0000_5678, "prog7: mem word 2 half lane");

    // -- program 8: signed vs unsigned branches (Stage E) ----------------------------------
    run_prog("prog8_branches", 40);
    check_reg(10, 6, "prog8: all six branch decisions correct");

    // ---- summary --------------------------------------------------------------------------------
    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
