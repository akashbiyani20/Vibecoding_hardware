// ============================================================================
// core_top.sv — Single-cycle RV32I CPU core
// ----------------------------------------------------------------------------
// Purpose:
//   Wires the five verified leaf modules (pc, control, imm_gen, regfile, alu)
//   into a working CPU, plus the small amount of glue logic that belongs to
//   the integration itself:
//     - operand select muxes (what feeds the ALU)
//     - write-back mux      (what goes into rd)
//     - next-PC logic       (sequential / branch / jump)
//
// One instruction = one clock cycle. Within a single cycle, combinationally:
//
//    pc_q --> imem (outside) --> instr
//                                  |
//              +---------+---------+----------+
//              v         v                    v
//           control   imm_gen             regfile read
//              |         |                    |
//              +---- operand muxes (op_a, op_b)--+
//                        v
//                       alu ------> dmem addr / branch decision
//                        |
//                   write-back mux --> regfile write (at clock edge)
//
// Memory interfaces:
//   Instruction side: imem_addr_o/imem_rdata_i — combinational fetch.
//   Data side: simple valid-style interface (addr/wdata/we/re/rdata).
//   In Stage C the data side gets wrapped by an AXI4-Lite master; keeping
//   the core itself bus-agnostic is standard practice (compare Ibex's
//   internal interface vs its bus wrapper).
//
// The interesting glue logic (understand these three):
//   1. Branch decision:  taken = branch & (alu_zero ^ funct3[0])
//      BEQ (funct3=000): ALU computes rs1-rs2, take if result IS zero.
//      BNE (funct3=001): same subtraction, take if result is NOT zero.
//      The XOR with funct3[0] flips the meaning — one gate, two instructions.
//   2. Two target sources:
//      Branches and JAL jump relative to the CURRENT instruction: PC + imm
//      (dedicated adder). JALR jumps to rs1 + imm — already computed by the
//      ALU this cycle — with bit 0 cleared, as the spec requires.
//   3. Write-back sources: ALU result (most ops), data memory (LW), or
//      PC+4 (JAL/JALR store the return address in rd).
// ============================================================================

