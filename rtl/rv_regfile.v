// 32 x 32-bit register file, 2 async read ports, 1 sync write port.
// Write-before-read bypass covers the WB -> ID hazard.
module rv_regfile (
    input  wire        clk,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    input  wire        we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);
    reg [31:0] regs [1:31];

    always @(posedge clk) begin
        if (we && rd_addr != 5'd0)
            regs[rd_addr] <= rd_data;
    end

    assign rs1_data = (rs1_addr == 5'd0)                ? 32'd0   :
                      (we && rd_addr == rs1_addr)        ? rd_data :
                                                           regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0)                ? 32'd0   :
                      (we && rd_addr == rs2_addr)        ? rd_data :
                                                           regs[rs2_addr];
endmodule
