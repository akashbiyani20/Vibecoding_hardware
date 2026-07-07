// ============================================================================
// soc_top.sv — the complete System-on-Chip (Phase 1)
// ----------------------------------------------------------------------------
// This is the chip. Everything below this module is internal wiring;
// everything above it is the outside world (clock, reset, LEDs, serial).
//
//                +-------------------------------------------+
//                |                 soc_top                   |
//                |   +--------+        +--------------+      |
//   clk, rst --->|   |  imem  |<-fetch-|   core_top   |      |
//                |   +--------+        +------+-------+      |
//                |                            | data port    |
//                |                    +-------+--------+     |
//                |                    | axi_lite_master|     |
//                |                    +-------+--------+     |
//                |                            | AXI4-Lite    |
//                |                    +-------+--------+     |
//                |                    | axi_lite_xbar  |     |
//                |                    +--+-----+----+--+     |
//                |                       |     |    |        |
//                |                  +----+  +--+--+ +-+----+ |
//                |                  | RAM |  |GPIO | | UART | |
//                |                  +-----+  +--+--+ +-+----+ |
//                +-------------------------------|------|----+
//                                            led_o   uart_tx_o
//
// Instruction fetch stays on a private port to imem (not through the AXI
// bus). This is a real architecture pattern (Harvard-style split); it also
// keeps the single-cycle fetch simple. Programs are "flashed" by loading
// the imem contents — in simulation via $readmemh, on FPGA via the
// bitstream's BRAM initialization.
//
// Parameters:
//   PROGRAM_HEX   — firmware image to preload (sw/build/*.hex)
//   CLKS_PER_BIT  — UART baud divider (868 = 115200 @ 100 MHz;
//                   testbenches use 16 to keep simulations fast)
// ============================================================================

