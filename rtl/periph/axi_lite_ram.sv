// ============================================================================
// axi_lite_ram.sv — data RAM with an AXI4-Lite slave interface
// ----------------------------------------------------------------------------
// Purpose:
//   The CPU's working memory (variables, stack, buffers), reachable over the
//   bus at 0x2000_0000 (the interconnect strips nothing — we just decode
//   low address bits here).
//
// The slave handshake pattern (reused by GPIO and UART — learn it once):
//   WRITE: wait until BOTH awvalid and wvalid are up, accept them together
//          in one cycle (awready = wready = handshake pulse), perform the
//          write, then hold bvalid until the master takes the response.
//          Accepting AW and W together is the simplest legal implementation.
//   READ:  accept ar when we're not already answering (arready = ~rvalid),
//          register the data, hold rvalid until rready.
//   Both paths respect the AXI rule that a slave must not drop valid
//   until the handshake completes.
//
// wstrb (write strobes): one bit per byte lane, so SB/SH write only their
//   lanes while the rest of the word is preserved.
//
// FPGA lesson learned the hard way (17-hour place & route):
//   The memory array and its read register live in a process WITHOUT a
//   reset. Physical block RAM (Cyclone V M10K, Xilinx BRAM) has no
//   asynchronous reset — if the array is touched inside an async-reset
//   process, synthesis silently falls back to FLIP-FLOPS: 32,768 registers
//   plus a mux the router chokes on. The AXI handshake flags keep their
//   async reset in separate processes; the RAM itself follows the clean
//   inference template below.
// ============================================================================

module axi_lite_ram #(
    parameter int DEPTH_WORDS = 1024,  // 4 KB
    parameter     INIT_FILE   = ""     // preload image (C .rodata/.data);
                                       // on FPGA this becomes BRAM init
) (
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

  localparam int AW = $clog2(DEPTH_WORDS);

  logic [31:0] mem[0:DEPTH_WORDS-1];

  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  // ---- write path ---------------------------------------------------------------
  logic wr_fire;
  assign wr_fire    = s_awvalid_i & s_wvalid_i & ~s_bvalid_o;
  assign s_awready_o = wr_fire;
  assign s_wready_o  = wr_fire;
  assign s_bresp_o   = 2'b00;                       // OKAY

  // ---- the RAM itself: no reset, sync write + sync read = M10K/BRAM ----------
  always_ff @(posedge clk_i) begin
    if (wr_fire) begin
      if (s_wstrb_i[0]) mem[s_awaddr_i[AW+1:2]][7:0]   <= s_wdata_i[7:0];
      if (s_wstrb_i[1]) mem[s_awaddr_i[AW+1:2]][15:8]  <= s_wdata_i[15:8];
      if (s_wstrb_i[2]) mem[s_awaddr_i[AW+1:2]][23:16] <= s_wdata_i[23:16];
      if (s_wstrb_i[3]) mem[s_awaddr_i[AW+1:2]][31:24] <= s_wdata_i[31:24];
    end
    if (rd_fire) s_rdata_o <= mem[s_araddr_i[AW+1:2]];
  end

  // ---- write response handshake (async reset is fine for plain flops) --------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)          s_bvalid_o <= 1'b0;
    else if (wr_fire)     s_bvalid_o <= 1'b1;
    else if (s_bready_i)  s_bvalid_o <= 1'b0;
  end

  // ---- read path -------------------------------------------------------------------
  logic rd_fire;
  assign rd_fire     = s_arvalid_i & s_arready_o;
  assign s_arready_o = ~s_rvalid_o;
  assign s_rresp_o   = 2'b00;                       // OKAY

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)          s_rvalid_o <= 1'b0;
    else if (rd_fire)     s_rvalid_o <= 1'b1;
    else if (s_rready_i)  s_rvalid_o <= 1'b0;
  end

endmodule
