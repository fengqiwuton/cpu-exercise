module alu (
    input  logic [31:0] src_a, src_b,
    input  logic [3:0]  alu_control,
    output logic [31:0] alu_result,
    output logic        zero, lt, ltu
);
    // Manual SRA: logical shift + sign-bit fill mask
    // mask = ~(0xFFFFFFFF >> amt) sets top `amt` bits to src_a[31]
    wire [31:0] shift_amt;
    wire [31:0] sra_out;
    assign shift_amt = {27'b0, src_b[4:0]};
    assign sra_out = (src_a >> shift_amt) |
                     (src_a[31] ? ~(32'hFFFF_FFFF >> shift_amt) : 32'h0);

    always_comb case (alu_control)
        4'b0000: alu_result = src_a + src_b;
        4'b0001: alu_result = src_a - src_b;
        4'b0010: alu_result = src_a & src_b;
        4'b0011: alu_result = src_a | src_b;
        4'b0100: alu_result = {31'b0, $signed(src_a) < $signed(src_b)};
        4'b0101: alu_result = {31'b0, src_a < src_b};
        4'b0110: alu_result = src_a ^ src_b;
        4'b0111: alu_result = src_a << src_b[4:0];
        4'b1000: alu_result = src_a >> src_b[4:0];
        4'b1001: alu_result = sra_out;
        default: alu_result = 32'h0;
    endcase
    assign zero = (alu_result == 0);
    assign lt   = $signed(src_a) < $signed(src_b);
    assign ltu  = src_a < src_b;
endmodule
