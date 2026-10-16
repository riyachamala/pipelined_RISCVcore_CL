// Unified instruction/data RAM: two combinational read ports, one byte-
// maskable synchronous write port. Behavioural model intended for
// simulation (maps to distributed RAM on FPGA for small sizes; swap for a
// synchronous BRAM + fetch-stage register when targeting real hardware).
module rv_ram #(
    parameter SIZE_BYTES = 4 * 1024 * 1024
) (
    input  wire        clk,

    input  wire [31:0] i_addr,      // byte offset into RAM
    output wire [31:0] i_rdata,

    input  wire [31:0] d_addr,      // byte offset into RAM
    output wire [31:0] d_rdata,
    input  wire        d_we,
    input  wire [3:0]  d_wstrb,
    input  wire [31:0] d_wdata
);
    localparam WORDS  = SIZE_BYTES / 4;
    localparam AWIDTH = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];

    wire [AWIDTH-1:0] i_idx = i_addr[AWIDTH+1:2];
    wire [AWIDTH-1:0] d_idx = d_addr[AWIDTH+1:2];

    assign i_rdata = mem[i_idx];
    assign d_rdata = mem[d_idx];

    always @(posedge clk) begin
        if (d_we) begin
            if (d_wstrb[0]) mem[d_idx][7:0]   <= d_wdata[7:0];
            if (d_wstrb[1]) mem[d_idx][15:8]  <= d_wdata[15:8];
            if (d_wstrb[2]) mem[d_idx][23:16] <= d_wdata[23:16];
            if (d_wstrb[3]) mem[d_idx][31:24] <= d_wdata[31:24];
        end
    end
endmodule
