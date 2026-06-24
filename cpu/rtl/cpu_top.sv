module cpu_top (
    input logic clk,
    input logic rst_n,
    input logic uart_rx_pin    // UART RX serial input
);
    // PC
    logic [31:0] pc, next_pc, pc_plus_4, branch_target;
    logic        pc_src;

    // Instruction
    logic [31:0] instr;

    // Control
    logic        reg_write, alu_src, mem_write, mem_to_reg;
    logic        branch, jump, lui_sel, auipc_sel;
    logic [2:0]  load_ext;
    logic [1:0]  store_type;
    logic [3:0]  alu_control;

    // Register file
    logic [31:0] rs1_data, rs2_data, rd_data;

    // Immediate
    logic [31:0] imm;

    // ALU
    logic [31:0] alu_src_b, alu_result;
    logic        zero, lt, ltu;

    // Data memory + MMIO
    logic [31:0] mem_read_data;
    logic [31:0] uart_read_data;
    logic [31:0] bus_read_data;
    logic [31:0] mem_ext_data;
    logic [3:0]  byte_enable;
    logic        io_sel;       // MMIO address select (UART)

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
        .reg_write, .alu_src, .mem_write, .mem_to_reg,
        .branch, .jump, .lui_sel, .auipc_sel,
        .load_ext, .store_type, .alu_control
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

    // Byte enables from store_type
    always_comb begin
        unique case (store_type)
            2'b01: byte_enable = 4'b0001 << alu_result[1:0];
            2'b10: byte_enable = (alu_result[1]) ? 4'b1100 : 4'b0011;
            default: byte_enable = 4'b1111;
        endcase
    end

    // MMIO address decode: UART at 0x4000_0000
    assign io_sel = (alu_result[31:28] == 4'h4);

    // Replicate byte/half-word for sb/sh so byte_enable picks correct lane
    wire [31:0] store_data;
    assign store_data = (store_type == 2'b01) ? {4{rs2_data[7:0]}} :
                        (store_type == 2'b10) ? {2{rs2_data[15:0]}} :
                        rs2_data;

    data_mem #(.DEPTH(2048)) u_data_mem (
        .clk, .addr(alu_result),
        .write_data(store_data),
        .mem_write(mem_write && !io_sel),
        .byte_enable, .read_data(mem_read_data)
    );

    uart #(.CLK_FREQ(50_000_000)) u_uart (
        .clk, .rst_n,
        .cs(io_sel),
        .addr(alu_result[3:0]),
        .write_data(store_data),
        .mem_write(mem_write && io_sel),
        .byte_enable,
        .read_data(uart_read_data),
        .tx_pin(),
        .rx_pin(uart_rx_pin)
    );

    assign bus_read_data = io_sel ? uart_read_data : mem_read_data;

    // Load extension — select correct byte/half based on addr[1:0]
    wire [1:0] load_off;
    assign load_off = alu_result[1:0];

    always_comb begin
        unique case (load_ext)
            3'b000: mem_ext_data = bus_read_data;  // lw
            3'b001: unique case (load_off)          // lb
                2'b00: mem_ext_data = {{24{bus_read_data[7]}},  bus_read_data[7:0]};
                2'b01: mem_ext_data = {{24{bus_read_data[15]}}, bus_read_data[15:8]};
                2'b10: mem_ext_data = {{24{bus_read_data[23]}}, bus_read_data[23:16]};
                default: mem_ext_data = {{24{bus_read_data[31]}}, bus_read_data[31:24]};
            endcase
            3'b010: mem_ext_data = (load_off[1])    // lh
                ? {{16{bus_read_data[31]}}, bus_read_data[31:16]}
                : {{16{bus_read_data[15]}}, bus_read_data[15:0]};
            3'b011: unique case (load_off)          // lbu
                2'b00: mem_ext_data = {24'b0, bus_read_data[7:0]};
                2'b01: mem_ext_data = {24'b0, bus_read_data[15:8]};
                2'b10: mem_ext_data = {24'b0, bus_read_data[23:16]};
                default: mem_ext_data = {24'b0, bus_read_data[31:24]};
            endcase
            3'b100: mem_ext_data = (load_off[1])    // lhu
                ? {16'b0, bus_read_data[31:16]}
                : {16'b0, bus_read_data[15:0]};
            default: mem_ext_data = bus_read_data;
        endcase
    end

    // rd_data multiplexer
    always_comb begin
        if (mem_to_reg)
            rd_data = mem_ext_data;
        else if (jump)
            rd_data = pc_plus_4;       // JAL/JALR return address
        else if (lui_sel)
            rd_data = imm;              // LUI: upper 20 bits
        else if (auipc_sel)
            rd_data = pc + imm;         // AUIPC: PC + upper 20 bits
        else
            rd_data = alu_result;
    end

    // Branch resolution
    assign funct3 = instr[14:12];
    assign pc_src = branch & (
        ((funct3 == 3'b000) &  zero)  |    // beq
        ((funct3 == 3'b001) & ~zero)  |    // bne
        ((funct3 == 3'b100) &  lt)    |    // blt
        ((funct3 == 3'b101) & ~lt)    |    // bge
        ((funct3 == 3'b110) &  ltu)   |    // bltu
        ((funct3 == 3'b111) & ~ltu)         // bgeu
    );

    assign branch_target = pc + imm;

    // next_pc selection
    always_comb begin
        if (jump && alu_src)
            next_pc = alu_result;       // JALR: rs1 + imm (ALU computed)
        else if (jump)
            next_pc = pc + imm;         // JAL: pc + J-imm
        else if (pc_src)
            next_pc = branch_target;    // branch taken
        else
            next_pc = pc_plus_4;        // sequential
    end
endmodule
