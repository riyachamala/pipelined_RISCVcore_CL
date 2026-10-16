// Dynamic branch predictor: direct-mapped BTB with a 2-bit saturating
// counter per entry. Looked up in IF, trained from EX.
//
// An entry is only allocated for control-flow instructions that were taken,
// so a BTB miss always predicts fall-through (pc + 4).
module rv_branch_predictor #(
    parameter ENTRIES_LOG2 = 6
) (
    input  wire        clk,
    input  wire        rst,

    // IF lookup
    input  wire [31:0] if_pc,
    output wire        pred_taken,
    output wire [31:0] pred_target,

    // EX update
    input  wire        upd_valid,
    input  wire [31:0] upd_pc,
    input  wire        upd_taken,
    input  wire [31:0] upd_target
);
    localparam ENTRIES = 1 << ENTRIES_LOG2;
    localparam TAG_W   = 30 - ENTRIES_LOG2;

    reg              valid  [0:ENTRIES-1];
    reg [TAG_W-1:0]  tag    [0:ENTRIES-1];
    reg [31:0]       target [0:ENTRIES-1];
    reg [1:0]        ctr    [0:ENTRIES-1];

    wire [ENTRIES_LOG2-1:0] if_idx  = if_pc[ENTRIES_LOG2+1:2];
    wire [TAG_W-1:0]        if_tag  = if_pc[31:ENTRIES_LOG2+2];
    wire [ENTRIES_LOG2-1:0] upd_idx = upd_pc[ENTRIES_LOG2+1:2];
    wire [TAG_W-1:0]        upd_tag = upd_pc[31:ENTRIES_LOG2+2];

    wire hit = valid[if_idx] && (tag[if_idx] == if_tag);
    assign pred_taken  = hit && ctr[if_idx][1];
    assign pred_target = target[if_idx];

    wire upd_hit = valid[upd_idx] && (tag[upd_idx] == upd_tag);

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1)
                valid[i] <= 1'b0;
        end else if (upd_valid) begin
            if (upd_hit) begin
                if (upd_taken) begin
                    target[upd_idx] <= upd_target;
                    if (ctr[upd_idx] != 2'b11) ctr[upd_idx] <= ctr[upd_idx] + 2'd1;
                end else if (ctr[upd_idx] != 2'b00) begin
                    ctr[upd_idx] <= ctr[upd_idx] - 2'd1;
                end
            end else if (upd_taken) begin
                valid[upd_idx]  <= 1'b1;
                tag[upd_idx]    <= upd_tag;
                target[upd_idx] <= upd_target;
                ctr[upd_idx]    <= 2'b10;          // weakly taken
            end
        end
    end
endmodule
