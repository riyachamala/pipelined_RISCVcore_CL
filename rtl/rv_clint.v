// Minimal CLINT-compatible machine timer (SiFive layout, base 0x0200_0000):
//   +0x4000  mtimecmp lo     +0x4004  mtimecmp hi
//   +0xBFF8  mtime lo        +0xBFFC  mtime hi
// mtime increments once every TICK_DIV clock cycles.
module rv_clint #(
    parameter TICK_DIV = 1
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        sel,
    input  wire [15:0] addr,
    input  wire        we,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire [63:0] mtime_o,
    output wire        timer_irq
);
    reg [63:0] mtime;
    reg [63:0] mtimecmp;
    reg [31:0] div_cnt;

    assign mtime_o   = mtime;
    assign timer_irq = (mtime >= mtimecmp);

    always @(*) begin
        case (addr)
            16'h4000: rdata = mtimecmp[31:0];
            16'h4004: rdata = mtimecmp[63:32];
            16'hBFF8: rdata = mtime[31:0];
            16'hBFFC: rdata = mtime[63:32];
            default:  rdata = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            mtime    <= 64'd0;
            mtimecmp <= {64{1'b1}};
            div_cnt  <= 32'd0;
        end else begin
            if (div_cnt == TICK_DIV - 1) begin
                div_cnt <= 32'd0;
                mtime   <= mtime + 64'd1;
            end else begin
                div_cnt <= div_cnt + 32'd1;
            end

            if (sel && we) begin
                case (addr)
                    16'h4000: mtimecmp[31:0]  <= wdata;
                    16'h4004: mtimecmp[63:32] <= wdata;
                    16'hBFF8: mtime[31:0]     <= wdata;
                    16'hBFFC: mtime[63:32]    <= wdata;
                    default: ;
                endcase
            end
        end
    end
endmodule