`include "riscv_defines.svh"

module core_top (
    input  logic        clk_i,
    input  logic        rst_ni,

    // Stall: freezes the whole core mid-instruction. Asserted by the bus
    // bridge while an AXI data transaction is in flight (memory answers
    // take multiple cycles on a real bus). While stalled, the PC holds and
    // no register is written, so the instruction simply stretches in time.
    input  logic        stall_i,

    // instruction fetch interface
    output logic [31:0] imem_addr_o,
    input  logic [31:0] imem_rdata_i,

    // data memory interface (wrapped by the AXI4-Lite master bridge)
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_wstrb_o,   // byte lanes (LSU-generated)
    output logic        dmem_we_o,
    output logic        dmem_re_o,
    input  logic [31:0] dmem_rdata_i,

    // status (debug / future trap handling)
    output logic        illegal_o      // unsupported instr OR misaligned access
);

  // ---- signals ---------------------------------------------------------------
  logic [31:0] pc_q, pc_next, pc_plus4, pc_target;
  logic [31:0] instr;
  logic [31:0] imm;
  logic [31:0] rs1_data, rs2_data, wb_data;
  logic [31:0] alu_a, alu_b, alu_result;
  logic        alu_zero;
  logic        branch_taken;

  // control signals
  logic [31:0] load_data;
  logic        misaligned, ctrl_illegal;
  logic [2:0]  imm_sel;
  logic [3:0]  alu_op;
  logic [1:0]  op_a_sel, wb_sel;
  logic        op_b_sel, reg_write, mem_read, mem_write;
  logic        branch, jump, jump_reg;

  // ---- fetch -------------------------------------------------------------------
  assign imem_addr_o = pc_q;
  assign instr       = imem_rdata_i;

  pc u_pc (
      .clk_i    (clk_i),
      .rst_ni   (rst_ni),
      .en_i     (~stall_i),    // hold the PC while the bus is busy
      .pc_next_i(pc_next),
      .pc_o     (pc_q)
  );

  // ---- decode --------------------------------------------------------------------
  control u_control (
      .instr_i    (instr),
      .imm_sel_o  (imm_sel),
      .alu_op_o   (alu_op),
      .op_a_sel_o (op_a_sel),
      .op_b_sel_o (op_b_sel),
      .reg_write_o(reg_write),
      .wb_sel_o   (wb_sel),
      .mem_read_o (mem_read),
      .mem_write_o(mem_write),
      .branch_o   (branch),
      .jump_o     (jump),
      .jump_reg_o (jump_reg),
      .illegal_o  (ctrl_illegal)
  );

  imm_gen u_imm_gen (
      .instr_i  (instr),
      .imm_sel_i(imm_sel),
      .imm_o    (imm)
  );

  regfile u_regfile (
      .clk_i    (clk_i),
      .we_i     (reg_write & ~stall_i),  // don't write rd until the bus answers
      .waddr_i  (instr[11:7]),    // rd
      .wdata_i  (wb_data),
      .raddr_a_i(instr[19:15]),   // rs1
      .rdata_a_o(rs1_data),
      .raddr_b_i(instr[24:20]),   // rs2
      .rdata_b_o(rs2_data)
  );

  // ---- execute -----------------------------------------------------------------------
  // operand A: rs1 normally, PC for AUIPC, 0 for LUI
  always_comb begin
    unique case (op_a_sel)
      `OPA_RS1:  alu_a = rs1_data;
      `OPA_PC:   alu_a = pc_q;
      `OPA_ZERO: alu_a = 32'd0;
      default:   alu_a = rs1_data;
    endcase
  end

  // operand B: rs2 for R-type/branches, immediate otherwise
  assign alu_b = (op_b_sel == `OPB_IMM) ? imm : rs2_data;

  alu u_alu (
      .a_i     (alu_a),
      .b_i     (alu_b),
      .op_i    (alu_op),
      .result_o(alu_result),
      .zero_o  (alu_zero)
  );

  // ---- data memory (through the load-store unit) ------------------------------------------
  // The LSU handles byte/halfword placement (stores) and extraction with
  // sign/zero extension (loads). funct3 = instr[14:12] tells it the size.
  lsu u_lsu (
      .addr_i      (alu_result),
      .funct3_i    (instr[14:12]),
      .store_data_i(rs2_data),
      .wdata_o     (dmem_wdata_o),
      .wstrb_o     (dmem_wstrb_o),
      .rdata_i     (dmem_rdata_i),
      .load_data_o (load_data),
      .misaligned_o(misaligned)
  );

  assign dmem_addr_o = alu_result;    // load/store address = rs1 + imm
  assign dmem_we_o   = mem_write;
  assign dmem_re_o   = mem_read;

  // ---- write-back --------------------------------------------------------------------------
  always_comb begin
    unique case (wb_sel)
      `WB_ALU: wb_data = alu_result;
      `WB_MEM: wb_data = load_data;    // LSU-extracted (LB/LH/LW/LBU/LHU)
      `WB_PC4: wb_data = pc_plus4;     // JAL/JALR link address
      default: wb_data = alu_result;
    endcase
  end

  // ---- next-PC logic ------------------------------------------------------------------------
  assign pc_plus4     = pc_q + 32'd4;
  assign pc_target    = pc_q + imm;                          // branches, JAL

  // Branch condition, all six branches with one mux and one XOR:
  //   BEQ/BNE  (funct3=00x): ALU did SUB   -> condition = zero flag
  //   BLT/BGE  (funct3=10x): ALU did SLT   -> condition = result bit 0
  //   BLTU/BGEU(funct3=11x): ALU did SLTU  -> condition = result bit 0
  //   funct3[0]=1 (BNE/BGE/BGEU) inverts the sense.
  logic branch_cond;
  assign branch_cond  = instr[14] ? alu_result[0] : alu_zero;
  assign branch_taken = branch & (branch_cond ^ instr[12]);

  // misaligned memory access is reported like an illegal instruction:
  // loud failure in simulation, trap material on real hardware
  assign illegal_o = ctrl_illegal | ((mem_read | mem_write) & misaligned);

  assign pc_next = jump_reg                ? {alu_result[31:1], 1'b0}  // JALR
                 : (jump | branch_taken)   ? pc_target                 // JAL, taken branch
                 :                           pc_plus4;                 // sequential

endmodule
