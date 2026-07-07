// ============================================================================
// lsu.sv — Load-Store Unit (byte / halfword / word alignment)
// ----------------------------------------------------------------------------
// Purpose:
//   The bus always moves 32-bit words, but C code constantly works with
//   bytes (char, strings) and halfwords (short). This unit translates:
//
//   STORES: place the small value into the right byte lane(s) of the
//     32-bit word and set wstrb so the memory only writes those lanes.
//     Example: SB to address ...01 -> data goes to bits [15:8], wstrb=0010.
//
//   LOADS: the bus returns the whole 32-bit word containing the target;
//     pick out the right byte/halfword using addr[1:0] and extend it to
//     32 bits — sign-extended (LB/LH: a char -1 must stay -1) or
//     zero-extended (LBU/LHU: an unsigned char 0xFF must become 255).
//
//   funct3 encodes size and signedness, straight from the instruction:
//     000 LB/SB   001 LH/SH   010 LW/SW   100 LBU   101 LHU
//     (bit1:0 = size, bit2 = unsigned load)
//
//   misaligned_o flags accesses that straddle a word boundary (LW at a
//   non-multiple-of-4, LH at an odd address). RV32I allows trapping on
//   these; we flag them like an illegal instruction so firmware bugs are
//   caught loudly instead of corrupting data silently.
//
// Timing: purely combinational, sits between the ALU (address) and the
//   data-bus port.
// ============================================================================

module lsu (
    // from the instruction / datapath
    input  logic [31:0] addr_i,        // byte address (ALU result)
    input  logic [2:0]  funct3_i,      // size + signedness
    input  logic [31:0] store_data_i,  // rs2, the value to store
    // to the bus (stores)
    output logic [31:0] wdata_o,       // value shifted into its byte lane
    output logic [3:0]  wstrb_o,       // which byte lanes to write
    // from the bus (loads)
    input  logic [31:0] rdata_i,       // full word from memory
    output logic [31:0] load_data_o,   // extracted + extended result
    // error
    output logic        misaligned_o
);

  logic [1:0] off;
  assign off = addr_i[1:0];

  // ---- store path: shift data into lane, build strobes -----------------------
  always_comb begin
    unique case (funct3_i[1:0])
      2'b00: begin                                   // SB
        wdata_o = {4{store_data_i[7:0]}};            // replicate to all lanes
        wstrb_o = 4'b0001 << off;                    // enable just one
      end
      2'b01: begin                                   // SH
        wdata_o = {2{store_data_i[15:0]}};
        wstrb_o = off[1] ? 4'b1100 : 4'b0011;
      end
      default: begin                                 // SW
        wdata_o = store_data_i;
        wstrb_o = 4'b1111;
      end
    endcase
  end
  // (replication trick: putting the byte in every lane means the strobe
  //  alone decides where it lands — no per-lane shifter needed)

  // ---- load path: extract, then extend ------------------------------------------
  logic [7:0]  byte_sel;
  logic [15:0] half_sel;

  always_comb begin
    unique case (off)
      2'b00: byte_sel = rdata_i[7:0];
      2'b01: byte_sel = rdata_i[15:8];
      2'b10: byte_sel = rdata_i[23:16];
      2'b11: byte_sel = rdata_i[31:24];
    endcase
  end
  assign half_sel = off[1] ? rdata_i[31:16] : rdata_i[15:0];

  always_comb begin
    unique case (funct3_i)
      3'b000:  load_data_o = {{24{byte_sel[7]}},  byte_sel};   // LB  (signed)
      3'b100:  load_data_o = {24'd0,              byte_sel};   // LBU
      3'b001:  load_data_o = {{16{half_sel[15]}}, half_sel};   // LH  (signed)
      3'b101:  load_data_o = {16'd0,              half_sel};   // LHU
      default: load_data_o = rdata_i;                          // LW
    endcase
  end

  // ---- alignment check ---------------------------------------------------------------
  always_comb begin
    unique case (funct3_i[1:0])
      2'b01:   misaligned_o = off[0];          // halfword: odd address
      2'b10:   misaligned_o = (off != 2'b00);  // word: must be 4-aligned
      default: misaligned_o = 1'b0;            // byte: always aligned
    endcase
  end

endmodule
