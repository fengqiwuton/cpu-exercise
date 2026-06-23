module control (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic        reg_write, alu_src, mem_write, mem_to_reg, branch,
    output logic [3:0]  alu_control
);
    always_comb begin
        {reg_write, alu_src, mem_write, mem_to_reg, branch} = 5'b0;
        alu_control = 4'b0000;
        case (opcode)
            7'b0110011: begin  // R-type
                reg_write = 1;
                case (funct3)
                    3'b000: alu_control = (funct7 == 7'b0100000) ? 4'b0001 : 4'b0000;
                    3'b111: alu_control = 4'b0010;
                    3'b110: alu_control = 4'b0011;
                endcase
            end
            7'b0000011: begin  // lw
                {reg_write, alu_src, mem_to_reg} = 3'b111;
            end
            7'b0100011: begin  // sw
                {alu_src, mem_write} = 2'b11;
            end
            7'b1100011: begin  // branch
                branch = 1;
                case (funct3)
                    3'b000: alu_control = 4'b0001;
                    3'b100, 3'b101: alu_control = 4'b0100;
                    3'b110, 3'b111: alu_control = 4'b0101;
                endcase
            end
        endcase
    end
endmodule
