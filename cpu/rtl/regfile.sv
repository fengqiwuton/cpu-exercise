module regfile (
    input  logic        clk,
    input  logic [4:0]  rs1_addr, rs2_addr, rd_addr,
    input  logic [31:0] rd_data,
    input  logic        reg_write,
    output logic [31:0] rs1_data, rs2_data
);
    logic [31:0] rf [0:31];
    assign rs1_data = (rs1_addr == 0) ? 32'h0 : rf[rs1_addr];
    assign rs2_data = (rs2_addr == 0) ? 32'h0 : rf[rs2_addr];
    always_ff @(posedge clk)
        if (reg_write && rd_addr != 0)
            rf[rd_addr] <= rd_data;
endmodule
