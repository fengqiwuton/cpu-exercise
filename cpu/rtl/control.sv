module control (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic        reg_write, alu_src, mem_write, mem_to_reg,
    output logic        branch, jump, lui_sel, auipc_sel,
    output logic [2:0]  load_ext,
    output logic [1:0]  store_type,
    output logic [3:0]  alu_control
);
    always_comb begin
        {reg_write, alu_src, mem_write, mem_to_reg, branch, jump, lui_sel, auipc_sel} = 8'b0;
        load_ext = 3'b000;
        store_type = 2'b00;
        alu_control = 4'b0000;

        unique case (opcode)
            // R-type: add, sub, sll, slt, sltu, xor, srl, sra, or, and
            7'b0110011: begin
                reg_write = 1;
                unique case (funct3)
                    3'b000: alu_control = (funct7 == 7'b0100000) ? 4'b0001 : 4'b0000;
                    3'b001: alu_control = 4'b0111;
                    3'b010: alu_control = 4'b0100;
                    3'b011: alu_control = 4'b0101;
                    3'b100: alu_control = 4'b0110;
                    3'b101: alu_control = (funct7 == 7'b0100000) ? 4'b1001 : 4'b1000;
                    3'b110: alu_control = 4'b0011;
                    3'b111: alu_control = 4'b0010;
                endcase
            end

            // I-type ALU: addi, slli, slti, sltiu, xori, srli/srai, ori, andi
            7'b0010011: begin
                reg_write = 1;
                alu_src = 1;
                unique case (funct3)
                    3'b000: alu_control = 4'b0000;
                    3'b001: alu_control = 4'b0111;
                    3'b010: alu_control = 4'b0100;
                    3'b011: alu_control = 4'b0101;
                    3'b100: alu_control = 4'b0110;
                    3'b101: alu_control = (funct7 == 7'b0100000) ? 4'b1001 : 4'b1000;
                    3'b110: alu_control = 4'b0011;
                    3'b111: alu_control = 4'b0010;
                endcase
            end

            // LOAD: lw, lh, lb, lhu, lbu
            7'b0000011: begin
                reg_write = 1;
                alu_src = 1;
                mem_to_reg = 1;
                alu_control = 4'b0000;
                unique case (funct3)
                    3'b000: load_ext = 3'b001;  // lb
                    3'b001: load_ext = 3'b010;  // lh
                    3'b010: load_ext = 3'b000;  // lw
                    3'b100: load_ext = 3'b011;  // lbu
                    3'b101: load_ext = 3'b100;  // lhu
                    default: load_ext = 3'b000;
                endcase
            end

            // STORE: sw, sh, sb
            7'b0100011: begin
                alu_src = 1;
                mem_write = 1;
                alu_control = 4'b0000;
                unique case (funct3)
                    3'b000: store_type = 2'b01;  // sb
                    3'b001: store_type = 2'b10;  // sh
                    3'b010: store_type = 2'b00;  // sw
                    default: store_type = 2'b00;
                endcase
            end

            // BRANCH: beq, bne, blt, bge, bltu, bgeu
            7'b1100011: begin
                branch = 1;
                unique case (funct3)
                    3'b000: alu_control = 4'b0001;  // beq
                    3'b001: alu_control = 4'b0001;  // bne
                    3'b100: alu_control = 4'b0100;  // blt
                    3'b101: alu_control = 4'b0100;  // bge
                    3'b110: alu_control = 4'b0101;  // bltu
                    3'b111: alu_control = 4'b0101;  // bgeu
                endcase
            end

            // JAL
            7'b1101111: begin
                reg_write = 1;
                jump = 1;
            end

            // JALR
            7'b1100111: begin
                reg_write = 1;
                alu_src = 1;
                jump = 1;
                alu_control = 4'b0000;
            end

            // LUI
            7'b0110111: begin
                reg_write = 1;
                lui_sel = 1;
            end

            // AUIPC
            7'b0010111: begin
                reg_write = 1;
                auipc_sel = 1;
            end
        endcase
    end
endmodule
