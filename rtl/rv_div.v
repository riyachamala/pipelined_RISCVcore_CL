// RV32M divider: DIV, DIVU, REM, REMU. Iterative radix-2 restoring divider,
// 32 iterations + 1 setup cycle. Division by zero finishes in one cycle.
//
// Handshake with the EX stage:
//   * `req` is held high while a divide sits in EX.
//   * `busy` stays high until the result is ready; EX stalls meanwhile.
//   * The cycle `busy` drops, `result` is valid and EX advances.
//   * `kill` aborts (e.g. an interrupt is taken on the divide).
// Operands are latched at start, so they stay correct even though the
// forwarding sources drain out of MEM/WB during the stall.
module rv_div (
    input  wire        clk,
    input  wire        rst,
    input  wire        req,
    input  wire        kill,
    input  wire [1:0]  op,       // 00 DIV, 01 DIVU, 10 REM, 11 REMU
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire        busy,
    output reg  [31:0] result
);
    reg        running;
    reg        done;
    reg [5:0]  count;
    reg [31:0] quo;
    reg [32:0] rem;
    reg [31:0] divisor;
    reg        neg_quo, neg_rem, want_rem;

    wire is_signed = ~op[0];
    wire a_neg     = is_signed & a[31];
    wire b_neg     = is_signed & b[31];
    wire [31:0] a_abs = a_neg ? -a : a;
    wire [31:0] b_abs = b_neg ? -b : b;

    wire [32:0] rem_shift = {rem[31:0], quo[31]};
    wire [32:0] diff      = rem_shift - {1'b0, divisor};
    wire        fits      = ~diff[32];

    assign busy = req && !done;

    always @(posedge clk) begin
        if (rst || kill) begin
            running <= 1'b0;
            done    <= 1'b0;
        end else if (done) begin
            done <= 1'b0;                      // result consumed this cycle
        end else if (req && !running) begin
            if (b == 32'd0) begin
                // x/0 = all ones, x%0 = x (no sign fix-up)
                result <= op[1] ? a : 32'hFFFF_FFFF;
                done   <= 1'b1;
            end else begin
                running  <= 1'b1;
                count    <= 6'd32;
                quo      <= a_abs;
                rem      <= 33'd0;
                divisor  <= b_abs;
                neg_quo  <= a_neg ^ b_neg;
                neg_rem  <= a_neg;
                want_rem <= op[1];
            end
        end else if (running) begin
            quo   <= {quo[30:0], fits};
            rem   <= fits ? diff : rem_shift;
            count <= count - 6'd1;
            if (count == 6'd1) begin
                running <= 1'b0;
                done    <= 1'b1;
                if (want_rem) begin
                    result <= neg_rem ? -(fits ? diff[31:0] : rem_shift[31:0])
                                      :  (fits ? diff[31:0] : rem_shift[31:0]);
                end else begin
                    result <= neg_quo ? -{quo[30:0], fits} : {quo[30:0], fits};
                end
            end
        end
    end
endmodule
