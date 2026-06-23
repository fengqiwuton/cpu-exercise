`timescale 1ns/1ps
module control_tb;
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic reg_write, alu_src, mem_write, mem_to_reg, branch;
    logic [3:0] alu_control;
    control dut (.*);

    initial begin
        $dumpfile("ctrl_tb.vcd"); $dumpvars(0, control_tb);

        // add
        opcode=7'b0110011; funct3=3'b000; funct7=0; #10;
        if (!reg_write || alu_control !== 0) $error("add");

        // sub
        funct7=7'b0100000; #10;
        if (!reg_write || alu_control !== 1) $error("sub");

        // and
        funct3=3'b111; funct7=0; #10;
        if (alu_control !== 2) $error("and");

        // or
        funct3=3'b110; funct7=0; #10;
        if (alu_control !== 3) $error("or");

        // lw
        opcode=7'b0000011; funct3=3'b010; #10;
        if (!reg_write || !alu_src || !mem_to_reg) $error("lw");

        // sw
        opcode=7'b0100011; #10;
        if (reg_write || !alu_src || !mem_write) $error("sw");

        // beq
        opcode=7'b1100011; funct3=3'b000; #10;
        if (!branch || alu_control !== 1) $error("beq");

        // blt
        funct3=3'b100; #10;
        if (!branch || alu_control !== 4) $error("blt");

        // bge
        funct3=3'b101; #10;
        if (!branch || alu_control !== 4) $error("bge");

        // bltu
        funct3=3'b110; #10;
        if (!branch || alu_control !== 5) $error("bltu");

        // bgeu
        funct3=3'b111; #10;
        if (!branch || alu_control !== 5) $error("bgeu");

        $display("control: PASSED"); $finish;
    end
endmodule
