// ============================================================================
// axi_lite_timer.sv — Timer peripheral (AXI4-Lite slave)
// ----------------------------------------------------------------------------
// Purpose:
//   A free-running 64-bit cycle counter. Firmware reads it to measure time
//   or to build ACCURATE delays — instead of calibrated delay loops (which
//   change speed whenever the code or clock changes), C code does:
//
//     start = timer_lo();  while (timer_lo() - start < CYCLES) {}
//
//   64 bits because 32 bits at 100 MHz wraps in 43 seconds; 64 bits lasts
//   5,800 years — a real product would never ship a 32-bit wall clock.
//
// Register map (base 0x1000_2000):
//   0x00  MTIME_LO  R  low 32 bits
//   0x04  MTIME_HI  R  high 32 bits (LATCHED — see below)
//   any write        resets the counter to 0
//
// The latching trick (a classic hardware race and its fix):
//   Reading 64 bits takes TWO bus reads, and the counter keeps running
//   between them. If the low word rolls over 0xFFFFFFFF -> 0 in between,
//   naive software computes a time that is off by 4 billion cycles.
//   Fix: reading MTIME_LO also captures MTIME_HI into a shadow register,
//   and reading MTIME_HI returns the SHADOW. Read lo-then-hi and the pair
//   is always coherent. (The RISC-V privileged spec discusses exactly this
//   problem for rdtime on 32-bit cores.)
// ============================================================================

module axi_lite_timer (
    input  logic        clk_i,
    input  logic        rst_ni,

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

  logic [63:0] mtime_q;
  logic [31:0] hi_shadow_q;

  // ---- write path: any write resets the counter --------------------------------
  logic wr_fire;
  assign wr_fire     = s_awvalid_i & s_wvalid_i & ~s_bvalid_o;
  assign s_awready_o = wr_fire;
  assign s_wready_o  = wr_fire;
  assign s_bresp_o   = 2'b00;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)          s_bvalid_o <= 1'b0;
    else if (wr_fire)     s_bvalid_o <= 1'b1;
    else if (s_bready_i)  s_bvalid_o <= 1'b0;
  end

  // ---- the counter ---------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)       mtime_q <= 64'd0;
    else if (wr_fire)  mtime_q <= 64'd0;
    else               mtime_q <= mtime_q + 64'd1;
  end

  // ---- read path with hi-shadow latch ----------------------------------------------
  logic rd_fire;
  assign rd_fire     = s_arvalid_i & s_arready_o;
  assign s_arready_o = ~s_rvalid_o;
  assign s_rresp_o   = 2'b00;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s_rvalid_o  <= 1'b0;
      s_rdata_o   <= 32'd0;
      hi_shadow_q <= 32'd0;
    end else begin
      if (rd_fire) begin
        if (s_araddr_i[3:0] == 4'h0) begin
          s_rdata_o   <= mtime_q[31:0];
          hi_shadow_q <= mtime_q[63:32];   // capture hi with lo — coherent pair
        end else if (s_araddr_i[3:0] == 4'h4) begin
          s_rdata_o   <= hi_shadow_q;
        end else begin
          s_rdata_o   <= 32'd0;
        end
        s_rvalid_o <= 1'b1;
      end else if (s_rready_i) begin
        s_rvalid_o <= 1'b0;
      end
    end
  end

endmodule