module soc_top #(
    parameter              PROGRAM_HEX  = "",
    parameter int          CLKS_PER_BIT = 868,
    parameter int          GPIO_WIDTH   = 8
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    output logic [GPIO_WIDTH-1:0] led_o,
    output logic                  uart_tx_o,
    output logic                  illegal_o   // debug: unsupported instruction
);

  // ---- core <-> imem ----------------------------------------------------------
  logic [31:0] imem_addr, imem_rdata;

  // ---- core <-> bridge ---------------------------------------------------------
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic        dmem_we, dmem_re, stall;

  // ---- bridge <-> xbar (master side) ---------------------------------------------
  logic [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
  logic [3:0]  m_wstrb;
  logic [1:0]  m_bresp, m_rresp;
  logic m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
  logic m_arvalid, m_arready, m_rvalid, m_rready;

  // ---- xbar <-> slaves ---------------------------------------------------------------
  // s0 = RAM, s1 = GPIO, s2 = UART
  logic [31:0] s0_awaddr, s0_wdata, s0_araddr, s0_rdata;
  logic [3:0]  s0_wstrb;
  logic [1:0]  s0_bresp, s0_rresp;
  logic s0_awvalid, s0_awready, s0_wvalid, s0_wready, s0_bvalid, s0_bready;
  logic s0_arvalid, s0_arready, s0_rvalid, s0_rready;

  logic [31:0] s1_awaddr, s1_wdata, s1_araddr, s1_rdata;
  logic [3:0]  s1_wstrb;
  logic [1:0]  s1_bresp, s1_rresp;
  logic s1_awvalid, s1_awready, s1_wvalid, s1_wready, s1_bvalid, s1_bready;
  logic s1_arvalid, s1_arready, s1_rvalid, s1_rready;

  logic [31:0] s2_awaddr, s2_wdata, s2_araddr, s2_rdata;
  logic [3:0]  s2_wstrb;
  logic [1:0]  s2_bresp, s2_rresp;
  logic s2_awvalid, s2_awready, s2_wvalid, s2_wready, s2_bvalid, s2_bready;
  logic s2_arvalid, s2_arready, s2_rvalid, s2_rready;

  // ==========================================================================
  // Instances
  // ==========================================================================
  imem #(
      .DEPTH_WORDS(1024),
      .INIT_FILE  (PROGRAM_HEX)
  ) u_imem (
      .addr_i (imem_addr),
      .rdata_o(imem_rdata)
  );

  core_top u_core (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni),
      .stall_i     (stall),
      .imem_addr_o (imem_addr),
      .imem_rdata_i(imem_rdata),
      .dmem_addr_o (dmem_addr),
      .dmem_wdata_o(dmem_wdata),
      .dmem_we_o   (dmem_we),
      .dmem_re_o   (dmem_re),
      .dmem_rdata_i(dmem_rdata),
      .illegal_o   (illegal_o)
  );

  axi_lite_master u_bridge (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .req_addr_i(dmem_addr), .req_wdata_i(dmem_wdata),
      .req_we_i(dmem_we), .req_re_i(dmem_re),
      .resp_rdata_o(dmem_rdata), .stall_o(stall),
      .m_awaddr_o(m_awaddr), .m_awvalid_o(m_awvalid), .m_awready_i(m_awready),
      .m_wdata_o(m_wdata), .m_wstrb_o(m_wstrb), .m_wvalid_o(m_wvalid), .m_wready_i(m_wready),
      .m_bresp_i(m_bresp), .m_bvalid_i(m_bvalid), .m_bready_o(m_bready),
      .m_araddr_o(m_araddr), .m_arvalid_o(m_arvalid), .m_arready_i(m_arready),
      .m_rdata_i(m_rdata), .m_rresp_i(m_rresp), .m_rvalid_i(m_rvalid), .m_rready_o(m_rready)
  );

  axi_lite_xbar u_xbar (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .m_awaddr_i(m_awaddr), .m_awvalid_i(m_awvalid), .m_awready_o(m_awready),
      .m_wdata_i(m_wdata), .m_wstrb_i(m_wstrb), .m_wvalid_i(m_wvalid), .m_wready_o(m_wready),
      .m_bresp_o(m_bresp), .m_bvalid_o(m_bvalid), .m_bready_i(m_bready),
      .m_araddr_i(m_araddr), .m_arvalid_i(m_arvalid), .m_arready_o(m_arready),
      .m_rdata_o(m_rdata), .m_rresp_o(m_rresp), .m_rvalid_o(m_rvalid), .m_rready_i(m_rready),
      .s0_awaddr_o(s0_awaddr), .s0_awvalid_o(s0_awvalid), .s0_awready_i(s0_awready),
      .s0_wdata_o(s0_wdata), .s0_wstrb_o(s0_wstrb), .s0_wvalid_o(s0_wvalid), .s0_wready_i(s0_wready),
      .s0_bresp_i(s0_bresp), .s0_bvalid_i(s0_bvalid), .s0_bready_o(s0_bready),
      .s0_araddr_o(s0_araddr), .s0_arvalid_o(s0_arvalid), .s0_arready_i(s0_arready),
      .s0_rdata_i(s0_rdata), .s0_rresp_i(s0_rresp), .s0_rvalid_i(s0_rvalid), .s0_rready_o(s0_rready),
      .s1_awaddr_o(s1_awaddr), .s1_awvalid_o(s1_awvalid), .s1_awready_i(s1_awready),
      .s1_wdata_o(s1_wdata), .s1_wstrb_o(s1_wstrb), .s1_wvalid_o(s1_wvalid), .s1_wready_i(s1_wready),
      .s1_bresp_i(s1_bresp), .s1_bvalid_i(s1_bvalid), .s1_bready_o(s1_bready),
      .s1_araddr_o(s1_araddr), .s1_arvalid_o(s1_arvalid), .s1_arready_i(s1_arready),
      .s1_rdata_i(s1_rdata), .s1_rresp_i(s1_rresp), .s1_rvalid_i(s1_rvalid), .s1_rready_o(s1_rready),
      .s2_awaddr_o(s2_awaddr), .s2_awvalid_o(s2_awvalid), .s2_awready_i(s2_awready),
      .s2_wdata_o(s2_wdata), .s2_wstrb_o(s2_wstrb), .s2_wvalid_o(s2_wvalid), .s2_wready_i(s2_wready),
      .s2_bresp_i(s2_bresp), .s2_bvalid_i(s2_bvalid), .s2_bready_o(s2_bready),
      .s2_araddr_o(s2_araddr), .s2_arvalid_o(s2_arvalid), .s2_arready_i(s2_arready),
      .s2_rdata_i(s2_rdata), .s2_rresp_i(s2_rresp), .s2_rvalid_i(s2_rvalid), .s2_rready_o(s2_rready)
  );

  axi_lite_ram #(.DEPTH_WORDS(1024)) u_ram (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .s_awaddr_i(s0_awaddr), .s_awvalid_i(s0_awvalid), .s_awready_o(s0_awready),
      .s_wdata_i(s0_wdata), .s_wstrb_i(s0_wstrb), .s_wvalid_i(s0_wvalid), .s_wready_o(s0_wready),
      .s_bresp_o(s0_bresp), .s_bvalid_o(s0_bvalid), .s_bready_i(s0_bready),
      .s_araddr_i(s0_araddr), .s_arvalid_i(s0_arvalid), .s_arready_o(s0_arready),
      .s_rdata_o(s0_rdata), .s_rresp_o(s0_rresp), .s_rvalid_o(s0_rvalid), .s_rready_i(s0_rready)
  );

  axi_lite_gpio #(.WIDTH(GPIO_WIDTH)) u_gpio (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .gpio_o(led_o),
      .s_awaddr_i(s1_awaddr), .s_awvalid_i(s1_awvalid), .s_awready_o(s1_awready),
      .s_wdata_i(s1_wdata), .s_wstrb_i(s1_wstrb), .s_wvalid_i(s1_wvalid), .s_wready_o(s1_wready),
      .s_bresp_o(s1_bresp), .s_bvalid_o(s1_bvalid), .s_bready_i(s1_bready),
      .s_araddr_i(s1_araddr), .s_arvalid_i(s1_arvalid), .s_arready_o(s1_arready),
      .s_rdata_o(s1_rdata), .s_rresp_o(s1_rresp), .s_rvalid_o(s1_rvalid), .s_rready_i(s1_rready)
  );

  axi_lite_uart #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .uart_tx_o(uart_tx_o),
      .s_awaddr_i(s2_awaddr), .s_awvalid_i(s2_awvalid), .s_awready_o(s2_awready),
      .s_wdata_i(s2_wdata), .s_wstrb_i(s2_wstrb), .s_wvalid_i(s2_wvalid), .s_wready_o(s2_wready),
      .s_bresp_o(s2_bresp), .s_bvalid_o(s2_bvalid), .s_bready_i(s2_bready),
      .s_araddr_i(s2_araddr), .s_arvalid_i(s2_arvalid), .s_arready_o(s2_arready),
      .s_rdata_o(s2_rdata), .s_rresp_o(s2_rresp), .s_rvalid_o(s2_rvalid), .s_rready_i(s2_rready)
  );

endmodule
