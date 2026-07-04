// ============================================================================
// regfile.sv — RV32I Register File
// ----------------------------------------------------------------------------
// Purpose:
//   32 general-purpose registers (x0..x31), each 32 bits wide.
//   RISC-V instructions read up to two registers (rs1, rs2) and write one
//   (rd) per instruction, hence: two read ports, one write port.
//
// The x0 rule:
//   Register x0 is hard-wired to zero in RISC-V. Writes to x0 are silently
//   discarded and reads always return 0. Software relies on this constantly
//   (e.g. "mv a0, a1" is really "addi a0, a1, 0"; comparisons against zero
//   use x0), so this behavior is enforced in hardware here, not left to
//   software convention.
//
// Interface:
//   clk_i     : clock, writes happen on rising edge
//   we_i      : write enable
//   waddr_i   : destination register index (rd)
//   wdata_i   : data to write
//   raddr_a_i : read port A index (rs1)   -> rdata_a_o (combinational)
//   raddr_b_i : read port B index (rs2)   -> rdata_b_o (combinational)
//
// Timing:
//   Reads are combinational: change the address, the data appears within the
//   same cycle. Writes are synchronous. If you read and write the same
//   register in the same cycle, the read returns the OLD value (the new one
//   is visible after the clock edge). The single-cycle core never hits this
//   case; a pipelined core will need forwarding — noted for later.
//
// Note on reset:
//   The register array is intentionally not reset. RISC-V does not define
//   register values at reset (except x0) and real cores don't reset the file;
//   software initializes what it needs. This also maps better to FPGA BRAM.
// ============================================================================

module regfile (
    input  logic        clk_i,
    // write port
    input  logic        we_i,
    input  logic [4:0]  waddr_i,
    input  logic [31:0] wdata_i,
    // read port A (rs1)
    input  logic [4:0]  raddr_a_i,
    output logic [31:0] rdata_a_o,
    // read port B (rs2)
    input  logic [4:0]  raddr_b_i,
    output logic [31:0] rdata_b_o
);

  // 31 real registers; x0 is not stored, it is synthesized as constant 0
  logic [31:0] regs[1:31];

  // ---- synchronous write (x0 writes discarded) -----------------------------
  always_ff @(posedge clk_i) begin
    if (we_i && (waddr_i != 5'd0)) begin
      regs[waddr_i] <= wdata_i;
    end
  end

  // ---- combinational reads (x0 reads as zero) -------------------------------
  assign rdata_a_o = (raddr_a_i == 5'd0) ? 32'd0 : regs[raddr_a_i];
  assign rdata_b_o = (raddr_b_i == 5'd0) ? 32'd0 : regs[raddr_b_i];

endmodule
