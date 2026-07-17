// ============================================================================
// fpga_top.sv — board wrapper for Intel/Altera Cyclone V (Quartus Prime)
// ----------------------------------------------------------------------------
// Differences from the Basys 3 (Artix-7) wrapper — and the ONLY things that
// change between FPGA vendors in this whole project:
//
//   1. Clock: Terasic Cyclone V boards provide 50 MHz (Basys 3: 100 MHz).
//      Only consequence: UART divider = 50e6 / 115200 = 434.
//   2. Reset: Terasic KEY buttons are ACTIVE-LOW (pressed = 0) and already
//      debounced-ish; Digilent buttons are active-high. We still run the
//      2-flop synchronizer — always condition external resets.
//   3. Pin names/locations: set in the .qsf file instead of an .xdc.
//
// The SoC itself (rtl/) is untouched. That's the point of vendor-neutral RTL.
//
// No board yet: this compiles as-is for resource/timing analysis. When a
// board arrives, uncomment its pin assignments in cyclone5.qsf.
// ============================================================================

module fpga_top (
    input  logic       clk50_i,     // 50 MHz board oscillator
    input  logic       key0_n_i,    // KEY0 pushbutton, ACTIVE LOW = reset
    output logic [7:0] led_o,       // LEDR[7:0]
    output logic       uart_tx_o,   // to USB-serial adapter (GPIO header)
    input  logic       uart_rx_i    // from USB-serial adapter
);

  // ---- reset conditioning: async assert, sync release ----------------------
  // key0_n_i is already active-low, matching our rst_ni convention.
  logic rst_n_meta, rst_n_sync;

  always_ff @(posedge clk50_i or negedge key0_n_i) begin
    if (!key0_n_i) begin
      rst_n_meta <= 1'b0;
      rst_n_sync <= 1'b0;
    end else begin
      rst_n_meta <= 1'b1;
      rst_n_sync <= rst_n_meta;
    end
  end

  // ---- the chip --------------------------------------------------------------
  soc_top #(
      .PROGRAM_HEX ("prog_c_text.hex"),  // firmware code  (put hex in project dir)
      .DATA_HEX    ("prog_c_data.hex"),  // firmware data
      .CLKS_PER_BIT(434),                // 50 MHz / 115200 baud
      .GPIO_WIDTH  (8)
  ) u_soc (
      .clk_i    (clk50_i),
      .rst_ni   (rst_n_sync),
      .led_o    (led_o),
      .uart_tx_o(uart_tx_o),
      .uart_rx_i(uart_rx_i),
      .illegal_o()
  );

endmodule
