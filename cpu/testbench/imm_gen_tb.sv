`timescale 1ns/1ps
module imm_gen_tb;
    logic [31:0] instr, imm;
    imm_gen dut (.*);
    initial begin
        $dumpfile("imm_tb.vcd"); $dumpvars(0, imm_gen_tb);
        // I-type lw +8
        instr = {12'd8, 5'd0, 3'b010, 5'd1, 7'b0000011}; #10;
        if (imm !== 32'd8) $error("I lw");
        // I-type addi -1
        instr = {12'hFFF, 5'd0, 3'b000, 5'd1, 7'b0010011}; #10;
        if (imm !== 32'hFFFF_FFFF) $error("I addi");
        // S-type +12
        instr = {7'b0, 5'd3, 5'd0, 3'b010, 5'd12, 7'b0100011}; #10;
        if (imm !== 32'd12) $error("S");
        // B-type +8
        instr = {1'b0, 6'd0, 5'd0, 5'd0, 3'b000, 4'd4, 1'b0, 7'b1100011}; #10;
        if (imm !== 32'd8) $error("B");
        // U-type lui 0xABCDE << 12
        instr = {20'hABCDE, 5'd5, 7'b0110111}; #10;
        if (imm !== 32'hABCD_E000) $error("U lui: %h", imm);
        // U-type auipc
        instr = {20'd1, 5'd5, 7'b0010111}; #10;
        if (imm !== 32'h0000_1000) $error("U auipc");
        // J-type jal +8: imm[20]=0, imm[10:1]=4, imm[11]=0, imm[19:12]=0
        instr = {1'b0, 10'b0000000100, 1'b0, 8'b0, 5'd1, 7'b1101111}; #10;
        if (imm !== 32'd8) $error("J");
        $display("imm_gen: PASSED"); $finish;
    end
endmodule
