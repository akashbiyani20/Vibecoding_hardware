// ============================================================================
// axi_lite_uart.sv — UART transmitter + receiver (AXI4-Lite slave)
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
//   0x00  TX      W   write a byte to transmit (ignored while TX busy)
//   0x04  STATUS  R   bit 0 = TX busy, bit 1 = RX byte waiting
//   0x08  RX      R   received byte; READING POPS IT (clears bit 1)
//
// Software contract:
//   send:    poll STATUS bit0 until 0, then write TX
//   receive: poll STATUS bit1 until 1, then read RX
//
// RX design: waits for the start-bit edge, then samples each bit at its
//   MIDDLE (start + 1.5, 2.5, ... bit times) — sampling mid-bit gives
//   maximum tolerance to clock mismatch between sender and receiver.
//   A new byte overwrites the previous unread one (no FIFO yet; a FIFO
//   is a natural future extension).
//
// Bus interface: same slave handshake pattern as axi_lite_ram/gpio.
// ============================================================================

module axi_lite_uart #(
    parameter int CLKS_PER_BIT = 868
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // serial pins
    output logic        uart_tx_o,
    input  logic        uart_rx_i,

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
  // reload constant sized to match the counter — keeps lint clean and the
  // intent explicit (CLKS_PER_BIT-1 always fits by construction)
  localparam int CNT_W = $clog2(CLKS_PER_BIT) + 1;
  localparam logic [CNT_W-1:0] BAUD_RELOAD = CNT_W'(CLKS_PER_BIT - 1);

  logic [9:0] shift_q;
  logic [3:0] bits_left_q;
  logic [CNT_W-1:0] baud_cnt_q;
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
        baud_cnt_q  <= BAUD_RELOAD;
      end else if (busy) begin
        if (baud_cnt_q == 0) begin
          shift_q     <= {1'b1, shift_q[9:1]};   // next bit, fill with idle
          bits_left_q <= bits_left_q - 1;
          baud_cnt_q  <= BAUD_RELOAD;
        end else begin
          baud_cnt_q <= baud_cnt_q - 1;
        end
      end
    end
  end

  // ==========================================================================
  // Receive engine: start-edge detect, then mid-bit sampling
  // ==========================================================================
  // 2-flop synchronizer: uart_rx_i comes from outside the chip and is not
  // aligned to our clock — sampling it directly risks metastability.
  logic rx_meta, rx_sync;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_meta <= 1'b1;
      rx_sync <= 1'b1;
    end else begin
      rx_meta <= uart_rx_i;
      rx_sync <= rx_meta;
    end
  end

  typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_e;
  rx_state_e rx_state_q;

  logic [CNT_W-1:0] rx_cnt_q;
  logic [2:0]       rx_bit_q;
  logic [7:0]       rx_shift_q;
  logic [7:0]       rx_data_q;
  logic             rx_valid_q;
  logic             rx_pop;

  localparam logic [CNT_W-1:0] HALF_BIT = CNT_W'(CLKS_PER_BIT / 2);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_state_q <= RX_IDLE;
      rx_cnt_q   <= '0;
      rx_bit_q   <= '0;
      rx_shift_q <= '0;
      rx_data_q  <= '0;
      rx_valid_q <= 1'b0;
    end else begin
      if (rx_pop) rx_valid_q <= 1'b0;   // reading the RX register pops it

      unique case (rx_state_q)
        RX_IDLE: begin
          if (rx_sync == 1'b0) begin            // start bit edge
            rx_state_q <= RX_START;
            rx_cnt_q   <= HALF_BIT;             // aim for middle of start bit
          end
        end
        RX_START: begin
          if (rx_cnt_q == 0) begin
            if (rx_sync == 1'b0) begin          // still low: real start bit
              rx_state_q <= RX_DATA;
              rx_cnt_q   <= BAUD_RELOAD;
              rx_bit_q   <= 3'd0;
            end else begin
              rx_state_q <= RX_IDLE;            // glitch — ignore
            end
          end else rx_cnt_q <= rx_cnt_q - 1'b1;
        end
        RX_DATA: begin
          if (rx_cnt_q == 0) begin              // middle of data bit
            rx_shift_q <= {rx_sync, rx_shift_q[7:1]};   // LSB first
            rx_cnt_q   <= BAUD_RELOAD;
            if (rx_bit_q == 3'd7) rx_state_q <= RX_STOP;
            else                  rx_bit_q   <= rx_bit_q + 1'b1;
          end else rx_cnt_q <= rx_cnt_q - 1'b1;
        end
        RX_STOP: begin
          if (rx_cnt_q == 0) begin              // middle of stop bit
            if (rx_sync == 1'b1) begin          // valid frame
              rx_data_q  <= rx_shift_q;
              rx_valid_q <= 1'b1;               // overwrites unread byte
            end
            rx_state_q <= RX_IDLE;              // framing error: drop silently
          end else rx_cnt_q <= rx_cnt_q - 1'b1;
        end
        default: rx_state_q <= RX_IDLE;
      endcase
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

  // reading offset 8 pops the RX byte (single-cycle pulse at accept time)
  assign rx_pop = rd_fire & (s_araddr_i[3:0] == 4'h8);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s_rvalid_o <= 1'b0;
      s_rdata_o  <= 32'd0;
    end else begin
      if (rd_fire) begin
        unique case (s_araddr_i[3:0])
          4'h4:    s_rdata_o <= {30'd0, rx_valid_q, busy};
          4'h8:    s_rdata_o <= {24'd0, rx_data_q};
          default: s_rdata_o <= 32'd0;
        endcase
        s_rvalid_o <= 1'b1;
      end else if (s_rready_i) begin
        s_rvalid_o <= 1'b0;
      end
    end
  end

endmodule
