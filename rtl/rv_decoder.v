`include "rv_defines.vh"

// Main instruction decoder (ID stage). Pure combinational.
module rv_decoder #(
    parameter RV32M = 1
) (
    input  wire [31:0] instr,

    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,

    output reg  [2:0]  imm_type,
    output reg  [3:0]  alu_op,
    output reg  [1:0]  src_a_sel,
    output reg         src_b_sel,
    output reg  [1:0]  wb_sel,
    output reg         reg_write,
    output reg         uses_rs1,
    output reg         uses_rs2,

    output reg         mem_read,
    output reg         mem_write,

    output reg         is_branch,
    output reg         is_jal,
    output reg         is_jalr,

    output reg         is_mul,
    output reg         is_div,

    output reg         is_csr,
    output reg         is_ecall,
    output reg         is_ebreak,
    output reg         is_mret,
    output reg         is_fence_i,
    output reg         illegal
);
    wire [6:0] opcode = instr[6:0];
    wire [6:0] funct7 = instr[31:25];

    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];

    always @(*) begin
        imm_type   = `IMM_I;
        alu_op     = `ALU_ADD;
        src_a_sel  = `SRCA_RS1;
        src_b_sel  = `SRCB_IMM;
        wb_sel     = `WB_ALU;
        reg_write  = 1'b0;
        uses_rs1   = 1'b0;
        uses_rs2   = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        is_branch  = 1'b0;
        is_jal     = 1'b0;
        is_jalr    = 1'b0;
        is_mul     = 1'b0;
        is_div     = 1'b0;
        is_csr     = 1'b0;
        is_ecall   = 1'b0;
        is_ebreak  = 1'b0;
        is_mret    = 1'b0;
        is_fence_i = 1'b0;
        illegal    = 1'b0;

        case (opcode)
            `OP_LUI: begin
                imm_type  = `IMM_U;
                src_a_sel = `SRCA_ZERO;
                reg_write = 1'b1;
            end

            `OP_AUIPC: begin
                imm_type  = `IMM_U;
                src_a_sel = `SRCA_PC;
                reg_write = 1'b1;
            end

            `OP_JAL: begin
                imm_type  = `IMM_J;
                wb_sel    = `WB_PC4;
                reg_write = 1'b1;
                is_jal    = 1'b1;
            end

            `OP_JALR: begin
                imm_type  = `IMM_I;
                wb_sel    = `WB_PC4;
                reg_write = 1'b1;
                uses_rs1  = 1'b1;
                is_jalr   = 1'b1;
                illegal   = (funct3 != 3'b000);
            end

            `OP_BRANCH: begin
                imm_type  = `IMM_B;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                is_branch = 1'b1;
                illegal   = (funct3 == 3'b010) || (funct3 == 3'b011);
            end

            `OP_LOAD: begin
                imm_type  = `IMM_I;
                wb_sel    = `WB_MEM;
                reg_write = 1'b1;
                uses_rs1  = 1'b1;
                mem_read  = 1'b1;
                illegal   = (funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111);
            end

            `OP_STORE: begin
                imm_type  = `IMM_S;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                mem_write = 1'b1;
                illegal   = (funct3 > 3'b010);
            end

            `OP_IMM: begin
                imm_type  = `IMM_I;
                reg_write = 1'b1;
                uses_rs1  = 1'b1;
                case (funct3)
                    3'b000: alu_op = `ALU_ADD;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    3'b001: begin
                        alu_op  = `ALU_SLL;
                        illegal = (funct7 != 7'b0000000);
                    end
                    3'b101: begin
                        alu_op  = funct7[5] ? `ALU_SRA : `ALU_SRL;
                        illegal = (funct7 != 7'b0000000) && (funct7 != 7'b0100000);
                    end
                endcase
            end

            `OP_REG: begin
                src_b_sel = `SRCB_RS2;
                reg_write = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                case (funct3)
                    3'b000: alu_op = funct7[5] ? `ALU_SUB : `ALU_ADD;
                    3'b001: alu_op = `ALU_SLL;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b101: alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                endcase
                if (funct7 == 7'b0000001 && RV32M) begin
                    is_mul = ~funct3[2];        // MUL, MULH, MULHSU, MULHU
                    is_div =  funct3[2];        // DIV, DIVU, REM, REMU
                end else if (funct7 == 7'b0100000)
                    illegal = (funct3 != 3'b000) && (funct3 != 3'b101);
                else
                    illegal = (funct7 != 7'b0000000);
            end

            `OP_MISCMEM: begin
                // FENCE is a no-op on this in-order single-hart core.
                is_fence_i = (funct3 == 3'b001);
                illegal    = (funct3 != 3'b000) && (funct3 != 3'b001);
            end

            `OP_SYSTEM: begin
                if (funct3 == 3'b000) begin
                    case (instr[31:20])
                        12'h000: is_ecall  = 1'b1;
                        12'h001: is_ebreak = 1'b1;
                        12'h302: is_mret   = 1'b1;
                        12'h105: ;                   // WFI -> no-op
                        default: illegal   = 1'b1;
                    endcase
                end else if (funct3 == 3'b100) begin
                    illegal = 1'b1;
                end else begin
                    is_csr    = 1'b1;
                    wb_sel    = `WB_CSR;
                    reg_write = 1'b1;
                    uses_rs1  = ~funct3[2];          // CSRR*I use zimm
                end
            end

            default: illegal = 1'b1;
        endcase
    end
endmodule
