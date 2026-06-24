module control (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic [11:0] funct12,       // funct7+funct5 for SYSTEM instrs
    output logic        reg_write, alu_src, mem_write, mem_to_reg,
    output logic        branch, jump, lui_sel, auipc_sel,
    output logic [2:0]  load_ext,
    output logic [1:0]  store_type,
    output logic [3:0]  alu_control,
    // CSR / Exception
    output logic        csr_read,       // read CSR (rd = CSR[addr])
    output logic        csr_write,      // write CSR
    output logic [1:0]  csr_op,         // 00=rw, 01=rs, 10=rc
    output logic        csr_imm_sel,    // use zimm instead of rs1
    output logic        ecall_flag,     // ecall instruction
    output logic        mret_flag,      // mret instruction
    output logic        exception,      // trigger exception
    output logic [3:0]  except_cause    // exception type
);
    always_comb begin
        {reg_write, alu_src, mem_write, mem_to_reg, branch, jump, lui_sel, auipc_sel} = 8'b0;
        {csr_read, csr_write, csr_imm_sel, ecall_flag, mret_flag, exception} = 6'b0;
        load_ext = 3'b000;
        store_type = 2'b00;
        alu_control = 4'b0000;
        csr_op = 2'b00;
        except_cause = 4'd0;

        unique case (opcode)
            // R-type
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
                    default: begin
                        exception = 1;
                        except_cause = 4'd2;  // illegal instruction
                    end
                endcase
            end

            // I-type ALU
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
                    default: begin
                        exception = 1;
                        except_cause = 4'd2;
                    end
                endcase
            end

            // LOAD
            7'b0000011: begin
                reg_write = 1;
                alu_src = 1;
                mem_to_reg = 1;
                alu_control = 4'b0000;
                unique case (funct3)
                    3'b000: load_ext = 3'b001;
                    3'b001: load_ext = 3'b010;
                    3'b010: load_ext = 3'b000;
                    3'b100: load_ext = 3'b011;
                    3'b101: load_ext = 3'b100;
                    default: begin
                        exception = 1;
                        except_cause = 4'd2;
                    end
                endcase
            end

            // STORE
            7'b0100011: begin
                alu_src = 1;
                mem_write = 1;
                alu_control = 4'b0000;
                unique case (funct3)
                    3'b000: store_type = 2'b01;
                    3'b001: store_type = 2'b10;
                    3'b010: store_type = 2'b00;
                    default: begin
                        exception = 1;
                        except_cause = 4'd2;
                    end
                endcase
            end

            // BRANCH
            7'b1100011: begin
                branch = 1;
                unique case (funct3)
                    3'b000: alu_control = 4'b0001;
                    3'b001: alu_control = 4'b0001;
                    3'b100: alu_control = 4'b0100;
                    3'b101: alu_control = 4'b0100;
                    3'b110: alu_control = 4'b0101;
                    3'b111: alu_control = 4'b0101;
                    default: begin
                        exception = 1;
                        except_cause = 4'd2;
                    end
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

            // SYSTEM (csr*, ecall, mret)
            7'b1110011: begin
                unique case (funct3)
                    3'b000: begin  // ecall / mret (distinguished by funct12)
                        if (funct12 == 12'h000) begin
                            // ecall
                            exception = 1;
                            except_cause = 4'd11;  // ecall from M-mode
                            ecall_flag = 1;
                        end else if (funct12 == 12'h302) begin
                            // mret
                            mret_flag = 1;
                            jump = 1;
                        end else begin
                            exception = 1;
                            except_cause = 4'd2;
                        end
                    end
                    3'b001: begin csr_read=1; csr_write=1; csr_op=2'b00; reg_write=1; end
                    3'b010: begin csr_read=1; csr_write=1; csr_op=2'b01; reg_write=1; end
                    3'b011: begin csr_read=1; csr_write=1; csr_op=2'b10; reg_write=1; end
                    3'b101: begin csr_read=1; csr_write=1; csr_op=2'b00; csr_imm_sel=1; reg_write=1; end
                    3'b110: begin csr_read=1; csr_write=1; csr_op=2'b01; csr_imm_sel=1; reg_write=1; end
                    3'b111: begin csr_read=1; csr_write=1; csr_op=2'b10; csr_imm_sel=1; reg_write=1; end
                    default: begin
                        exception = 1;
                        except_cause = 4'd2;
                    end
                endcase
            end

            default: begin
                exception = 1;
                except_cause = 4'd2;  // illegal instruction
            end
        endcase
    end
endmodule
