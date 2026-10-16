// Load/store alignment unit (MEM stage). Misaligned accesses are not
// trapped; the low address bits are simply ignored for word/half accesses.
module rv_lsu (
    input  wire [2:0]  funct3,
    input  wire [31:0] addr,
    input  wire [31:0] store_data,
    input  wire [31:0] mem_rdata,
    output reg  [31:0] mem_wdata,
    output reg  [3:0]  mem_wstrb,
    output reg  [31:0] load_data
);
    wire [1:0] off = addr[1:0];

    // Store path
    always @(*) begin
        case (funct3[1:0])
            2'b00: begin                                    // SB
                mem_wdata = {4{store_data[7:0]}};
                mem_wstrb = 4'b0001 << off;
            end
            2'b01: begin                                    // SH
                mem_wdata = {2{store_data[15:0]}};
                mem_wstrb = off[1] ? 4'b1100 : 4'b0011;
            end
            default: begin                                  // SW
                mem_wdata = store_data;
                mem_wstrb = 4'b1111;
            end
        endcase
    end

    // Load path
    wire [31:0] shifted = mem_rdata >> {off, 3'b000};

    always @(*) begin
        case (funct3)
            3'b000:  load_data = {{24{shifted[7]}},  shifted[7:0]};   // LB
            3'b001:  load_data = {{16{shifted[15]}}, shifted[15:0]};  // LH
            3'b100:  load_data = {24'd0, shifted[7:0]};               // LBU
            3'b101:  load_data = {16'd0, shifted[15:0]};              // LHU
            default: load_data = mem_rdata;                           // LW
        endcase
    end
endmodule
