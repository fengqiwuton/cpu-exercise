`timescale 1ns/1ps
module alu_tb;
    logic [31:0] src_a, src_b, alu_result;
    logic [3:0] alu_control;
    logic zero, lt, ltu;
    alu dut (.*);
    initial begin
        $dumpfile("alu_tb.vcd"); $dumpvars(0, alu_tb);
        src_a=10; src_b=3; alu_control=0; #10;
        if (alu_result !== 13 || zero) $error("ADD");
        src_a=10; src_b=3; alu_control=1; #10;
        if (alu_result !== 7) $error("SUB");
        src_a=5; src_b=5; alu_control=1; #10;
        if (alu_result !== 0 || !zero) $error("SUB zero");
        src_a=10; src_b=3; alu_control=2; #10;
        if (alu_result !== 2) $error("AND");
        src_a=10; src_b=3; alu_control=3; #10;
        if (alu_result !== 11) $error("OR");
        src_a=5; src_b=10; alu_control=4; #10;
        if (alu_result !== 1 || !lt) $error("SLT");
        src_a=32'hFFFF_FFFF; src_b=1; alu_control=4; #10;
        if (alu_result !== 1) $error("SLT signed");
        src_a=32'hFFFF_FFFF; src_b=1; alu_control=5; #10;
        if (alu_result !== 0 || ltu) $error("SLTU");
        src_a=32'hF0F0_F0F0; src_b=32'hFFFF_0000; alu_control=6; #10;
        if (alu_result !== 32'h0F0F_F0F0) $error("XOR");
        src_a=32'h1; src_b=32'd4; alu_control=7; #10;
        if (alu_result !== 32'h10) $error("SLL");
        src_a=32'h8000_0000; src_b=32'd3; alu_control=8; #10;
        if (alu_result !== 32'h1000_0000) $error("SRL");
        src_a=32'h8000_0000; src_b=32'd2; alu_control=9; #10;
        if (alu_result !== 32'hE000_0000) $error("SRA");
        $display("alu: PASSED"); $finish;
    end
endmodule
