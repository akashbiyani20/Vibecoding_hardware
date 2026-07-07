// ============================================================================
// tb_soc.sv — system test: firmware running on the complete SoC
// ----------------------------------------------------------------------------
// This is the closest simulation gets to "flash it and watch it work":
// the ONLY things the testbench touches are the chip's real pins —
// clock, reset, LEDs, and the serial line. Pure black-box testing.
//
//   Test 1 (prog_blink):  count LED toggles, check they alternate with a
//                         steady period (the delay loop's signature).
//   Test 2 (prog_hello):  an independent 8N1 receiver decodes the serial
//                         line and must read exactly "Hi!\n".
//
// Plus the usual invariant: the core must never hit an illegal instruction.
// ============================================================================

`timescale 1ns / 1ps

module tb_soc;

  localparam int CPB    = 16;          // UART clocks per bit (fast sim)
  localparam int BIT_NS = CPB * 10;

  logic clk, rst_n;
  logic [7:0] led;
  logic uart_tx, illegal;

  int errors = 0;
  int checks = 0;

  soc_top #(
      .PROGRAM_HEX (""),               // loaded per-test via $readmemh
      .CLKS_PER_BIT(CPB)
  ) dut (
      .clk_i    (clk),
      .rst_ni   (rst_n),
      .led_o    (led),
      .uart_tx_o(uart_tx),
      .illegal_o(illegal)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  // illegal-instruction watchdog
  always @(posedge clk) begin
    if (rst_n && illegal) begin
      errors++;
      $display("FAIL: illegal instruction in SoC at t=%0t", $time);
    end
  end

  string hexdir = "../../sw/build";

  task automatic load_and_reset(input string name);
    string path;
    path = {hexdir, "/", name, ".hex"};
    $display("---- flashing %s ----", name);
    for (int i = 0; i < 1024; i++) begin
      dut.u_imem.mem[i] = 32'h0000006F;  // fill: safe self-loop
      dut.u_ram.mem[i]  = 32'd0;
    end
    $readmemh(path, dut.u_imem.mem);
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
  endtask

  // independent 8N1 serial receiver (same as tb_axi_uart)
  task automatic uart_recv(output [7:0] b);
    @(negedge uart_tx);
    #(BIT_NS / 2);
    checks++;
    if (uart_tx !== 1'b0) begin errors++; $display("FAIL: start bit"); end
    for (int i = 0; i < 8; i++) begin
      #(BIT_NS);
      b[i] = uart_tx;
    end
    #(BIT_NS);
    checks++;
    if (uart_tx !== 1'b1) begin errors++; $display("FAIL: stop bit"); end
  endtask

  // ---- LED toggle observer -----------------------------------------------------
  int     toggle_count;
  logic   led_prev;
  time    last_toggle, period, first_period;

  logic [7:0] rxb;
  logic [7:0] expected[0:3];

  initial begin
    $dumpfile("tb_soc.vcd");
    $dumpvars(0, tb_soc);
    if ($value$plusargs("hexdir=%s", hexdir)) ;
    rst_n = 0;

    // ================= Test 1: LED blink =================
    load_and_reset("prog_blink");

    toggle_count = 0;
    led_prev     = led[0];
    last_toggle  = 0;
    first_period = 0;
    // watch the LED pin for a while
    repeat (400) begin
      @(posedge clk);
      if (led[0] !== led_prev) begin
        toggle_count++;
        if (last_toggle != 0) begin
          period = $time - last_toggle;
          if (first_period == 0) first_period = period;
          else begin
            checks++;
            if (period != first_period) begin
              errors++;
              $display("FAIL: blink period drifted (%0t vs %0t)",
                       period, first_period);
            end
          end
        end
        last_toggle = $time;
        led_prev    = led[0];
      end
    end
    checks++;
    if (toggle_count < 6) begin
      errors++;
      $display("FAIL: expected >=6 LED toggles, saw %0d", toggle_count);
    end else begin
      $display("      LED toggled %0d times, steady period %0t ns",
               toggle_count, first_period);
    end

    // ================= Test 2: UART hello =================
    load_and_reset("prog_hello");

    expected[0] = "H"; expected[1] = "i";
    expected[2] = "!"; expected[3] = 8'h0A;   // '\n'
    for (int c = 0; c < 4; c++) begin
      uart_recv(rxb);
      checks++;
      if (rxb !== expected[c]) begin
        errors++;
        $display("FAIL: UART byte %0d: expected 0x%02h ('%c'), got 0x%02h",
                 c, expected[c], expected[c], rxb);
      end else begin
        $display("      UART received: 0x%02h ('%c')", rxb,
                 (rxb >= 32) ? rxb : 8'h20);
      end
    end
    // line must return to idle and stay there
    #(BIT_NS * 20);
    checks++;
    if (uart_tx !== 1'b1) begin
      errors++; $display("FAIL: UART line not idle after message");
    end

    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d/%0d checks failed)", errors, checks);
    $finish;
  end

endmodule
