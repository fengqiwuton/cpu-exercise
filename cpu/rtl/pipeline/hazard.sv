// Hazard detection + forwarding unit for 5-stage pipeline
module hazard (
    // ID stage register sources
    input  logic [4:0]  id_rs1, id_rs2,
    // EX stage register sources + destination
    input  logic [4:0]  ex_rs1, ex_rs2,
    input  logic [4:0]  ex_rd,
    input  logic        ex_mem_read,       // EX stage is a load
    // EX/MEM destination
    input  logic [4:0]  ex_mem_rd,
    input  logic        ex_mem_reg_write,
    // MEM/WB destination
    input  logic [4:0]  mem_wb_rd,
    input  logic        mem_wb_reg_write,

    // Outputs
    output logic [1:0]  forward_a,         // 00=rs1, 01=EX/MEM, 10=MEM/WB
    output logic [1:0]  forward_b,         // 00=rs2, 01=EX/MEM, 10=MEM/WB
    output logic        stall,             // stall IF/ID and ID/EX
    output logic        flush              // flush IF/ID (for branches)
);
    // ── Forwarding for EX stage ─────────────────────────────
    always_comb begin
        forward_a = 2'b00;
        forward_b = 2'b00;

        // Forward A (rs1)
        if (ex_rs1 != 0) begin
            if (ex_mem_reg_write && ex_mem_rd == ex_rs1)
                forward_a = 2'b01;  // from EX/MEM
            else if (mem_wb_reg_write && mem_wb_rd == ex_rs1)
                forward_a = 2'b10;  // from MEM/WB
        end

        // Forward B (rs2)
        if (ex_rs2 != 0) begin
            if (ex_mem_reg_write && ex_mem_rd == ex_rs2)
                forward_b = 2'b01;  // from EX/MEM
            else if (mem_wb_reg_write && mem_wb_rd == ex_rs2)
                forward_b = 2'b10;  // from MEM/WB
        end
    end

    // ── Load-use stall: EX stage is a load whose result is ──
    // needed by the next instruction in ID. Stall 1 cycle.
    logic load_use;
    assign load_use = ex_mem_read && ex_rd != 0 && (
        (ex_rd == id_rs1) || (ex_rd == id_rs2)
    );

    assign stall = load_use;
    assign flush = 1'b0;  // used externally for branches

endmodule
