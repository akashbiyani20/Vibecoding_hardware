// ============================================================================
// fpga_top.sv — board wrapper for Digilent Basys 3 (Artix-7 XC7A35T)
// ----------------------------------------------------------------------------
// The ONLY file that knows about the board. It adapts:
//   - the 100 MHz oscillator to the SoC clock (direct — no PLL needed yet)
//   - the center button (active HIGH, mechanical) into a clean active-LOW
//     reset via a 2-flop synchronizer (async assert, synchronous release —
//     the standard reset conditioning circuit)
//   - SoC pins to physical pins (see basys3.xdc)
//
// Firmware: set PROGRAM_HEX to an absolute path or add the hex file to the
// Vivado project so $readmemh finds it at synthesis time.
// ============================================================================

module fpga_top (
    input  logic       clk100_i,   // W5  — 100 MHz oscillator
    input  logic       btn_rst_i,  // U18 — center button = reset
    output logic [7:0] led_o,      // board LEDs
    output logic       uart_tx_o,  // A18 — USB-UART bridge, 115200 baud
    input  logic       uart_rx_i   // B18 — USB-UART bridge, PC -> FPGA
);

  // ---- reset conditioning: async assert, sync release --------------------
  logic rst_n_meta, rst_n_sync;

  always_ff @(posedge clk100_i or posedge btn_rst_i) begin
    if (btn_rst_i) begin
      rst_n_meta <= 1'b0;
      rst_n_sync <= 1'b0;
    end else begin
      rst_n_meta <= 1'b1;
      rst_n_sync <= rst_n_meta;
    end
  end

  // ---- the chip ------------------------------------------------------------
  soc_top #(
      .PROGRAM_HEX ("prog_blink.hex"),   // firmware baked into the bitstream
      .CLKS_PER_BIT(868),                // 100 MHz / 115200 baud
      .GPIO_WIDTH  (8)
  ) u_soc (
      .clk_i    (clk100_i),
      .rst_ni   (rst_n_sync),
      .led_o    (led_o),
      .uart_tx_o(uart_tx_o),
      .uart_rx_i(uart_rx_i),
      .illegal_o()                        // unconnected on the board
  );

endmodule
