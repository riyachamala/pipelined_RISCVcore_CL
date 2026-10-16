// RV32M multiplier: MUL, MULH, MULHSU, MULHU. Single-cycle (maps onto DSP
// blocks on FPGA); funct3[1:0] selects the variant.
module rv_mul (
    input  wire [1:0]  op,       // 00 MUL, 01 MULH, 10 MULHSU, 11 MULHU
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [31:0] y
);
    wire a_signed = (op == 2'b01) || (op == 2'b10);
    wire b_signed = (op == 2'b01);

    wire signed [32:0] sa = {a_signed & a[31], a};
    wire signed [32:0] sb = {b_signed & b[31], b};
    wire signed [65:0] prod = sa * sb;

    assign y = (op == 2'b00) ? prod[31:0] : prod[63:32];
endmodule
