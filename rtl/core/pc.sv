// ============================================================================
// pc.sv — Program Counter
// ----------------------------------------------------------------------------
// Purpose:
//   Holds the address of the instruction currently being fetched.
//   On every clock edge (when enabled) it loads the next address, which the
//   surrounding next-PC logic computes as either PC+4 (sequential execution)
//   or a branch/jump target. Keeping the "what is next?" decision OUTSIDE
//   this module keeps it tiny and reusable.
//
// Interface:
//   clk_i      : clock, all state changes on rising edge
//   rst_ni     : asynchronous reset, active LOW (industry convention).
//                On reset the PC becomes RESET_PC (0x0000_0000).
//   en_i       : update enable. 1 = load pc_next_i on next edge,
//                0 = hold current value (future use: stalls). Tie to 1 for now.
//   pc_next_i  : the address to load next (PC+4, branch or jump target)
//   pc_o       : current program counter value
//
// Timing:
//   pc_o changes only on the rising clock edge (or async on reset).
//   There is no combinational path from pc_next_i to pc_o.
// ============================================================================

`include "riscv_defines.svh"

module pc (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        en_i,
    input  logic [31:0] pc_next_i,
    output logic [31:0] pc_o
);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_o <= `RESET_PC;
    end else if (en_i) begin
      pc_o <= pc_next_i;
    end
  end

endmodule
