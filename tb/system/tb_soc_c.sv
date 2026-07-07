// ============================================================================
// tb_soc_c.sv — THE milestone test: compiled C code running on our SoC
// ----------------------------------------------------------------------------
// Firmware: sw/c/main.c, built by sw/c/build.sh with riscv-gcc (-march=rv32i).
// "Flashing" = loading prog_c_text.hex into imem and prog_c_data.hex into
// RAM — exactly what BRAM initialization will do on the FPGA.
//
// The testbench acts as the serial terminal on the other end of the wire:
// it decodes everything the firmware prints, types two characters when the
// firmware asks for them, and finally compares the ENTIRE session against
// the expected transcript. It also counts LED blinks. Black-box, pins only.
//
// Expected transcript:
//   hello from C!\n answer=42\n counter=0\n 7*7=49\n blink done\n
//   (we type 'A' -> firmware echoes 'B'; type '1' -> echoes '2')
//   B2\nbye\n
// ============================================================================

`timescale 1ns / 1ps

module tb_soc_c;

  localparam int CPB    = 16;
  localparam int BIT_NS = CPB * 10;
  // expected length is computed at runtime while building expbuf

  logic clk, rst_n;
  logic [7:0] led;
  logic uart_tx, uart_rx, illegal;

  int errors = 0;
  int checks = 0;

  soc_top #(
      .PROGRAM_HEX (""),
      .DATA_HEX    (""),
      .CLKS_PER_BIT(CPB)
  ) dut (
      .clk_i    (clk),
      .rst_ni   (rst_n),
      .led_o    (led),
      .uart_tx_o(uart_tx),
      .uart_rx_i(uart_rx),
      .illegal_o(illegal)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst_n && illegal) begin
      errors++;
      $display("FAIL: illegal instruction at t=%0t (PC=0x%08h)",
               $time, dut.u_core.pc_q);
    end
  end

  // ---- serial receive (terminal side) ------------------------------------------
  task automatic uart_recv(output [7:0] b);
    @(negedge uart_tx);
    #(BIT_NS / 2);
    for (int i = 0; i < 8; i++) begin
      #(BIT_NS);
      b[i] = uart_tx;
    end
    #(BIT_NS);
  endtask

  // ---- serial send (typing on the terminal) --------------------------------------
  task automatic uart_send(input [7:0] b);
    uart_rx = 0;          #(BIT_NS);
    for (int i = 0; i < 8; i++) begin
      uart_rx = b[i];     #(BIT_NS);
    end
    uart_rx = 1;          #(BIT_NS);
  endtask

  // ---- continuous collector -------------------------------------------------------
  byte rxbuf[0:127];
  int  rxcount = 0;

  initial begin : collector
    logic [7:0] b;
    forever begin
      uart_recv(b);
      rxbuf[rxcount] = b;
      rxcount++;
    end
  end

  // ---- LED blink counter -------------------------------------------------------------
  int  led_toggles = 0;
  logic led_prev = 0;
  always @(posedge clk) begin
    if (rst_n && led[0] !== led_prev) begin
      led_toggles++;
      led_prev <= led[0];
    end
  end

  // ---- expected transcript ----------------------------------------------------------
  // built as a byte array with explicit 0x0A newlines (simulators disagree
  // about \n inside `string` literals — bytes are unambiguous)
  byte expbuf[0:127];
  int  explen = 0;

  task automatic exp_line(input string t);
    for (int i = 0; i < t.len(); i++) begin
      expbuf[explen] = t[i];
      explen++;
    end
    expbuf[explen] = 8'h0A;   // '\n'
    explen++;
  endtask

  string hexdir = "../../sw/build";

  initial begin
    $dumpfile("tb_soc_c.vcd");
    $dumpvars(0, tb_soc_c);
    uart_rx = 1;

    exp_line("hello from C!");
    exp_line("answer=42");
    exp_line("counter=0");
    exp_line("7*7=49");
    exp_line("blink done");
    exp_line("B2");
    exp_line("bye");

    // ---- flash the C program ------------------------------------------------
    $display("---- flashing compiled C firmware ----");
    for (int i = 0; i < 1024; i++) begin
      dut.u_imem.mem[i] = 32'h0000006F;
      dut.u_ram.mem[i]  = 32'd0;
    end
    if ($value$plusargs("hexdir=%s", hexdir)) ;
    $readmemh({hexdir, "/prog_c_text.hex"}, dut.u_imem.mem);
    $readmemh({hexdir, "/prog_c_data.hex"}, dut.u_ram.mem);

    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    // ---- wait for the firmware to print through "blink done\n" (52 chars) ----
    fork : waiter
      wait (rxcount >= 52);
      begin #40_000_000; $display("FAIL: timeout waiting for output"); errors++; end
    join_any
    disable waiter;

    // ---- firmware is now blocking in uart_getc() — type two characters --------
    uart_send("A");
    fork : w2
      wait (rxcount >= 53);
      begin #4_000_000; errors++; $display("FAIL: no echo for 'A'"); end
    join_any
    disable w2;
    uart_send("1");
    fork : w3
      wait (rxcount >= explen);
      begin #4_000_000; errors++; $display("FAIL: session incomplete"); end
    join_any
    disable w3;

    // ---- compare the whole session, byte by byte -----------------------------------
    checks++;
    if (rxcount != explen) begin
      errors++;
      $display("FAIL: expected %0d chars, received %0d", explen, rxcount);
    end
    begin
      int mismatches = 0;
      for (int i = 0; i < rxcount && i < explen; i++) begin
        if (rxbuf[i] !== expbuf[i]) begin
          mismatches++;
          $display("FAIL: char %0d: expected 0x%02h got 0x%02h",
                   i, expbuf[i], rxbuf[i]);
        end
      end
      checks++;
      if (mismatches != 0) errors++;
      else begin
        $display("  transcript OK (%0d chars). Session as a terminal saw it:", rxcount);
        for (int i = 0; i < rxcount; i++) $write("%c", rxbuf[i]);
      end
    end

    checks++;
    if (led_toggles < 6) begin
      errors++;
      $display("FAIL: expected >=6 LED toggles, saw %0d", led_toggles);
    end else begin
      $display("  LED blinked: %0d toggles", led_toggles);
    end

    if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
    else             $display("RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

endmodule
