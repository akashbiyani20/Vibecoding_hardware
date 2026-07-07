// ============================================================================
// tb_axi_uart.sv — UART TX unit test with a real serial decoder
// ----------------------------------------------------------------------------
// Black-box test: the testbench contains an independent 8N1 receiver that
// samples uart_tx_o at the right times (middle of each bit), exactly like a
// real terminal would. If framing, bit order, or timing were wrong, the
// decoded byte would be wrong.
// Tests:
//   1. Line idles high
//   2. Send one byte, decode it off the wire, check start/stop framing
//   3. STATUS busy flag: set during transmission, clear after
//   4. Write while busy is ignored (no corruption)
//   5. Poll-then-send stream "OK!" decoded correctly
// ============================================================================

`timescale 1ns / 1ps

module tb_axi_uart;

  localparam int CPB    = 16;              // clocks per bit (fast sim)
  localparam int BIT_NS = CPB * 10;        // 10 ns clock

  logic clk, rst_n;
  logic [31:0] addr, wdata, rdata;
  logic we, re, stall;
  logic tx;
  logic rx;

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

  axi_lite_uart #(.CLKS_PER_BIT(CPB)) u_uart (
      .clk_i(clk), .rst_ni(rst_n),
      .uart_tx_o(tx),
      .uart_rx_i(rx),
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

  // ---- independent 8N1 receiver: what a terminal does -------------------------
  task automatic uart_recv(output [7:0] b);
    @(negedge tx);                    // wait for start bit edge
    #(BIT_NS / 2);                    // move to middle of start bit
    checks++;
    if (tx !== 1'b0) begin
      errors++; $display("FAIL: start bit not low");
    end
    for (int i = 0; i < 8; i++) begin
      #(BIT_NS);                      // middle of data bit i
      b[i] = tx;                      // LSB first
    end
    #(BIT_NS);                        // middle of stop bit
    checks++;
    if (tx !== 1'b1) begin
      errors++; $display("FAIL: stop bit not high");
    end
  endtask

  // ---- independent 8N1 transmitter: what a terminal's keyboard does -----------
  task automatic uart_send(input [7:0] b);
    rx = 0;               #(BIT_NS);        // start bit
    for (int i = 0; i < 8; i++) begin
      rx = b[i];          #(BIT_NS);        // data bits, LSB first
    end
    rx = 1;               #(BIT_NS);        // stop bit
  endtask

  task automatic check32(input [31:0] got, input [31:0] exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL: %s | expected 0x%08h got 0x%08h", what, exp, got);
    end
  endtask

  logic [31:0] tmp;
  logic [7:0]  rxb;
  logic [7:0]  expected[0:2];

  initial begin
    $dumpfile("tb_axi_uart.vcd");
    $dumpvars(0, tb_axi_uart);
    we = 0; re = 0; addr = 0; wdata = 0;
    rx = 1;                      // line idles high
    rst_n = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // 1: idle line is high
    check32({31'd0, tx}, 32'd1, "line idles high");

    // 2: send 0x55 (alternating bits — catches bit-order mistakes), decode it
    fork
      bus_write(32'h0, 32'h0000_0055);
      uart_recv(rxb);
    join
    check32({24'd0, rxb}, 32'h0000_0055, "decoded byte 0x55");

    // 3: busy flag set right after accepting the byte...
    bus_read(32'h4, tmp);
    check32(tmp, 32'd1, "STATUS busy during TX");
    // ...and clear after the frame ends
    #(BIT_NS * 12);
    bus_read(32'h4, tmp);
    check32(tmp, 32'd0, "STATUS idle after TX");

    // 4: write while busy is ignored
    fork
      begin
        bus_write(32'h0, 32'h0000_0041);   // 'A' — accepted
        bus_write(32'h0, 32'h0000_005A);   // 'Z' while busy — must be dropped
      end
      uart_recv(rxb);
    join
    check32({24'd0, rxb}, 32'h0000_0041, "byte while busy dropped, 'A' intact");
    #(BIT_NS * 12);
    check32({31'd0, tx}, 32'd1, "no second frame after dropped byte");

    // 5: polled stream "OK!" like real firmware does
    expected[0] = "O"; expected[1] = "K"; expected[2] = "!";
    for (int c = 0; c < 3; c++) begin
      // poll STATUS until idle
      tmp = 1;
      while (tmp != 0) bus_read(32'h4, tmp);
      fork
        bus_write(32'h0, {24'd0, expected[c]});
        uart_recv(rxb);
      join
      check32({24'd0, rxb}, {24'd0, expected[c]}, "polled stream byte");
    end

    // ---- RX path -----------------------------------------------------------
    // 6: nothing received yet -> STATUS bit1 clear
    bus_read(32'h4, tmp);
    check32(tmp & 32'h2, 32'h0, "no RX data initially");
    // 7: send a byte into the rx pin, STATUS bit1 sets, RX reg holds it
    uart_send(8'h5A);
    #(BIT_NS);
    bus_read(32'h4, tmp);
    check32((tmp >> 1) & 32'h1, 32'h1, "RX valid after frame");
    bus_read(32'h8, tmp);
    check32(tmp, 32'h0000_005A, "RX byte value");
    // 8: reading popped it
    bus_read(32'h4, tmp);
    check32((tmp >> 1) & 32'h1, 32'h0, "RX valid cleared by read");
    // 9: two bytes back-to-back: second overwrites first (no FIFO)
    uart_send(8'h11);
    uart_send(8'h22);
    #(BIT_NS);
    bus_read(32'h8, tmp);
    check32(tmp, 32'h0000_0022, "overwrite: newest byte wins");

    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
