// ============================================================================
// tb_axi_gpio.sv — GPIO slave unit test (driven through the real bridge)
// ----------------------------------------------------------------------------
// Reuses the verified axi_lite_master as the bus driver, so the GPIO sees
// bona fide AXI traffic. Tests:
//   1. Reset state: all pins low
//   2. Write -> pins change
//   3. Read-back matches pins
//   4. Every bit pattern 0..255
//   5. Write to unmapped offset ignored, read of unmapped offset returns 0
// ============================================================================

`timescale 1ns / 1ps

module tb_axi_gpio;

  logic clk, rst_n;
  logic [31:0] addr, wdata, rdata;
  logic we, re, stall;
  logic [7:0] pins;

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
      .req_we_i(we), .req_re_i(re),
      .resp_rdata_o(rdata), .stall_o(stall),
      .m_awaddr_o(awaddr), .m_awvalid_o(awvalid), .m_awready_i(awready),
      .m_wdata_o(wd), .m_wstrb_o(wstrb), .m_wvalid_o(wvalid), .m_wready_i(wready),
      .m_bresp_i(bresp), .m_bvalid_i(bvalid), .m_bready_o(bready),
      .m_araddr_o(araddr), .m_arvalid_o(arvalid), .m_arready_i(arready),
      .m_rdata_i(rd), .m_rresp_i(rresp), .m_rvalid_i(rvalid), .m_rready_o(rready)
  );

  axi_lite_gpio #(.WIDTH(8)) u_gpio (
      .clk_i(clk), .rst_ni(rst_n),
      .gpio_o(pins),
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

  task automatic check32(input [31:0] got, input [31:0] exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL: %s | expected 0x%08h got 0x%08h", what, exp, got);
    end
  endtask

  logic [31:0] tmp;

  initial begin
    $dumpfile("tb_axi_gpio.vcd");
    $dumpvars(0, tb_axi_gpio);
    we = 0; re = 0; addr = 0; wdata = 0;
    rst_n = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // 1: reset state
    check32({24'd0, pins}, 32'd0, "pins low after reset");

    // 2: write turns pins on
    bus_write(32'h0, 32'h0000_00A5);
    check32({24'd0, pins}, 32'h0000_00A5, "pins follow write");

    // 3: read-back
    bus_read(32'h0, tmp);
    check32(tmp, 32'h0000_00A5, "read-back of GPIO_OUT");

    // 4: all patterns
    for (int v = 0; v < 256; v++) begin
      bus_write(32'h0, v);
      check32({24'd0, pins}, v[31:0], "pattern sweep");
    end

    // 5: unmapped offset — write ignored, read returns 0
    bus_write(32'h0, 32'h0000_0055);
    bus_write(32'h8, 32'hFFFF_FFFF);
    check32({24'd0, pins}, 32'h0000_0055, "write to 0x8 ignored");
    bus_read(32'h8, tmp);
    check32(tmp, 32'd0, "read of 0x8 returns 0");

    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
