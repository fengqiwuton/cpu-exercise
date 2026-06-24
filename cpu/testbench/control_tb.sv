`timescale 1ns/1ps
module control_tb;
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic reg_write, alu_src, mem_write, mem_to_reg, branch, jump, lui_sel, auipc_sel;
    logic [2:0] load_ext;
    logic [1:0] store_type;
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

        // sll
        funct3=3'b001; funct7=0; #10;
        if (alu_control !== 7) $error("sll");

        // slt
        funct3=3'b010; #10;
        if (alu_control !== 4) $error("slt");

        // sltu
        funct3=3'b011; #10;
        if (alu_control !== 5) $error("sltu");

        // xor
        funct3=3'b100; #10;
        if (alu_control !== 6) $error("xor");

        // srl
        funct3=3'b101; funct7=0; #10;
        if (alu_control !== 8) $error("srl");

        // sra
        funct7=7'b0100000; #10;
        if (alu_control !== 9) $error("sra");

        // or
        funct3=3'b110; funct7=0; #10;
        if (alu_control !== 3) $error("or");

        // and
        funct3=3'b111; #10;
        if (alu_control !== 2) $error("and");

        // addi
        opcode=7'b0010011; funct3=3'b000; funct7=0; #10;
        if (!reg_write || !alu_src || alu_control !== 0) $error("addi");

        // xori
        funct3=3'b100; #10;
        if (alu_control !== 6) $error("xori");

        // srli
        funct3=3'b101; funct7=0; #10;
        if (alu_control !== 8) $error("srli");

        // srai
        funct7=7'b0100000; #10;
        if (alu_control !== 9) $error("srai");

        // lw
        opcode=7'b0000011; funct3=3'b010; #10;
        if (!reg_write || !alu_src || !mem_to_reg || load_ext !== 0) $error("lw");

        // lb
        funct3=3'b000; #10;
        if (load_ext !== 1) $error("lb");

        // lh
        funct3=3'b001; #10;
        if (load_ext !== 2) $error("lh");

        // lbu
        funct3=3'b100; #10;
        if (load_ext !== 3) $error("lbu");

        // lhu
        funct3=3'b101; #10;
        if (load_ext !== 4) $error("lhu");

        // sw
        opcode=7'b0100011; funct3=3'b010; #10;
        if (reg_write || !alu_src || !mem_write || store_type !== 0) $error("sw");

        // sb
        funct3=3'b000; #10;
        if (store_type !== 1) $error("sb");

        // sh
        funct3=3'b001; #10;
        if (store_type !== 2) $error("sh");

        // beq
        opcode=7'b1100011; funct3=3'b000; #10;
        if (!branch || alu_control !== 1) $error("beq");

        // bne
        funct3=3'b001; #10;
        if (!branch || alu_control !== 1) $error("bne");

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

        // jal
        opcode=7'b1101111; #10;
        if (!reg_write || !jump) $error("jal");

        // jalr
        opcode=7'b1100111; #10;
        if (!reg_write || !jump || !alu_src || alu_control !== 0) $error("jalr");

        // lui
        opcode=7'b0110111; #10;
        if (!reg_write || !lui_sel) $error("lui");

        // auipc
        opcode=7'b0010111; #10;
        if (!reg_write || !auipc_sel) $error("auipc");

        $display("control: PASSED"); $finish;
    end
endmodule
