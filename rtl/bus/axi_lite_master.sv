// ============================================================================
// axi_lite_master.sv — bridge: core's simple memory port -> AXI4-Lite master
// ----------------------------------------------------------------------------
// Why this module exists:
//   The core speaks a simple language: "here's an address, read it" and
//   expects the answer promptly. Real buses don't work that way — AXI4-Lite
//   splits every access into handshaked channels, and a slave may take any
//   number of cycles to answer. This bridge translates between the two
//   worlds and STALLS the core until the bus transaction finishes.
//
// AXI4-Lite in one paragraph (the part worth understanding):
//   Five independent channels, each with a valid/ready handshake —
//   write address (AW), write data (W), write response (B),
//   read address (AR), read data (R). A transfer happens on any channel
//   in the cycle where valid and ready are BOTH high. The golden rule:
//   once you assert valid, keep it (and the payload) stable until ready
//   arrives. Write = AW + W, then wait for B. Read = AR, then wait for R.
//
// State machine (one outstanding transaction, plenty for this core):
//
//   IDLE ──we_i──> WRITE (assert AWVALID+WVALID, drop each as accepted)
//        ──re_i──> READ  (assert ARVALID until accepted)
//   WRITE ──both accepted──> RESP_B (BREADY, wait BVALID)  ──> IDLE
//   READ  ──accepted──────> RESP_R (RREADY, wait RVALID)   ──> IDLE
//
//   stall_o = (re_i | we_i) & ~done — the core freezes from the cycle it
//   issues the request until the response cycle. During the response cycle
//   stall drops, read data flows combinationally to the core, and the core
//   retires the instruction on that clock edge.
//
// Timing: a read costs >= 3 cycles (AR, slave latency, R). The single-cycle
//   core simply stretches — correctness first, performance later.
// ============================================================================

module axi_lite_master (
    input  logic        clk_i,
    input  logic        rst_ni,

    // ---- core side (simple port) ----
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_wdata_i,
    input  logic [3:0]  req_wstrb_i,
    input  logic        req_we_i,
    input  logic        req_re_i,
    output logic [31:0] resp_rdata_o,
    output logic        stall_o,

    // ---- AXI4-Lite master side ----
    output logic [31:0] m_awaddr_o,
    output logic        m_awvalid_o,
    input  logic        m_awready_i,
    output logic [31:0] m_wdata_o,
    output logic [3:0]  m_wstrb_o,
    output logic        m_wvalid_o,
    input  logic        m_wready_i,
    input  logic [1:0]  m_bresp_i,
    input  logic        m_bvalid_i,
    output logic        m_bready_o,
    output logic [31:0] m_araddr_o,
    output logic        m_arvalid_o,
    input  logic        m_arready_i,
    input  logic [31:0] m_rdata_i,
    input  logic [1:0]  m_rresp_i,
    input  logic        m_rvalid_i,
    output logic        m_rready_o
);

  typedef enum logic [2:0] {IDLE, WRITE, RESP_B, READ, RESP_R} state_e;
  state_e state_q, state_d;

  // per-channel "already accepted" flags for the write phase
  logic aw_done_q, w_done_q;
  logic aw_accept, w_accept;

  assign aw_accept = m_awvalid_o & m_awready_i;
  assign w_accept  = m_wvalid_o  & m_wready_i;

  // ---- state register ---------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= IDLE;
      aw_done_q <= 1'b0;
      w_done_q  <= 1'b0;
    end else begin
      state_q <= state_d;
      if (state_q == IDLE) begin
        aw_done_q <= 1'b0;
        w_done_q  <= 1'b0;
      end else begin
        if (aw_accept) aw_done_q <= 1'b1;
        if (w_accept)  w_done_q  <= 1'b1;
      end
    end
  end

  // ---- next-state logic ----------------------------------------------------------
  always_comb begin
    state_d = state_q;
    unique case (state_q)
      IDLE:   if (req_we_i)      state_d = WRITE;
              else if (req_re_i) state_d = READ;
      WRITE:  if ((aw_done_q | aw_accept) && (w_done_q | w_accept))
                                 state_d = RESP_B;
      RESP_B: if (m_bvalid_i)    state_d = IDLE;
      READ:   if (m_arvalid_o & m_arready_i)
                                 state_d = RESP_R;
      RESP_R: if (m_rvalid_i)    state_d = IDLE;
      default:                   state_d = IDLE;
    endcase
  end

  // ---- channel outputs --------------------------------------------------------------
  assign m_awaddr_o  = req_addr_i;
  assign m_awvalid_o = (state_q == WRITE) & ~aw_done_q;
  assign m_wdata_o   = req_wdata_i;
  assign m_wstrb_o   = req_wstrb_i;                // byte lanes from the LSU
  assign m_wvalid_o  = (state_q == WRITE) & ~w_done_q;
  assign m_bready_o  = (state_q == RESP_B);

  assign m_araddr_o  = req_addr_i;
  assign m_arvalid_o = (state_q == READ);
  assign m_rready_o  = (state_q == RESP_R);

  // ---- core response --------------------------------------------------------------------
  // done = the cycle the response lands; read data flows straight through.
  logic done;
  assign done         = (state_q == RESP_R && m_rvalid_i) ||
                        (state_q == RESP_B && m_bvalid_i);
  assign resp_rdata_o = m_rdata_i;
  assign stall_o      = (req_re_i | req_we_i) & ~done;

endmodule
