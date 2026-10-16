`include "rv_defines.vh"

// Machine-mode CSR file (Zicsr) with trap entry/exit and a timer interrupt.
// Unimplemented CSRs read as zero and ignore writes.
module rv_csr (
    input  wire        clk,
    input  wire        rst,

    // CSR instruction (EX stage)
    input  wire        csr_en,
    input  wire [2:0]  csr_funct3,
    input  wire [11:0] csr_addr,
    input  wire [31:0] csr_operand,   // rs1 value or zimm
    input  wire        csr_operand_zero,
    output reg  [31:0] csr_rdata,

    // Trap entry / exit
    input  wire        trap_take,
    input  wire [31:0] trap_cause,
    input  wire [31:0] trap_pc,
    input  wire [31:0] trap_val,
    input  wire        mret,

    // Status
    input  wire        instret_inc,
    input  wire [63:0] mtime,
    input  wire        timer_irq,
    output wire [31:0] mtvec_o,
    output wire [31:0] mepc_o,
    output wire        irq_pending
);
    reg        mstatus_mie;
    reg        mstatus_mpie;
    reg        mie_mtie;
    reg [31:0] mtvec;
    reg [31:0] mscratch;
    reg [31:0] mepc;
    reg [31:0] mcause;
    reg [31:0] mtval;
    reg [63:0] mcycle;
    reg [63:0] minstret;

    wire [31:0] mstatus = {19'd0, 2'b11, 3'd0, mstatus_mpie, 3'd0, mstatus_mie, 3'd0}; // MPP = M
    wire [31:0] misa    = 32'h4000_0100;                                         // RV32I
    wire [31:0] mie_r   = {24'd0, mie_mtie, 7'd0};
    wire [31:0] mip_r   = {24'd0, timer_irq, 7'd0};

    assign mtvec_o     = mtvec;
    assign mepc_o      = mepc;
    assign irq_pending = mstatus_mie && mie_mtie && timer_irq;

    // Read
    always @(*) begin
        case (csr_addr)
            `CSR_MSTATUS:   csr_rdata = mstatus;
            `CSR_MISA:      csr_rdata = misa;
            `CSR_MIE:       csr_rdata = mie_r;
            `CSR_MTVEC:     csr_rdata = mtvec;
            `CSR_MSCRATCH:  csr_rdata = mscratch;
            `CSR_MEPC:      csr_rdata = mepc;
            `CSR_MCAUSE:    csr_rdata = mcause;
            `CSR_MTVAL:     csr_rdata = mtval;
            `CSR_MIP:       csr_rdata = mip_r;
            `CSR_MCYCLE,
            `CSR_CYCLE:     csr_rdata = mcycle[31:0];
            `CSR_MCYCLEH,
            `CSR_CYCLEH:    csr_rdata = mcycle[63:32];
            `CSR_MINSTRET,
            `CSR_INSTRET:   csr_rdata = minstret[31:0];
            `CSR_MINSTRETH,
            `CSR_INSTRETH:  csr_rdata = minstret[63:32];
            `CSR_TIME:      csr_rdata = mtime[31:0];
            `CSR_TIMEH:     csr_rdata = mtime[63:32];
            default:        csr_rdata = 32'd0;   // incl. mhartid/mvendorid/...
        endcase
    end

    // Write value: CSRRW/CSRRS/CSRRC (and immediate forms)
    reg [31:0] wdata;
    always @(*) begin
        case (csr_funct3[1:0])
            2'b01:   wdata = csr_operand;
            2'b10:   wdata = csr_rdata |  csr_operand;
            2'b11:   wdata = csr_rdata & ~csr_operand;
            default: wdata = csr_rdata;
        endcase
    end
    // CSRRS/CSRRC with rs1 = x0 (or zimm = 0) must not write.
    wire csr_we = csr_en && (csr_funct3[1:0] == 2'b01 || !csr_operand_zero);

    always @(posedge clk) begin
        if (rst) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
            mie_mtie     <= 1'b0;
            mtvec        <= 32'd0;
            mscratch     <= 32'd0;
            mepc         <= 32'd0;
            mcause       <= 32'd0;
            mtval        <= 32'd0;
            mcycle       <= 64'd0;
            minstret     <= 64'd0;
        end else begin
            mcycle   <= mcycle + 64'd1;
            if (instret_inc)
                minstret <= minstret + 64'd1;

            if (trap_take) begin
                mepc         <= {trap_pc[31:2], 2'b00};
                mcause       <= trap_cause;
                mtval        <= trap_val;
                mstatus_mpie <= mstatus_mie;
                mstatus_mie  <= 1'b0;
            end else if (mret) begin
                mstatus_mie  <= mstatus_mpie;
                mstatus_mpie <= 1'b1;
            end else if (csr_we) begin
                case (csr_addr)
                    `CSR_MSTATUS: begin
                        mstatus_mie  <= wdata[3];
                        mstatus_mpie <= wdata[7];
                    end
                    `CSR_MIE:       mie_mtie       <= wdata[7];
                    `CSR_MTVEC:     mtvec          <= {wdata[31:2], 1'b0, wdata[0]};
                    `CSR_MSCRATCH:  mscratch       <= wdata;
                    `CSR_MEPC:      mepc           <= {wdata[31:2], 2'b00};
                    `CSR_MCAUSE:    mcause         <= wdata;
                    `CSR_MTVAL:     mtval          <= wdata;
                    `CSR_MCYCLE:    mcycle[31:0]   <= wdata;
                    `CSR_MCYCLEH:   mcycle[63:32]  <= wdata;
                    `CSR_MINSTRET:  minstret[31:0] <= wdata;
                    `CSR_MINSTRETH: minstret[63:32] <= wdata;
                    default: ;
                endcase
            end
        end
    end
endmodule
