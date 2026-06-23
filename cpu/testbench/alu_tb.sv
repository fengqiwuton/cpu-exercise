`timescale 1ns/1ps
module alu_tb;
    logic [31:0] src_a, src_b, alu_result;
    logic [3:0] alu_control;
    logic zero, lt, ltu;
    alu dut (.*);

    initial begin
        $dumpfile("alu_tb.vcd"); $dumpvars(0, alu_tb);

        // ADD: 10+3=13
        src_a=10; src_b=3; alu_control=0; #10;
        if (alu_result !== 13 || zero) $error("ADD");

        // SUB: 10-3=7
        src_a=10; src_b=3; alu_control=1; #10;
        if (alu_result !== 7) $error("SUB");

        // SUB: 5-5=0, zero=1
        src_a=5; src_b=5; alu_control=1; #10;
        if (alu_result !== 0 || !zero) $error("SUB zero");

        // AND: 10&3=2
        src_a=10; src_b=3; alu_control=2; #10;
        if (alu_result !== 2) $error("AND");

        // OR: 10|3=11
        src_a=10; src_b=3; alu_control=3; #10;
        if (alu_result !== 11) $error("OR");

        // SLT signed: 5<10=1
        src_a=5; src_b=10; alu_control=4; #10;
        if (alu_result !== 1 || !lt) $error("SLT 5<10");

        // SLT signed: -1<1=1
        src_a=32'hFFFF_FFFF; src_b=1; alu_control=4; #10;
        if (alu_result !== 1) $error("SLT signed -1<1");

        // SLTU: 0xFFFFFFFF < 1 = 0 (unsigned)
        src_a=32'hFFFF_FFFF; src_b=1; alu_control=5; #10;
        if (alu_result !== 0 || ltu) $error("SLTU FFFFFFFF<1");

        $display("alu: PASSED"); $finish;
    end
endmodule
