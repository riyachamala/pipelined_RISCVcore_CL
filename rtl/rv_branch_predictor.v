`include "rv_defines.vh"

// Branch prediction unit, operating on the instruction being fetched.
//
// The fetched instruction is predecoded in IF, so direct targets are
// computed exactly and only indirect jumps need stored targets:
//
//   JAL               always taken, target = pc + immJ
//   Bxx (conditional) gshare: 2-bit counters indexed by pc ^ global history,
//                     target = pc + immB
//   JALR return       (rs1 = ra/t0, rd != link)   -> return address stack
//   other JALR        BTB (direct-mapped, tagged), else predict fall-through
//
// Speculation and repair: the global history (GHR) and RAS pointer are
// updated speculatively as instructions leave IF. Each instruction carries
// the GHR / RAS pointer seen *before* its own update. On a redirect from EX
// every younger instruction is squashed, so restoring the redirecting
// instruction's snapshot, plus its own effect if it executed, is exact
// (wrong-path RAS pushes can still clobber entries; that only costs accuracy).
module rv_branch_predictor #(
    parameter BTB_ENTRIES_LOG2 = 5,
    parameter PHT_ENTRIES_LOG2 = 12,
    parameter GHR_BITS         = 12,
    parameter RAS_DEPTH_LOG2   = 3
) (
    input  wire        clk,
    input  wire        rst,

    // IF: lookup and speculative update
    input  wire [31:0] if_pc,
    input  wire [31:0] if_instr,
    input  wire        if_advance,      // fetched instruction moves to ID
    output wire        pred_taken,
    output wire [31:0] pred_target,
    output wire [GHR_BITS-1:0]       pred_ghr,      // snapshot before this instr
    output wire [RAS_DEPTH_LOG2-1:0] pred_ras_ptr,  // snapshot before this instr

    // EX: redirect repair
    input  wire        ex_redirect,
    input  wire        ex_executed,     // redirecting instr completed (not a trap)
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_instr,
    input  wire        ex_taken,
    input  wire [GHR_BITS-1:0]       ex_ghr,
    input  wire [RAS_DEPTH_LOG2-1:0] ex_ras_ptr,

    // EX: training
    input  wire        upd_valid,       // resolved control-flow instruction
    input  wire [31:0] upd_target
);
    localparam BTB_ENTRIES = 1 << BTB_ENTRIES_LOG2;
    localparam PHT_ENTRIES = 1 << PHT_ENTRIES_LOG2;
    localparam RAS_DEPTH   = 1 << RAS_DEPTH_LOG2;
    localparam TAG_W       = 30 - BTB_ENTRIES_LOG2;

    // ------------------------------------------------------------ predecode
    function automatic is_link(input [4:0] r);
        is_link = (r == 5'd1) || (r == 5'd5);
    endfunction

    // Classify an instruction: {is_branch, is_jal, is_jalr, is_call, is_ret}
    function automatic [4:0] classify(input [31:0] instr);
        reg br, jal, jalr, call, ret;
        begin
            br   = instr[6:0] == `OP_BRANCH;
            jal  = instr[6:0] == `OP_JAL;
            jalr = instr[6:0] == `OP_JALR;
            call = (jal || jalr) && is_link(instr[11:7]);
            ret  = jalr && is_link(instr[19:15]) && !is_link(instr[11:7]);
            classify = {br, jal, jalr, call, ret};
        end
    endfunction

    wire if_br, if_jal, if_jalr, if_call, if_ret;
    assign {if_br, if_jal, if_jalr, if_call, if_ret} = classify(if_instr);

    wire ex_br, ex_jal, ex_jalr, ex_call, ex_ret;
    assign {ex_br, ex_jal, ex_jalr, ex_call, ex_ret} = classify(ex_instr);

    wire [31:0] imm_b = {{19{if_instr[31]}}, if_instr[31], if_instr[7],
                         if_instr[30:25], if_instr[11:8], 1'b0};
    wire [31:0] imm_j = {{11{if_instr[31]}}, if_instr[31], if_instr[19:12],
                         if_instr[20], if_instr[30:21], 1'b0};

    // ------------------------------------------------------------ state
    reg [GHR_BITS-1:0]       ghr;
    reg [1:0]                pht        [0:PHT_ENTRIES-1];
    reg [31:0]               ras        [0:RAS_DEPTH-1];
    reg [RAS_DEPTH_LOG2-1:0] ras_ptr;                    // next free slot
    reg                      btb_valid  [0:BTB_ENTRIES-1];
    reg [TAG_W-1:0]          btb_tag    [0:BTB_ENTRIES-1];
    reg [31:0]               btb_target [0:BTB_ENTRIES-1];

    function automatic [PHT_ENTRIES_LOG2-1:0] pht_index(input [31:0] pc, input [GHR_BITS-1:0] h);
        reg [PHT_ENTRIES_LOG2+GHR_BITS-1:0] hist;
        begin
            hist      = {{PHT_ENTRIES_LOG2{1'b0}}, h};
            pht_index = pc[PHT_ENTRIES_LOG2+1:2] ^ hist[PHT_ENTRIES_LOG2-1:0];
        end
    endfunction

    // ------------------------------------------------------------ lookup
    wire [BTB_ENTRIES_LOG2-1:0] btb_idx = if_pc[BTB_ENTRIES_LOG2+1:2];
    wire btb_hit = btb_valid[btb_idx] && btb_tag[btb_idx] == if_pc[31:BTB_ENTRIES_LOG2+2];

    wire br_taken = pht[pht_index(if_pc, ghr)][1];
    wire [31:0] ras_top = ras[ras_ptr - 1'b1];

    assign pred_taken  = if_jal || (if_br && br_taken) || if_ret || (if_jalr && btb_hit);
    assign pred_target = if_jal ? if_pc + imm_j :
                         if_br  ? if_pc + imm_b :
                         if_ret ? ras_top       : btb_target[btb_idx];
    assign pred_ghr     = ghr;
    assign pred_ras_ptr = ras_ptr;

    // ------------------------------------------------------------ training
    wire [PHT_ENTRIES_LOG2-1:0] upd_pht = pht_index(ex_pc, ex_ghr);
    wire [BTB_ENTRIES_LOG2-1:0] upd_btb = ex_pc[BTB_ENTRIES_LOG2+1:2];

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            ghr     <= {GHR_BITS{1'b0}};
            ras_ptr <= {RAS_DEPTH_LOG2{1'b0}};
            for (i = 0; i < PHT_ENTRIES; i = i + 1) pht[i] <= 2'b01;
            for (i = 0; i < RAS_DEPTH;   i = i + 1) ras[i] <= 32'd0;
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                btb_valid[i]  <= 1'b0;
                btb_target[i] <= 32'd0;
            end
        end else begin
            // ---- speculative history / RAS, or repair on redirect
            if (ex_redirect) begin
                ghr     <= (ex_executed && ex_br) ? {ex_ghr[GHR_BITS-2:0], ex_taken} : ex_ghr;
                ras_ptr <= !ex_executed ? ex_ras_ptr      :
                           ex_call      ? ex_ras_ptr + 1'b1 :
                           ex_ret       ? ex_ras_ptr - 1'b1 : ex_ras_ptr;
                if (ex_executed && ex_call)
                    ras[ex_ras_ptr] <= ex_pc + 32'd4;
            end else if (if_advance) begin
                if (if_br)
                    ghr <= {ghr[GHR_BITS-2:0], br_taken};
                if (if_call) begin
                    ras[ras_ptr] <= if_pc + 32'd4;
                    ras_ptr      <= ras_ptr + 1'b1;
                end else if (if_ret) begin
                    ras_ptr      <= ras_ptr - 1'b1;
                end
            end

            // ---- counters and indirect targets
            if (upd_valid && ex_br) begin
                if (ex_taken && pht[upd_pht] != 2'b11)
                    pht[upd_pht] <= pht[upd_pht] + 2'd1;
                else if (!ex_taken && pht[upd_pht] != 2'b00)
                    pht[upd_pht] <= pht[upd_pht] - 2'd1;
            end
            if (upd_valid && ex_jalr && !ex_ret) begin
                btb_valid[upd_btb]  <= 1'b1;
                btb_tag[upd_btb]    <= ex_pc[31:BTB_ENTRIES_LOG2+2];
                btb_target[upd_btb] <= upd_target;
            end
        end
    end
endmodule
