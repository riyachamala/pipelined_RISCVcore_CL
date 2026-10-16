// Operand forwarding into EX from the MEM and WB stages.
// sel: 2'b00 = register file, 2'b01 = MEM stage result, 2'b10 = WB data
module rv_forward_unit (
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    input  wire       mem_valid,
    input  wire       mem_reg_write,
    input  wire [4:0] mem_rd,
    input  wire       wb_valid,
    input  wire       wb_reg_write,
    input  wire [4:0] wb_rd,
    output reg  [1:0] fwd_a,
    output reg  [1:0] fwd_b
);
    wire mem_fwd = mem_valid && mem_reg_write && (mem_rd != 5'd0);
    wire wb_fwd  = wb_valid  && wb_reg_write  && (wb_rd  != 5'd0);

    always @(*) begin
        if (mem_fwd && mem_rd == ex_rs1)     fwd_a = 2'b01;
        else if (wb_fwd && wb_rd == ex_rs1)  fwd_a = 2'b10;
        else                                 fwd_a = 2'b00;

        if (mem_fwd && mem_rd == ex_rs2)     fwd_b = 2'b01;
        else if (wb_fwd && wb_rd == ex_rs2)  fwd_b = 2'b10;
        else                                 fwd_b = 2'b00;
    end
endmodule
