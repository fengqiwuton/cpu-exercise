`timescale 1ns/1ps
module imm_gen_tb;
    logic [31:0] instr, imm;
    imm_gen dut (.*);
    initial begin
        $dumpfile("imm_tb.vcd"); $dumpvars(0, imm_gen_tb);

        // I-type: lw x1, 8(x0) -> imm=8
        instr = {12'd8, 5'd0, 3'b010, 5'd1, 7'b0000011}; #10;
        if (imm !== 32'd8) $error("I pos: %d", imm);

        // I-type: lw x2, -4(x1) -> imm=-4
        instr = {12'hFFC, 5'd1, 3'b010, 5'd2, 7'b0000011}; #10;
        if (imm !== 32'hFFFF_FFFC) $error("I neg: %h", imm);

        // S-type: sw x3, 12(x0) -> imm=12
        instr = {7'b0, 5'd3, 5'd0, 3'b010, 5'd12, 7'b0100011}; #10;
        if (imm !== 32'd12) $error("S: %d", imm);

        // B-type: beq x0, x0, +8 -> imm=8
        instr = {1'b0, 6'd0, 5'd0, 5'd0, 3'b000, 4'd4, 1'b0, 7'b1100011}; #10;
        if (imm !== 32'd8) $error("B fwd: %d", imm);

        // B-type: beq x0, x0, -4 -> imm=-4
        instr = {1'b1, 6'd63, 5'd0, 5'd0, 3'b000, 4'd14, 1'b1, 7'b1100011}; #10;
        if (imm !== 32'hFFFF_FFFC) $error("B bwd: %h", imm);

        $display("imm_gen: PASSED"); $finish;
    end
endmodule
