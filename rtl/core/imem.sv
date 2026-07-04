// ============================================================================
// imem.sv — Instruction Memory (behavioral, Phase 1)
// ----------------------------------------------------------------------------
// Purpose:
//   Holds the program. The core presents a byte address (the PC) and gets the
//   32-bit instruction at that address back, combinationally — which is what
//   a single-cycle CPU needs (fetch and execute happen in the same cycle).
//
// Modeling choice:
//   A simple Verilog array initialized with $readmemh from a hex file
//   (one 32-bit word per line, as produced by sw/asm.py). On FPGA this
//   maps to block RAM / ROM later; the interface won't change.
//
// Addressing:
//   Instructions are 4 bytes, so byte address bits [1:0] are always 00 and
//   are ignored; the word index is addr[N+1:2]. With DEPTH_WORDS = 1024
//   this is a 4 KB memory — matching the memory map (0x0000_0000, 4 KB).
//
// Timing: purely combinational read (asynchronous ROM).
// ============================================================================

module imem #(
    parameter int          DEPTH_WORDS = 1024,       // 4 KB
    parameter              INIT_FILE   = ""          // hex program to load
) (
    input  logic [31:0] addr_i,    // byte address (the PC)
    output logic [31:0] rdata_o    // instruction at that address
);

  localparam int AW = $clog2(DEPTH_WORDS);

  logic [31:0] mem[0:DEPTH_WORDS-1];

  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  assign rdata_o = mem[addr_i[AW+1:2]];

endmodule
