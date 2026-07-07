// ============================================================================
// axi_lite_xbar.sv — AXI4-Lite interconnect: 1 master, 4 slaves
// ----------------------------------------------------------------------------
// Purpose:
//   The "switchboard" of the SoC. The CPU issues one address; this module
//   decides which peripheral answers, forwards the request there, and routes
//   the response back. Nothing more — an interconnect is just address
//   decoding plus multiplexers.
//
// Memory map implemented here (docs/memory_map.md):
//   0x2000_0000  4 KB   slave 0: data RAM
//   0x1000_0000  4 KB   slave 1: GPIO
//   0x1000_1000  4 KB   slave 2: UART
//   0x1000_2000  4 KB   slave 3: timer
//   anything else  -->  built-in default responder, answers DECERR
//
// Decode rule: addr[31:28] picks the region (2 = RAM, 1 = peripherals),
//   then addr[15:12] picks the peripheral inside region 1. Reads and writes
//   are decoded independently (AXI allows simultaneous read + write).
//
// Simplification honesty: this design relies on the single outstanding
//   transaction guaranteed by our bridge — the decode mux follows the
//   current address, which the master holds stable for the whole
//   transaction. A multi-master or pipelined interconnect must latch the
//   selection instead; that's a later lesson.
//
// The default responder: answering "nobody lives at this address" with a
//   DECERR response instead of hanging the bus. Without it, a firmware bug
//   (wild pointer) would freeze the CPU forever with no clue why.
// ============================================================================

