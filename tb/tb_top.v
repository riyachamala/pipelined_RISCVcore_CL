`timescale 1ns/1ps

// Top-level simulation testbench, shared by both supported simulators:
// Icarus Verilog, and Verilator 5+ built with --binary --timing.
//
// Plusargs
//   +hex=<file>          program image ($readmemh, one 32-bit word per line,
//                        word 0 = 0x8000_0000)               [required]
//   +max_cycles=<n>      timeout (default 2_000_000)
//   +tohost=<hex>        riscv-tests / riscof "tohost" address; a store of 1
//                        means PASS, any other odd value means FAIL
//   +signature=<file>    dump memory [sig_begin, sig_end) at end (riscof)
//   +sig_begin=<hex> +sig_end=<hex>
//   +trace               print every retired instruction
//   +vcd                 dump waves to tb_top.vcd
module tb_top;
    localparam RAM_BYTES = 1024 * 1024;
    localparam [31:0] RAM_BASE = 32'h8000_0000;

    reg clk = 1'b0;
    reg rst = 1'b1;

    always #5 clk = ~clk;

    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;
    wire        sim_exit_valid;
    wire [31:0] sim_exit_code;

    rv_soc #(.RAM_BYTES(RAM_BYTES)) dut (
        .clk            (clk),
        .rst            (rst),
        .uart_tx_valid  (uart_tx_valid),
        .uart_tx_data   (uart_tx_data),
        .sim_exit_valid (sim_exit_valid),
        .sim_exit_code  (sim_exit_code)
    );

    // ------------------------------------------------------------------ setup
    reg [1023:0] hex_file;
    reg [1023:0] sig_file;
    reg [31:0]   tohost_addr;
    reg [31:0]   sig_begin, sig_end;
    reg [63:0]   max_cycles;
    reg          trace_en, has_tohost, has_sig;
    reg [63:0]   cycle;
    integer      fd, i;

    initial begin
        if (!$value$plusargs("hex=%s", hex_file)) begin
            $display("[tb] ERROR: +hex=<file> is required");
            $finish;
        end
        $readmemh(hex_file, dut.u_ram.mem);

        if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = 2_000_000;
        has_tohost = $value$plusargs("tohost=%h", tohost_addr);
        has_sig    = $value$plusargs("signature=%s", sig_file);
        if (has_sig) begin
            if (!$value$plusargs("sig_begin=%h", sig_begin) ||
                !$value$plusargs("sig_end=%h", sig_end)) begin
                $display("[tb] ERROR: +signature needs +sig_begin and +sig_end");
                $finish;
            end
        end
        trace_en = $test$plusargs("trace");

        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_top.vcd");
            $dumpvars(0, tb_top);
        end

        repeat (5) @(posedge clk);
        rst <= 1'b0;
    end

    // ------------------------------------------------------------------ finish
    task finish_sim(input pass, input [31:0] code);
        reg [63:0] instret;
        begin
            instret = dut.u_core.u_csr.minstret;
            if (has_sig) dump_signature();
            $display("");
            $display("[tb] cycles=%0d instret=%0d", cycle, instret);
            if (instret != 0)
                $display("[tb] CPI=%0d.%03d", cycle / instret, ((cycle * 1000) / instret) % 1000);
            if (pass) $display("[tb] PASS");
            else      $display("[tb] FAIL (code=%0d)", code);
            $finish;
        end
    endtask

    task dump_signature;
        reg [31:0] a;
        begin
            fd = $fopen(sig_file, "w");
            for (a = sig_begin; a < sig_end; a = a + 4)
                $fdisplay(fd, "%08x", dut.u_ram.mem[(a - RAM_BASE) >> 2]);
            $fclose(fd);
        end
    endtask

    // ------------------------------------------------------------------ monitors
    always @(posedge clk) begin
        if (rst) begin
            cycle <= 0;
        end else begin
            cycle <= cycle + 1;

            if (cycle >= max_cycles) begin
                $display("\n[tb] TIMEOUT after %0d cycles", cycle);
                finish_sim(1'b0, 32'hFFFF_FFFF);
            end

            if (uart_tx_valid)
                $write("%c", uart_tx_data);

            if (sim_exit_valid)
                finish_sim(sim_exit_code == 0, sim_exit_code);

            if (has_tohost && dut.u_core.dmem_we && dut.u_core.dmem_addr == tohost_addr) begin
                if (dut.u_core.dmem_wdata == 32'd1)
                    finish_sim(1'b1, 0);
                else
                    finish_sim(1'b0, dut.u_core.dmem_wdata >> 1);   // failing test number
            end

            if (trace_en && dut.u_core.retire_valid) begin
                if (dut.u_core.retire_rd_we)
                    $display("[%0d] %08x: %08x  x%0d <= %08x", cycle,
                             dut.u_core.retire_pc, dut.u_core.retire_instr,
                             dut.u_core.retire_rd, dut.u_core.retire_rd_data);
                else
                    $display("[%0d] %08x: %08x", cycle,
                             dut.u_core.retire_pc, dut.u_core.retire_instr);
            end
        end
    end
endmodule
