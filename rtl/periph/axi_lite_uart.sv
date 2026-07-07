// ============================================================================
// axi_lite_uart.sv — UART transmitter (AXI4-Lite slave)
// ----------------------------------------------------------------------------
// Purpose:
//   Lets firmware print text. The CPU writes a byte to the TX register;
//   this module serializes it onto the uart_tx_o pin using the classic
//   8N1 format that every serial terminal understands:
//
//     idle ──start──> d0 d1 d2 d3 d4 d5 d6 d7 ──stop──> idle
//      (1)    (0)        LSB first, 8 bits        (1)
//
//   Each bit lasts CLKS_PER_BIT clock cycles. For a 100 MHz clock and
//   115200 baud: 100_000_000 / 115200 = 868. Testbenches use a small
//   value (e.g. 16) so simulations stay fast — the logic is identical.
//
// Register map (offsets from UART base 0x1000_1000):
//   0x00  TX      W   write a byte to transmit (ignored while busy)
//   0x04  STATUS  R   bit 0 = busy (1 while a frame is on the wire)
//
// Software contract: poll STATUS until busy==0, then write TX.
//   (prog_hello.s does exactly this.)
//
// Bus interface: same slave handshake pattern as axi_lite_ram/gpio.
// ============================================================================

module axi_lite_uart #(
    parameter int CLKS_PER_BIT = 868
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // serial output pin
    output logic        uart_tx_o,

    // AXI4-Lite slave
    input  logic [31:0] s_awaddr_i,
    input  logic        s_awvalid_i,
    output logic        s_awready_o,
    input  logic [31:0] s_wdata_i,
    input  logic [3:0]  s_wstrb_i,
    input  logic        s_wvalid_i,
    output logic        s_wready_o,
    output logic [1:0]  s_bresp_o,
    output logic        s_bvalid_o,
    input  logic        s_bready_i,
    input  logic [31:0] s_araddr_i,
    input  logic        s_arvalid_i,
    output logic        s_arready_o,
    output logic [31:0] s_rdata_o,
    output logic [1:0]  s_rresp_o,
    output logic        s_rvalid_o,
    input  logic        s_rready_i
);

  // ==========================================================================
  // Transmit engine
  // ==========================================================================
  // frame shift register: {stop, d7..d0, start} = 10 bits, sent LSB first.
  // A one-hot trick: preload 10 bits, shift right, count bits — when the
  // counter hits zero the line returns to idle (1) automatically because
  // we shift in 1s from the top.
  logic [9:0] shift_q;
  logic [3:0] bits_left_q;
  logic [$clog2(CLKS_PER_BIT):0] baud_cnt_q;
  logic       busy;
  logic       tx_start;
  logic [7:0] tx_byte;

  assign busy      = (bits_left_q != 0);
  assign uart_tx_o = busy ? shift_q[0] : 1'b1;   // idle line is high

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      shift_q     <= '1;
      bits_left_q <= '0;
      baud_cnt_q  <= '0;
    end else begin
      if (tx_start && !busy) begin
        shift_q     <= {1'b1, tx_byte, 1'b0};    // stop, data, start
        bits_left_q <= 4'd10;
        baud_cnt_q  <= CLKS_PER_BIT - 1;
      end else if (busy) begin
        if (baud_cnt_q == 0) begin
          shift_q     <= {1'b1, shift_q[9:1]};   // next bit, fill with idle
          bits_left_q <= bits_left_q - 1;
          baud_cnt_q  <= CLKS_PER_BIT - 1;
        end else begin
          baud_cnt_q <= baud_cnt_q - 1;
        end
      end
    end
  end

  // ==========================================================================
  // AXI4-Lite slave
  // ==========================================================================
  // ---- write path: a write to offset 0 starts a transmission ---------------
  logic wr_fire;
  assign wr_fire     = s_awvalid_i & s_wvalid_i & ~s_bvalid_o;
  assign s_awready_o = wr_fire;
  assign s_wready_o  = wr_fire;
  assign s_bresp_o   = 2'b00;
  assign tx_start    = wr_fire & (s_awaddr_i[3:0] == 4'h0) & s_wstrb_i[0];
  assign tx_byte     = s_wdata_i[7:0];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)          s_bvalid_o <= 1'b0;
    else if (wr_fire)     s_bvalid_o <= 1'b1;
    else if (s_bready_i)  s_bvalid_o <= 1'b0;
  end

  // ---- read path: offset 4 returns the busy flag ------------------------------
  logic rd_fire;
  assign rd_fire     = s_arvalid_i & s_arready_o;
  assign s_arready_o = ~s_rvalid_o;
  assign s_rresp_o   = 2'b00;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s_rvalid_o <= 1'b0;
      s_rdata_o  <= 32'd0;
    end else begin
      if (rd_fire) begin
        s_rdata_o  <= (s_araddr_i[3:0] == 4'h4) ? {31'd0, busy} : 32'd0;
        s_rvalid_o <= 1'b1;
      end else if (s_rready_i) begin
        s_rvalid_o <= 1'b0;
      end
    end
  end

endmodule