module axi_lite_xbar (
    input  logic        clk_i,
    input  logic        rst_ni,

    // ---- from the master (bridge) ----
    input  logic [31:0] m_awaddr_i,
    input  logic        m_awvalid_i,
    output logic        m_awready_o,
    input  logic [31:0] m_wdata_i,
    input  logic [3:0]  m_wstrb_i,
    input  logic        m_wvalid_i,
    output logic        m_wready_o,
    output logic [1:0]  m_bresp_o,
    output logic        m_bvalid_o,
    input  logic        m_bready_i,
    input  logic [31:0] m_araddr_i,
    input  logic        m_arvalid_i,
    output logic        m_arready_o,
    output logic [31:0] m_rdata_o,
    output logic [1:0]  m_rresp_o,
    output logic        m_rvalid_o,
    input  logic        m_rready_i,

    // ---- to slave 0: RAM ----
    output logic [31:0] s0_awaddr_o,
    output logic        s0_awvalid_o,
    input  logic        s0_awready_i,
    output logic [31:0] s0_wdata_o,
    output logic [3:0]  s0_wstrb_o,
    output logic        s0_wvalid_o,
    input  logic        s0_wready_i,
    input  logic [1:0]  s0_bresp_i,
    input  logic        s0_bvalid_i,
    output logic        s0_bready_o,
    output logic [31:0] s0_araddr_o,
    output logic        s0_arvalid_o,
    input  logic        s0_arready_i,
    input  logic [31:0] s0_rdata_i,
    input  logic [1:0]  s0_rresp_i,
    input  logic        s0_rvalid_i,
    output logic        s0_rready_o,

    // ---- to slave 1: GPIO ----
    output logic [31:0] s1_awaddr_o,
    output logic        s1_awvalid_o,
    input  logic        s1_awready_i,
    output logic [31:0] s1_wdata_o,
    output logic [3:0]  s1_wstrb_o,
    output logic        s1_wvalid_o,
    input  logic        s1_wready_i,
    input  logic [1:0]  s1_bresp_i,
    input  logic        s1_bvalid_i,
    output logic        s1_bready_o,
    output logic [31:0] s1_araddr_o,
    output logic        s1_arvalid_o,
    input  logic        s1_arready_i,
    input  logic [31:0] s1_rdata_i,
    input  logic [1:0]  s1_rresp_i,
    input  logic        s1_rvalid_i,
    output logic        s1_rready_o,

    // ---- to slave 2: UART ----
    output logic [31:0] s2_awaddr_o,
    output logic        s2_awvalid_o,
    input  logic        s2_awready_i,
    output logic [31:0] s2_wdata_o,
    output logic [3:0]  s2_wstrb_o,
    output logic        s2_wvalid_o,
    input  logic        s2_wready_i,
    input  logic [1:0]  s2_bresp_i,
    input  logic        s2_bvalid_i,
    output logic        s2_bready_o,
    output logic [31:0] s2_araddr_o,
    output logic        s2_arvalid_o,
    input  logic        s2_arready_i,
    input  logic [31:0] s2_rdata_i,
    input  logic [1:0]  s2_rresp_i,
    input  logic        s2_rvalid_i,
    output logic        s2_rready_o,

    // ---- to slave 3: timer ----
    output logic [31:0] s3_awaddr_o,
    output logic        s3_awvalid_o,
    input  logic        s3_awready_i,
    output logic [31:0] s3_wdata_o,
    output logic [3:0]  s3_wstrb_o,
    output logic        s3_wvalid_o,
    input  logic        s3_wready_i,
    input  logic [1:0]  s3_bresp_i,
    input  logic        s3_bvalid_i,
    output logic        s3_bready_o,
    output logic [31:0] s3_araddr_o,
    output logic        s3_arvalid_o,
    input  logic        s3_arready_i,
    input  logic [31:0] s3_rdata_i,
    input  logic [1:0]  s3_rresp_i,
    input  logic        s3_rvalid_i,
    output logic        s3_rready_o
);

  // ---- address decode -------------------------------------------------------
  localparam logic [2:0] SEL_RAM = 3'd0, SEL_GPIO = 3'd1,
                         SEL_UART = 3'd2, SEL_TIMER = 3'd3, SEL_NONE = 3'd4;

  function automatic logic [2:0] decode(input logic [31:0] a);
    if (a[31:28] == 4'h2)                          decode = SEL_RAM;
    else if (a[31:28] == 4'h1 && a[15:12] == 4'h0) decode = SEL_GPIO;
    else if (a[31:28] == 4'h1 && a[15:12] == 4'h1) decode = SEL_UART;
    else if (a[31:28] == 4'h1 && a[15:12] == 4'h2) decode = SEL_TIMER;
    else                                           decode = SEL_NONE;
  endfunction

  logic [2:0] wsel, rsel;
  assign wsel = decode(m_awaddr_i);
  assign rsel = decode(m_araddr_i);

  // ---- broadcast payloads (valids do the selecting) ----------------------------
  assign s0_awaddr_o = m_awaddr_i;  assign s0_wdata_o = m_wdata_i;
  assign s0_wstrb_o  = m_wstrb_i;   assign s0_araddr_o = m_araddr_i;
  assign s1_awaddr_o = m_awaddr_i;  assign s1_wdata_o = m_wdata_i;
  assign s1_wstrb_o  = m_wstrb_i;   assign s1_araddr_o = m_araddr_i;
  assign s2_awaddr_o = m_awaddr_i;  assign s2_wdata_o = m_wdata_i;
  assign s2_wstrb_o  = m_wstrb_i;   assign s2_araddr_o = m_araddr_i;
  assign s3_awaddr_o = m_awaddr_i;  assign s3_wdata_o = m_wdata_i;
  assign s3_wstrb_o  = m_wstrb_i;   assign s3_araddr_o = m_araddr_i;

  // ---- write channel routing ------------------------------------------------------
  assign s0_awvalid_o = m_awvalid_i & (wsel == SEL_RAM);
  assign s1_awvalid_o = m_awvalid_i & (wsel == SEL_GPIO);
  assign s2_awvalid_o = m_awvalid_i & (wsel == SEL_UART);
  assign s0_wvalid_o  = m_wvalid_i  & (wsel == SEL_RAM);
  assign s1_wvalid_o  = m_wvalid_i  & (wsel == SEL_GPIO);
  assign s2_wvalid_o  = m_wvalid_i  & (wsel == SEL_UART);
  assign s0_bready_o  = m_bready_i  & (wsel == SEL_RAM);
  assign s1_bready_o  = m_bready_i  & (wsel == SEL_GPIO);
  assign s2_bready_o  = m_bready_i  & (wsel == SEL_UART);
  assign s3_awvalid_o = m_awvalid_i & (wsel == SEL_TIMER);
  assign s3_wvalid_o  = m_wvalid_i  & (wsel == SEL_TIMER);
  assign s3_bready_o  = m_bready_i  & (wsel == SEL_TIMER);

  // ---- read channel routing ----------------------------------------------------------
  assign s0_arvalid_o = m_arvalid_i & (rsel == SEL_RAM);
  assign s1_arvalid_o = m_arvalid_i & (rsel == SEL_GPIO);
  assign s2_arvalid_o = m_arvalid_i & (rsel == SEL_UART);
  assign s0_rready_o  = m_rready_i  & (rsel == SEL_RAM);
  assign s1_rready_o  = m_rready_i  & (rsel == SEL_GPIO);
  assign s2_rready_o  = m_rready_i  & (rsel == SEL_UART);
  assign s3_arvalid_o = m_arvalid_i & (rsel == SEL_TIMER);
  assign s3_rready_o  = m_rready_i  & (rsel == SEL_TIMER);

  // ---- default responder for unmapped addresses ------------------------------------------
  // Completes the handshake with resp = DECERR (2'b11) so the bus never hangs.
  logic def_bvalid_q, def_rvalid_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      def_bvalid_q <= 1'b0;
      def_rvalid_q <= 1'b0;
    end else begin
      // write: accept AW+W together when targeted, then answer
      if (m_awvalid_i && m_wvalid_i && wsel == SEL_NONE && !def_bvalid_q)
        def_bvalid_q <= 1'b1;
      else if (m_bready_i)
        def_bvalid_q <= 1'b0;
      // read
      if (m_arvalid_i && rsel == SEL_NONE && !def_rvalid_q)
        def_rvalid_q <= 1'b1;
      else if (m_rready_i)
        def_rvalid_q <= 1'b0;
    end
  end

  logic def_aw_fire, def_ar_fire;
  assign def_aw_fire = m_awvalid_i & m_wvalid_i & (wsel == SEL_NONE) & ~def_bvalid_q;
  assign def_ar_fire = m_arvalid_i & (rsel == SEL_NONE) & ~def_rvalid_q;

  // ---- response muxes back to the master --------------------------------------------------
  always_comb begin
    unique case (wsel)
      SEL_RAM:  begin m_awready_o = s0_awready_i; m_wready_o = s0_wready_i;
                      m_bresp_o = s0_bresp_i;     m_bvalid_o = s0_bvalid_i; end
      SEL_GPIO: begin m_awready_o = s1_awready_i; m_wready_o = s1_wready_i;
                      m_bresp_o = s1_bresp_i;     m_bvalid_o = s1_bvalid_i; end
      SEL_UART: begin m_awready_o = s2_awready_i; m_wready_o = s2_wready_i;
                      m_bresp_o = s2_bresp_i;     m_bvalid_o = s2_bvalid_i; end
      SEL_TIMER:begin m_awready_o = s3_awready_i; m_wready_o = s3_wready_i;
                      m_bresp_o = s3_bresp_i;     m_bvalid_o = s3_bvalid_i; end
      default:  begin m_awready_o = def_aw_fire;  m_wready_o = def_aw_fire;
                      m_bresp_o = 2'b11;          m_bvalid_o = def_bvalid_q; end
    endcase
    unique case (rsel)
      SEL_RAM:  begin m_arready_o = s0_arready_i; m_rdata_o = s0_rdata_i;
                      m_rresp_o = s0_rresp_i;     m_rvalid_o = s0_rvalid_i; end
      SEL_GPIO: begin m_arready_o = s1_arready_i; m_rdata_o = s1_rdata_i;
                      m_rresp_o = s1_rresp_i;     m_rvalid_o = s1_rvalid_i; end
      SEL_UART: begin m_arready_o = s2_arready_i; m_rdata_o = s2_rdata_i;
                      m_rresp_o = s2_rresp_i;     m_rvalid_o = s2_rvalid_i; end
      SEL_TIMER:begin m_arready_o = s3_arready_i; m_rdata_o = s3_rdata_i;
                      m_rresp_o = s3_rresp_i;     m_rvalid_o = s3_rvalid_i; end
      default:  begin m_arready_o = def_ar_fire;  m_rdata_o = 32'hDEAD_DEC0;
                      m_rresp_o = 2'b11;          m_rvalid_o = def_rvalid_q; end
    endcase
  end

endmodule
