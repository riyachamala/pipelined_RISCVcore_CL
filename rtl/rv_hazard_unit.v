// Hazard detection: load-use stall and control-flow flushes.
//
// Control-flow changes (mispredict, trap, mret, fence.i) are resolved in EX,
// so a redirect squashes the two younger instructions in IF/ID and ID/EX.
module rv_hazard_unit (
    // ID stage
    input  wire       id_valid,
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_uses_rs1,
    input  wire       id_uses_rs2,
    // EX stage
    input  wire       ex_valid,
    input  wire       ex_mem_read,
    input  wire [4:0] ex_rd,
    input  wire       ex_redirect,

    output wire       stall_if,
    output wire       stall_id,
    output wire       flush_id,   // squash IF/ID register
    output wire       flush_ex    // insert bubble into ID/EX register
);
    wire load_use = id_valid && ex_valid && ex_mem_read && (ex_rd != 5'd0) &&
                    ((id_uses_rs1 && id_rs1 == ex_rd) ||
                     (id_uses_rs2 && id_rs2 == ex_rd));

    assign stall_if = load_use && !ex_redirect;
    assign stall_id = load_use && !ex_redirect;
    assign flush_id = ex_redirect;
    assign flush_ex = ex_redirect || load_use;
endmodule
