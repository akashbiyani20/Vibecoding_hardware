// ============================================================================
// tb_axi_timer.sv — timer unit test (driven through the real bridge)
// ----------------------------------------------------------------------------
// Tests:
//   1. Counter runs: two reads spaced N cycles apart differ by ~N
//   2. Write resets the counter
//   3. hi-shadow coherence: reading LO latches HI (the rollover race fix)
// ============================================================================

`timescale 1ns / 1ps

module tb_axi_timer;

  logic clk, rst_n;
  logic [31:0] addr, wdata, rdata;
  logic we, re, stall;

  logic [31:0] awaddr, wd, araddr, rd;
  logic [3:0]  wstrb;
  logic [1:0]  bresp, rresp;
  logic awvalid, awready, wvalid, wready, bvalid, bready;
  logic arvalid, arready, rvalid, rready;

  int errors = 0;
  int checks = 0;

  axi_lite_master u_bridge (
      .clk_i(clk), .rst_ni(rst_n),
      .req_addr_i(addr), .req_wdata_i(wdata),
      .req_wstrb_i(4'b1111),
      .req_we_i(we), .req_re_i(re),
      .resp_rdata_o(rdata), .stall_o(stall),
      .m_awaddr_o(awaddr), .m_awvalid_o(awvalid), .m_awready_i(awready),
      .m_wdata_o(wd), .m_wstrb_o(wstrb), .m_wvalid_o(wvalid), .m_wready_i(wready),
      .m_bresp_i(bresp), .m_bvalid_i(bvalid), .m_bready_o(bready),
      .m_araddr_o(araddr), .m_arvalid_o(arvalid), .m_arready_i(arready),
      .m_rdata_i(rd), .m_rresp_i(rresp), .m_rvalid_i(rvalid), .m_rready_o(rready)
  );

  axi_lite_timer u_timer (
      .clk_i(clk), .rst_ni(rst_n),
      .s_awaddr_i(awaddr), .s_awvalid_i(awvalid), .s_awready_o(awready),
      .s_wdata_i(wd), .s_wstrb_i(wstrb), .s_wvalid_i(wvalid), .s_wready_o(wready),
      .s_bresp_o(bresp), .s_bvalid_o(bvalid), .s_bready_i(bready),
      .s_araddr_i(araddr), .s_arvalid_i(arvalid), .s_arready_o(arready),
      .s_rdata_o(rd), .s_rresp_o(rresp), .s_rvalid_o(rvalid), .s_rready_i(rready)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic bus_write(input [31:0] a, input [31:0] d);
    @(negedge clk); addr = a; wdata = d; we = 1;
    @(negedge clk); while (stall) @(negedge clk);
    we = 0;
  endtask

  task automatic bus_read(input [31:0] a, output [31:0] d);
    @(negedge clk); addr = a; re = 1;
    @(negedge clk); while (stall) @(negedge clk);
    d = rdata; re = 0;
  endtask

  logic [31:0] t1, t2, hi;

  initial begin
    $dumpfile("tb_axi_timer.vcd");
    $dumpvars(0, tb_axi_timer);
    we = 0; re = 0; addr = 0; wdata = 0;
    rst_n = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // 1: counter advances by the elapsed cycles
    bus_read(32'h0, t1);
    repeat (50) @(negedge clk);
    bus_read(32'h0, t2);
    checks++;
    if (t2 - t1 < 50 || t2 - t1 > 60) begin
      errors++;
      $display("FAIL: expected ~50-60 cycle delta, got %0d", t2 - t1);
    end

    // 2: write resets
    bus_write(32'h0, 32'h0);
    bus_read(32'h0, t1);
    checks++;
    if (t1 > 10) begin
      errors++; $display("FAIL: counter not reset (read %0d)", t1);
    end

    // 3: hi shadow — force the counter near 32-bit rollover, read lo then hi
    u_timer.mtime_q = 64'h0000_0000_FFFF_FFF0;
    bus_read(32'h0, t1);      // latches hi=0 with lo
    repeat (40) @(negedge clk);  // counter rolls over during the gap
    bus_read(32'h4, hi);      // must return the LATCHED hi (0), not current (1)
    checks++;
    if (hi !== 32'd0) begin
      errors++;
      $display("FAIL: hi shadow broken — got %0d, expected latched 0", hi);
    end
    checks++;
    if (t1 < 32'hFFFF_FF00) begin
      errors++; $display("FAIL: lo read implausible: 0x%08h", t1);
    end

    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
