module alu (
    input  logic [31:0] src_a, src_b,
    input  logic [3:0]  alu_control,
    output logic [31:0] alu_result,
    output logic        zero, lt, ltu
);
    always_comb case (alu_control)
        4'b0000: alu_result = src_a + src_b;
        4'b0001: alu_result = src_a - src_b;
        4'b0010: alu_result = src_a & src_b;
        4'b0011: alu_result = src_a | src_b;
        4'b0100: alu_result = {31'b0, $signed(src_a) < $signed(src_b)};
        4'b0101: alu_result = {31'b0, src_a < src_b};
        default: alu_result = 32'h0;
    endcase
    assign zero = (alu_result == 0);
    assign lt   = $signed(src_a) < $signed(src_b);
    assign ltu  = src_a < src_b;
endmodule
