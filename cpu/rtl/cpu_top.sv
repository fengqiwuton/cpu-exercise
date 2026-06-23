module cpu_top (
    input logic clk,
    input logic rst_n
);
    // PC
    logic [31:0] pc, next_pc, pc_plus_4, branch_target;
    logic        pc_src;

    // Instruction
    logic [31:0] instr;

    // Control
    logic        reg_write, alu_src, mem_write, mem_to_reg, branch;
    logic [3:0]  alu_control;

    // Register file
    logic [31:0] rs1_data, rs2_data, rd_data;

    // Immediate
    logic [31:0] imm;

    // ALU
    logic [31:0] alu_src_b, alu_result;
    logic        zero, lt, ltu;

    // Data memory
    logic [31:0] mem_read_data;

    // Branch
    logic [2:0]  funct3;

    // -- Instantiations --
    pc u_pc (.clk, .rst_n, .next_pc, .pc);
    assign pc_plus_4 = pc + 32'h4;

    insn_mem #(.DEPTH(1024)) u_insn_mem (.addr(pc), .instr);

    control u_control (
        .opcode    (instr[6:0]),
        .funct3    (instr[14:12]),
        .funct7    (instr[31:25]),
        .reg_write, .alu_src, .mem_write, .mem_to_reg, .branch, .alu_control
    );

    regfile u_regfile (
        .clk,
        .rs1_addr (instr[19:15]),
        .rs2_addr (instr[24:20]),
        .rd_addr  (instr[11:7]),
        .rd_data, .reg_write, .rs1_data, .rs2_data
    );

    imm_gen u_imm_gen (.instr, .imm);

    assign alu_src_b = alu_src ? imm : rs2_data;

    alu u_alu (
        .src_a(rs1_data), .src_b(alu_src_b), .alu_control,
        .alu_result, .zero, .lt, .ltu
    );

    data_mem #(.DEPTH(1024)) u_data_mem (
        .clk, .addr(alu_result), .write_data(rs2_data), .mem_write,
        .read_data(mem_read_data)
    );

    assign rd_data = mem_to_reg ? mem_read_data : alu_result;

    // Branch resolution
    assign funct3 = instr[14:12];
    assign pc_src = branch & (
        ((funct3 == 3'b000) &  zero) |
        ((funct3 == 3'b100) &  lt)   |
        ((funct3 == 3'b101) & ~lt)   |
        ((funct3 == 3'b110) &  ltu)  |
        ((funct3 == 3'b111) & ~ltu)
    );

    assign branch_target = pc + imm;
    assign next_pc = pc_src ? branch_target : pc_plus_4;
endmodule
