// ============================================================================
// axi_lite_gpio.sv — GPIO peripheral (AXI4-Lite slave)
// ----------------------------------------------------------------------------
// Purpose:
//   The simplest possible peripheral: a register the CPU can write whose
//   bits drive physical pins (LEDs). Writing 1 to bit 0 turns LED 0 on.
//   This is the moment software touches the physical world.
//
// Register map (offsets from GPIO base 0x1000_0000):
//   0x00  GPIO_OUT  R/W   bit N drives gpio_o[N]; reads return current value
//   0x04  (reserved for GPIO_IN — switches — a future extension)
//
// Bus interface: identical handshake pattern to axi_lite_ram — accept AW+W
//   together, respond with B; register the read data, respond with R.
//   Unmapped offsets read as 0 and writes to them are ignored (harmless).
// ============================================================================

module axi_lite_gpio #(
    parameter int WIDTH = 8
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // physical pins
    output logic [WIDTH-1:0] gpio_o,

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

  // ---- write path ---------------------------------------------------------------
  logic wr_fire;
  assign wr_fire     = s_awvalid_i & s_wvalid_i & ~s_bvalid_o;
  assign s_awready_o = wr_fire;
  assign s_wready_o  = wr_fire;
  assign s_bresp_o   = 2'b00;  // OKAY

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s_bvalid_o <= 1'b0;
      gpio_o     <= '0;        // LEDs off at reset — a deliberate choice
    end else begin
      if (wr_fire) begin
        if (s_awaddr_i[3:0] == 4'h0 && s_wstrb_i[0])
          gpio_o <= s_wdata_i[WIDTH-1:0];
        s_bvalid_o <= 1'b1;
      end else if (s_bready_i) begin
        s_bvalid_o <= 1'b0;
      end
    end
  end

  // ---- read path -------------------------------------------------------------------
  logic rd_fire;
  assign rd_fire     = s_arvalid_i & s_arready_o;
  assign s_arready_o = ~s_rvalid_o;
  assign s_rresp_o   = 2'b00;  // OKAY

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s_rvalid_o <= 1'b0;
      s_rdata_o  <= 32'd0;
    end else begin
      if (rd_fire) begin
        s_rdata_o  <= (s_araddr_i[3:0] == 4'h0) ? {{(32-WIDTH){1'b0}}, gpio_o}
                                                : 32'd0;
        s_rvalid_o <= 1'b1;
      end else if (s_rready_i) begin
        s_rvalid_o <= 1'b0;
      end
    end
  end

endmodule
