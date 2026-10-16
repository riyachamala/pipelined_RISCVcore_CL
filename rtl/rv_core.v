`include "rv_defines.vh"

// 5-stage in-order RV32IM pipeline: IF -> ID -> EX -> MEM -> WB
//
//  * Full forwarding MEM->EX and WB->EX; WB->ID through the register file.
//  * One-cycle load-use stall.
//  * Single-cycle multiplier; iterative divider that stalls EX (~33 cycles).
//  * BTB + 2-bit counter prediction in IF; resolution and redirect in EX
//    (2-cycle mispredict penalty).
//  * Traps (ecall/ebreak/illegal/timer IRQ), mret and fence.i are handled
//    in EX, so every older instruction has already left the trap window and
//    exceptions are precise.
module rv_core #(
    parameter RESET_PC     = `RESET_PC,
    parameter BTB_ENTRIES_LOG2 = 6,
    parameter RV32M            = 1     // include the M extension
) (
    input  wire        clk,
    input  wire        rst,

    // Instruction memory (combinational read)
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // Data memory (combinational read, synchronous write)
    output wire [31:0] dmem_addr,
    output wire        dmem_re,
    output wire        dmem_we,
    output wire [3:0]  dmem_wstrb,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,

    // Interrupts / time
    input  wire        timer_irq,
    input  wire [63:0] mtime,

    // Retirement trace (for the testbench)
    output wire        retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_instr,
    output wire        retire_rd_we,
    output wire [4:0]  retire_rd,
    output wire [31:0] retire_rd_data
);
    // =====================================================================
    // Forward declarations of cross-stage signals
    // =====================================================================
    wire        stall_if, stall_id, stall_ex, flush_id, flush_ex;
    wire        ex_redirect;
    wire        ex_trap;
    wire [31:0] ex_redirect_pc;

    // =====================================================================
    // IF
    // =====================================================================
    reg  [31:0] if_pc;
    wire        if_pred_taken;
    wire [31:0] if_pred_target;

    assign imem_addr = if_pc;

    wire [31:0] if_pc_next = ex_redirect   ? ex_redirect_pc :
                             stall_if      ? if_pc          :
                             if_pred_taken ? if_pred_target :
                                             if_pc + 32'd4;

    always @(posedge clk) begin
        if (rst) if_pc <= RESET_PC;
        else     if_pc <= if_pc_next;
    end

    // ---------------------------------------------------------------- IF/ID
    reg        id_valid;
    reg [31:0] id_pc;
    reg [31:0] id_instr;
    reg        id_pred_taken;
    reg [31:0] id_pred_target;

    always @(posedge clk) begin
        if (rst || flush_id) begin
            id_valid <= 1'b0;
            id_instr <= `NOP_INSTR;
        end else if (!stall_id) begin
            id_valid       <= 1'b1;
            id_pc          <= if_pc;
            id_instr       <= imem_rdata;
            id_pred_taken  <= if_pred_taken;
            id_pred_target <= if_pred_target;
        end
    end

    // =====================================================================
    // ID
    // =====================================================================
    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [2:0]  id_funct3, id_imm_type;
    wire [3:0]  id_alu_op;
    wire [1:0]  id_src_a_sel, id_wb_sel;
    wire        id_src_b_sel, id_reg_write, id_uses_rs1, id_uses_rs2;
    wire        id_mem_read, id_mem_write;
    wire        id_is_branch, id_is_jal, id_is_jalr, id_is_mul, id_is_div;
    wire        id_is_csr, id_is_ecall, id_is_ebreak, id_is_mret, id_is_fence_i;
    wire        id_illegal;
    wire [31:0] id_imm, id_rs1_data, id_rs2_data;

    rv_decoder #(.RV32M(RV32M)) u_decoder (
        .instr      (id_instr),
        .rs1        (id_rs1),
        .rs2        (id_rs2),
        .rd         (id_rd),
        .funct3     (id_funct3),
        .imm_type   (id_imm_type),
        .alu_op     (id_alu_op),
        .src_a_sel  (id_src_a_sel),
        .src_b_sel  (id_src_b_sel),
        .wb_sel     (id_wb_sel),
        .reg_write  (id_reg_write),
        .uses_rs1   (id_uses_rs1),
        .uses_rs2   (id_uses_rs2),
        .mem_read   (id_mem_read),
        .mem_write  (id_mem_write),
        .is_branch  (id_is_branch),
        .is_jal     (id_is_jal),
        .is_jalr    (id_is_jalr),
        .is_mul     (id_is_mul),
        .is_div     (id_is_div),
        .is_csr     (id_is_csr),
        .is_ecall   (id_is_ecall),
        .is_ebreak  (id_is_ebreak),
        .is_mret    (id_is_mret),
        .is_fence_i (id_is_fence_i),
        .illegal    (id_illegal)
    );

    rv_imm_gen u_imm_gen (
        .instr    (id_instr),
        .imm_type (id_imm_type),
        .imm      (id_imm)
    );

    // WB-stage signals feed the register file write port
    reg        wb_valid;
    reg        wb_reg_write;
    reg [4:0]  wb_rd;
    reg [31:0] wb_data;
    reg [31:0] wb_pc;
    reg [31:0] wb_instr;

    wire wb_rf_we = wb_valid && wb_reg_write;

    rv_regfile u_regfile (
        .clk      (clk),
        .rs1_addr (id_rs1),
        .rs2_addr (id_rs2),
        .rs1_data (id_rs1_data),
        .rs2_data (id_rs2_data),
        .we       (wb_rf_we),
        .rd_addr  (wb_rd),
        .rd_data  (wb_data)
    );

    // ---------------------------------------------------------------- ID/EX
    reg        ex_valid;
    reg [31:0] ex_pc, ex_instr, ex_imm, ex_rs1_data, ex_rs2_data;
    reg [4:0]  ex_rs1, ex_rs2, ex_rd;
    reg [2:0]  ex_funct3;
    reg [3:0]  ex_alu_op;
    reg [1:0]  ex_src_a_sel, ex_wb_sel;
    reg        ex_src_b_sel, ex_reg_write, ex_mem_read, ex_mem_write;
    reg        ex_is_branch, ex_is_jal, ex_is_jalr, ex_is_mul, ex_is_div;
    reg        ex_is_csr, ex_is_ecall, ex_is_ebreak, ex_is_mret, ex_is_fence_i;
    reg        ex_illegal;
    reg        ex_pred_taken;
    reg [31:0] ex_pred_target;

    always @(posedge clk) begin
        if (rst || flush_ex) begin
            ex_valid     <= 1'b0;
            ex_mem_read  <= 1'b0;
            ex_instr     <= `NOP_INSTR;
        end else if (!stall_ex) begin
            ex_valid       <= id_valid;
            ex_pc          <= id_pc;
            ex_instr       <= id_instr;
            ex_imm         <= id_imm;
            ex_rs1_data    <= id_rs1_data;
            ex_rs2_data    <= id_rs2_data;
            // Only track source registers that are actually read, so that
            // forwarding / hazard logic ignores garbage fields.
            ex_rs1         <= id_uses_rs1 ? id_rs1 : 5'd0;
            ex_rs2         <= id_uses_rs2 ? id_rs2 : 5'd0;
            ex_rd          <= id_rd;
            ex_funct3      <= id_funct3;
            ex_alu_op      <= id_alu_op;
            ex_src_a_sel   <= id_src_a_sel;
            ex_src_b_sel   <= id_src_b_sel;
            ex_wb_sel      <= id_wb_sel;
            ex_reg_write   <= id_reg_write && (id_rd != 5'd0);
            ex_mem_read    <= id_mem_read;
            ex_mem_write   <= id_mem_write;
            ex_is_branch   <= id_is_branch;
            ex_is_jal      <= id_is_jal;
            ex_is_jalr     <= id_is_jalr;
            ex_is_mul      <= id_is_mul;
            ex_is_div      <= id_is_div;
            ex_is_csr      <= id_is_csr;
            ex_is_ecall    <= id_is_ecall;
            ex_is_ebreak   <= id_is_ebreak;
            ex_is_mret     <= id_is_mret;
            ex_is_fence_i  <= id_is_fence_i;
            ex_illegal     <= id_illegal;
            ex_pred_taken  <= id_pred_taken;
            ex_pred_target <= id_pred_target;
        end
    end

    // =====================================================================
    // EX
    // =====================================================================
    // EX/MEM registers declared early for forwarding
    reg        mem_valid;
    reg        mem_reg_write, mem_mem_read, mem_mem_write;
    reg [4:0]  mem_rd;
    reg [2:0]  mem_funct3;
    reg [31:0] mem_result, mem_store_data, mem_pc, mem_instr;

    wire [1:0] fwd_a, fwd_b;

    rv_forward_unit u_forward (
        .ex_rs1        (ex_rs1),
        .ex_rs2        (ex_rs2),
        .mem_valid     (mem_valid),
        .mem_reg_write (mem_reg_write),
        .mem_rd        (mem_rd),
        .wb_valid      (wb_valid),
        .wb_reg_write  (wb_reg_write),
        .wb_rd         (wb_rd),
        .fwd_a         (fwd_a),
        .fwd_b         (fwd_b)
    );

    wire [31:0] ex_rs1_val = (fwd_a == 2'b01) ? mem_result :
                             (fwd_a == 2'b10) ? wb_data    : ex_rs1_data;
    wire [31:0] ex_rs2_val = (fwd_b == 2'b01) ? mem_result :
                             (fwd_b == 2'b10) ? wb_data    : ex_rs2_data;

    wire [31:0] alu_a = (ex_src_a_sel == `SRCA_PC)   ? ex_pc :
                        (ex_src_a_sel == `SRCA_ZERO) ? 32'd0 : ex_rs1_val;
    wire [31:0] alu_b = (ex_src_b_sel == `SRCB_IMM)  ? ex_imm : ex_rs2_val;
    wire [31:0] alu_y;

    rv_alu u_alu (
        .op (ex_alu_op),
        .a  (alu_a),
        .b  (alu_b),
        .y  (alu_y)
    );

    // ---------------------------------------------------------------- M extension
    wire [31:0] mul_y, div_y;
    wire        div_busy;

    rv_mul u_mul (
        .op (ex_funct3[1:0]),
        .a  (ex_rs1_val),
        .b  (ex_rs2_val),
        .y  (mul_y)
    );

    rv_div u_div (
        .clk    (clk),
        .rst    (rst),
        .req    (ex_valid && ex_is_div),
        .kill   (ex_trap),
        .op     (ex_funct3[1:0]),
        .a      (ex_rs1_val),
        .b      (ex_rs2_val),
        .busy   (div_busy),
        .result (div_y)
    );

    // EX holds (and stalls everything behind it) while a divide runs.
    wire ex_busy = div_busy;

    // ---------------------------------------------------------------- branch resolution
    wire ex_br_cond;
    rv_branch_unit u_branch (
        .funct3 (ex_funct3),
        .a      (ex_rs1_val),
        .b      (ex_rs2_val),
        .taken  (ex_br_cond)
    );

    wire [31:0] ex_pc4         = ex_pc + 32'd4;
    wire        ex_is_cf       = ex_is_branch || ex_is_jal || ex_is_jalr;
    wire        ex_taken       = ex_is_jal || ex_is_jalr || (ex_is_branch && ex_br_cond);
    wire [31:0] ex_jalr_target = (ex_rs1_val + ex_imm) & ~32'd1;
    wire [31:0] ex_target      = ex_is_jalr ? ex_jalr_target : ex_pc + ex_imm;
    wire        ex_mispredict  = ex_taken ? !(ex_pred_taken && ex_pred_target == ex_target)
                                          : ex_pred_taken;

    // ---------------------------------------------------------------- traps / CSRs
    wire [31:0] csr_rdata, mtvec, mepc;
    wire        irq_pending;

    // Misaligned accesses trap (no hardware misaligned support). The
    // effective address is the ALU result for loads and stores.
    wire        ex_half_mis   = (ex_funct3[1:0] == 2'b01) && alu_y[0];
    wire        ex_word_mis   = (ex_funct3[1:0] == 2'b10) && (alu_y[1:0] != 2'b00);
    wire        ex_ld_mis     = ex_mem_read  && (ex_half_mis || ex_word_mis);
    wire        ex_st_mis     = ex_mem_write && (ex_half_mis || ex_word_mis);
    // Taken jump/branch to a non-word-aligned target (no C extension).
    wire        ex_fetch_mis  = ex_taken && (ex_target[1:0] != 2'b00);

    wire        ex_take_irq  = ex_valid && irq_pending;
    wire        ex_take_exc  = ex_valid && !irq_pending &&
                               (ex_illegal || ex_is_ecall || ex_is_ebreak ||
                                ex_ld_mis || ex_st_mis || ex_fetch_mis);
    assign      ex_trap      = ex_take_irq || ex_take_exc;
    wire [31:0] ex_trap_cause = ex_take_irq  ? `CAUSE_M_TIMER_IRQ        :
                                ex_illegal   ? `CAUSE_ILLEGAL_INSTR      :
                                ex_is_ebreak ? `CAUSE_BREAKPOINT         :
                                ex_is_ecall  ? `CAUSE_ECALL_M            :
                                ex_ld_mis    ? `CAUSE_LOAD_MISALIGNED    :
                                ex_st_mis    ? `CAUSE_STORE_MISALIGNED   :
                                               `CAUSE_FETCH_MISALIGNED;
    wire [31:0] ex_trap_val   = ex_take_irq               ? 32'd0     :
                                ex_illegal                ? ex_instr  :
                                ex_is_ebreak              ? ex_pc     :
                                (ex_ld_mis || ex_st_mis)  ? alu_y     :
                                ex_fetch_mis              ? ex_target : 32'd0;
    wire [31:0] ex_trap_vector = (mtvec[0] && ex_take_irq)
                               ? {mtvec[31:2], 2'b00} + {ex_trap_cause[29:0], 2'b00}
                               : {mtvec[31:2], 2'b00};

    wire ex_do_mret    = ex_valid && !ex_trap && ex_is_mret;
    wire ex_do_fence_i = ex_valid && !ex_trap && ex_is_fence_i;
    wire ex_do_csr     = ex_valid && !ex_trap && ex_is_csr;

    // A busy divide can be falsely "predicted taken" by BTB aliasing; defer
    // that fix-up to its final cycle so the divide is not dropped.
    assign ex_redirect    = ex_trap || ex_do_mret || ex_do_fence_i ||
                            (ex_valid && ex_mispredict && !ex_busy);
    assign ex_redirect_pc = ex_trap       ? ex_trap_vector :
                            ex_do_mret    ? mepc           :
                            ex_do_fence_i ? ex_pc4         :
                            ex_taken      ? ex_target      : ex_pc4;

    // CSRR*I: zimm lives in the rs1 field (ex_rs1 is zeroed for these).
    wire [31:0] csr_operand = ex_funct3[2] ? {27'd0, ex_instr[19:15]} : ex_rs1_val;

    rv_csr #(.MISA(RV32M ? 32'h4000_1100 : 32'h4000_0100)) u_csr (
        .clk              (clk),
        .rst              (rst),
        .csr_en           (ex_do_csr),
        .csr_funct3       (ex_funct3),
        .csr_addr         (ex_instr[31:20]),
        .csr_operand      (csr_operand),
        .csr_operand_zero (ex_instr[19:15] == 5'd0),
        .csr_rdata        (csr_rdata),
        .trap_take        (ex_trap),
        .trap_cause       (ex_trap_cause),
        .trap_pc          (ex_pc),
        .trap_val         (ex_trap_val),
        .mret             (ex_do_mret),
        // Count at EX: nothing past EX can trap, so leaving EX means retiring.
        .instret_inc      (ex_valid && !ex_trap && !ex_busy),
        .mtime            (mtime),
        .timer_irq        (timer_irq),
        .mtvec_o          (mtvec),
        .mepc_o           (mepc),
        .irq_pending      (irq_pending)
    );
    // ---------------------------------------------------------------- branch predictor
    rv_branch_predictor #(.ENTRIES_LOG2(BTB_ENTRIES_LOG2)) u_bp (
        .clk         (clk),
        .rst         (rst),
        .if_pc       (if_pc),
        .pred_taken  (if_pred_taken),
        .pred_target (if_pred_target),
        .upd_valid   (ex_valid && ex_is_cf && !ex_trap),
        .upd_pc      (ex_pc),
        .upd_taken   (ex_taken),
        .upd_target  (ex_target)
    );

    // ---------------------------------------------------------------- hazards
    rv_hazard_unit u_hazard (
        .id_valid    (id_valid),
        .id_rs1      (id_rs1),
        .id_rs2      (id_rs2),
        .id_uses_rs1 (id_uses_rs1),
        .id_uses_rs2 (id_uses_rs2),
        .ex_valid    (ex_valid),
        .ex_mem_read (ex_mem_read),
        .ex_rd       (ex_rd),
        .ex_redirect (ex_redirect),
        .ex_busy     (ex_busy),
        .stall_if    (stall_if),
        .stall_id    (stall_id),
        .stall_ex    (stall_ex),
        .flush_id    (flush_id),
        .flush_ex    (flush_ex)
    );

    wire [31:0] ex_result = (ex_wb_sel == `WB_PC4) ? ex_pc4    :
                            (ex_wb_sel == `WB_CSR) ? csr_rdata :
                            ex_is_mul              ? mul_y     :
                            ex_is_div              ? div_y     : alu_y;

    // ---------------------------------------------------------------- EX/MEM
    always @(posedge clk) begin
        if (rst) begin
            mem_valid     <= 1'b0;
            mem_reg_write <= 1'b0;
            mem_mem_read  <= 1'b0;
            mem_mem_write <= 1'b0;
        end else begin
            mem_valid      <= ex_valid && !ex_trap && !ex_busy;
            mem_reg_write  <= ex_reg_write;
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
            mem_rd         <= ex_rd;
            mem_funct3     <= ex_funct3;
            mem_result     <= ex_result;
            mem_store_data <= ex_rs2_val;
            mem_pc         <= ex_pc;
            mem_instr      <= ex_instr;
        end
    end

    // =====================================================================
    // MEM
    // =====================================================================
    wire [31:0] mem_load_data;

    rv_lsu u_lsu (
        .funct3     (mem_funct3),
        .addr       (mem_result),
        .store_data (mem_store_data),
        .mem_rdata  (dmem_rdata),
        .mem_wdata  (dmem_wdata),
        .mem_wstrb  (dmem_wstrb),
        .load_data  (mem_load_data)
    );

    assign dmem_addr = mem_result;
    assign dmem_re   = mem_valid && mem_mem_read;
    assign dmem_we   = mem_valid && mem_mem_write;

    // ---------------------------------------------------------------- MEM/WB
    always @(posedge clk) begin
        if (rst) begin
            wb_valid     <= 1'b0;
            wb_reg_write <= 1'b0;
        end else begin
            wb_valid     <= mem_valid;
            wb_reg_write <= mem_reg_write;
            wb_rd        <= mem_rd;
            wb_data      <= mem_mem_read ? mem_load_data : mem_result;
            wb_pc        <= mem_pc;
            wb_instr     <= mem_instr;
        end
    end

    // =====================================================================
    // WB / retirement
    // =====================================================================
    assign retire_valid   = wb_valid;
    assign retire_pc      = wb_pc;
    assign retire_instr   = wb_instr;
    assign retire_rd_we   = wb_rf_we;
    assign retire_rd      = wb_rd;
    assign retire_rd_data = wb_data;
endmodule
