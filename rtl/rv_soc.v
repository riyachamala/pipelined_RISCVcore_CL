`include "rv_defines.vh"

// SoC: core + RAM + CLINT timer + simulation I/O.
//
// Memory map
//   0x0200_0000 - 0x0200_FFFF   CLINT (mtime / mtimecmp)
//   0x1000_0000                 UART TX data   (write: byte to console)
//   0x1000_0004                 UART status    (read: bit0 = tx ready)
//   0x1000_0008                 SIM exit       (write: exit code, ends sim)
//   0x8000_0000 - +RAM_BYTES    RAM (code + data), reset vector at base
module rv_soc #(
    parameter RAM_BYTES = 1024 * 1024
) (
    input  wire        clk,
    input  wire        rst,

    output wire        uart_tx_valid,
    output wire [7:0]  uart_tx_data,
    output wire        sim_exit_valid,
    output wire [31:0] sim_exit_code
);
    localparam [31:0] RAM_BASE = 32'h8000_0000;
    localparam [31:0] RAM_MASK = ~(RAM_BYTES - 1);

    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_re, dmem_we;
    wire [3:0]  dmem_wstrb;
    wire        timer_irq;
    wire [63:0] mtime;

    rv_core u_core (
        .clk            (clk),
        .rst            (rst),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata),
        .dmem_addr      (dmem_addr),
        .dmem_re        (dmem_re),
        .dmem_we        (dmem_we),
        .dmem_wstrb     (dmem_wstrb),
        .dmem_wdata     (dmem_wdata),
        .dmem_rdata     (dmem_rdata),
        .timer_irq      (timer_irq),
        .mtime          (mtime),
        .retire_valid   (),
        .retire_pc      (),
        .retire_instr   (),
        .retire_rd_we   (),
        .retire_rd      (),
        .retire_rd_data ()
    );

    // ---------------------------------------------------------------- decode
    wire ram_sel   = (dmem_addr & RAM_MASK) == RAM_BASE;
    wire clint_sel = dmem_addr[31:16] == 16'h0200;
    wire io_sel    = dmem_addr[31:12] == 20'h10000;

    // ---------------------------------------------------------------- RAM
    wire [31:0] ram_rdata, ram_irdata;

    rv_ram #(.SIZE_BYTES(RAM_BYTES)) u_ram (
        .clk     (clk),
        .i_addr  (imem_addr - RAM_BASE),
        .i_rdata (ram_irdata),
        .d_addr  (dmem_addr - RAM_BASE),
        .d_rdata (ram_rdata),
        .d_we    (dmem_we && ram_sel),
        .d_wstrb (dmem_wstrb),
        .d_wdata (dmem_wdata)
    );

    // Fetches outside RAM return 0 -> illegal instruction trap.
    assign imem_rdata = ((imem_addr & RAM_MASK) == RAM_BASE) ? ram_irdata : 32'd0;

    // ---------------------------------------------------------------- CLINT
    wire [31:0] clint_rdata;

    rv_clint u_clint (
        .clk       (clk),
        .rst       (rst),
        .sel       (clint_sel),
        .addr      (dmem_addr[15:0]),
        .we        (dmem_we),
        .wdata     (dmem_wdata),
        .rdata     (clint_rdata),
        .mtime_o   (mtime),
        .timer_irq (timer_irq)
    );

    // ---------------------------------------------------------------- sim I/O
    wire [11:0] io_off = dmem_addr[11:0];
    wire [31:0] io_rdata = (io_off == 12'h004) ? 32'd1 : 32'd0;

    assign uart_tx_valid  = dmem_we && io_sel && io_off == 12'h000;
    assign uart_tx_data   = dmem_wdata[7:0];
    assign sim_exit_valid = dmem_we && io_sel && io_off == 12'h008;
    assign sim_exit_code  = dmem_wdata;

    // ---------------------------------------------------------------- read mux
    assign dmem_rdata = ram_sel   ? ram_rdata   :
                        clint_sel ? clint_rdata :
                        io_sel    ? io_rdata    : 32'd0;
endmodule
