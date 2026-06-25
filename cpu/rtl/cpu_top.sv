/* verilator lint_off UNOPTFLAT */
module cpu_top #(
    parameter BOOT_EN = 0     // 1 = boot ROM mode, 0 = direct BRAM
) (
    input logic clk,
    input logic rst_n,
    input logic uart_rx_pin,
    output logic uart_tx_pin,
    output logic [7:0] uart_tx_byte,
    output logic        uart_tx_strobe,
    // VGA debug read port
    input  logic [12:0] vga_dbg_addr,
    output logic [7:0]  vga_dbg_data
);
    logic [31:0] pc, next_pc, pc_plus_4, branch_target;
    logic        pc_src;

    // Instruction (muxed: boot ROM or program BRAM)
    logic [31:0] instr;
    logic [31:0] boot_instr;
    logic [31:0] bram_instr;
    logic        boot_sel;

    // Control
    logic        reg_write, alu_src, mem_write, mem_to_reg;
    logic        branch, jump, lui_sel, auipc_sel;
    logic [2:0]  load_ext;
    logic [1:0]  store_type;
    logic [3:0]  alu_control;

    // CSR / Exception
    logic        csr_read, csr_write, csr_imm_sel;
    logic [1:0]  csr_op;
    logic        ecall_flag, mret_flag;
    logic        exception;
    logic [3:0]  except_cause;
    logic [31:0] csr_rdata, csr_wdata;
    logic [31:0] mtvec_val, mepc_val;

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
    logic        io_sel;
    logic        uart_sel;
    logic        bram_sel;
    logic        vga_sel;
    logic        ps2_sel;
    logic [31:0] ps2_read_data;

    // Branch
    logic [2:0]  funct3;

    // ── Instruction fetch ──────────────────────────────────
    pc u_pc (.clk, .rst_n, .next_pc, .pc);
    assign pc_plus_4 = pc + 32'h4;

    // Boot ROM (0x0000-0x0FFF), Program BRAM (0x1000+)
    assign boot_sel = BOOT_EN && (pc[31:12] == 20'h0);

    boot_rom #(.DEPTH(1024)) u_boot_rom (.addr(pc), .instr(boot_instr));

    insn_mem #(.DEPTH(1024)) u_insn_mem (
        .addr_a(pc),
        .instr_a(bram_instr),
        .clk,
        .addr_b(alu_result),
        .data_b(store_data),
        .wr_en_b(mem_write && bram_sel)
    );

    assign instr = boot_sel ? boot_instr : bram_instr;

    // ── Decode ─────────────────────────────────────────────
    control u_control (
        .opcode(instr[6:0]), .funct3(instr[14:12]), .funct7(instr[31:25]),
        .funct12(instr[31:20]),
        .reg_write, .alu_src, .mem_write, .mem_to_reg,
        .branch, .jump, .lui_sel, .auipc_sel,
        .load_ext, .store_type, .alu_control,
        .csr_read, .csr_write, .csr_op, .csr_imm_sel,
        .ecall_flag, .mret_flag, .exception, .except_cause
    );

    regfile u_regfile (
        .clk, .rs1_addr(instr[19:15]), .rs2_addr(instr[24:20]),
        .rd_addr(instr[11:7]), .rd_data, .reg_write, .rs1_data, .rs2_data
    );

    imm_gen u_imm_gen (.instr, .imm);
    assign alu_src_b = alu_src ? imm : rs2_data;

    alu u_alu (.src_a(rs1_data), .src_b(alu_src_b), .alu_control,
               .alu_result, .zero, .lt, .ltu);

    // ── MMIO address decode ────────────────────────────────
    assign io_sel   = (alu_result[31:28] == 4'h4);
    assign uart_sel = io_sel && (alu_result[15:12] == 4'h0) && (alu_result[5:4] == 2'd0);
    assign ps2_sel  = io_sel && (alu_result[15:12] == 4'h0) && (alu_result[5:4] == 2'd3);
    assign bram_sel = io_sel && (alu_result[15:12] == 4'h1);
    assign vga_sel  = io_sel && (alu_result[15:12] == 4'h2);

    // ── Byte enables ───────────────────────────────────────
    always_comb begin
        unique case (store_type)
            2'b01: byte_enable = 4'b0001 << alu_result[1:0];
            2'b10: byte_enable = (alu_result[1]) ? 4'b1100 : 4'b0011;
            default: byte_enable = 4'b1111;
        endcase
    end

    wire [31:0] store_data;
    assign store_data = (store_type == 2'b01) ? {4{rs2_data[7:0]}} :
                        (store_type == 2'b10) ? {2{rs2_data[15:0]}} :
                        rs2_data;

    // ── Data memory (NOT MMIO) ─────────────────────────────
    data_mem #(.DEPTH(2048)) u_data_mem (
        .clk, .addr(alu_result), .write_data(store_data),
        .mem_write(mem_write && !io_sel),
        .byte_enable, .read_data(mem_read_data)
    );

    // ── UART ───────────────────────────────────────────────
    uart #(.CLK_FREQ(50_000_000)) u_uart (
        .clk, .rst_n, .cs(uart_sel),
        .addr(alu_result[3:0]), .write_data(store_data),
        .mem_write(mem_write && uart_sel),
        .byte_enable, .read_data(uart_read_data),
        .tx_pin(uart_tx_pin), .rx_pin(uart_rx_pin),
        .tx_byte(uart_tx_byte), .tx_strobe(uart_tx_strobe)
    );

    // ── PS/2 Keyboard ──────────────────────────────────────
    ps2_kbd u_ps2 (
        .clk, .rst_n,
        .ps2_clk(1'b1),          // simulation: no real keyboard
        .ps2_data(1'b1),
        .cs(ps2_sel),
        .addr(alu_result[3:0]),
        .mem_write(mem_write && ps2_sel),
        .read_data(ps2_read_data)
    );

    // ── VGA Framebuffer ────────────────────────────────────
    vga_fb u_vga (
        .clk, .rst_n,
        .cs(vga_sel),
        .addr(alu_result),
        .write_data(store_data),
        .mem_write(mem_write && vga_sel),
        .vga_r(), .vga_g(), .vga_b(),
        .vga_hsync(), .vga_vsync(),
        .dbg_addr(vga_dbg_addr),
        .dbg_data(vga_dbg_data)
    );

    // ── CSR module ──────────────────────────────────────────
    assign csr_wdata = csr_imm_sel ? {27'b0, instr[19:15]} : rs1_data;

    csr u_csr (
        .clk, .rst_n,
        .addr(instr[31:20]),
        .write_data(csr_wdata),
        .csr_write(csr_write),
        .csr_op(csr_op),
        .read_data(csr_rdata),
        .exception(exception),
        .except_pc(pc),
        .except_cause(except_cause),
        .mtvec(mtvec_val),
        .mepc(mepc_val),
        .mret_taken()
    );

    assign bus_read_data = uart_sel ? uart_read_data :
                           ps2_sel  ? ps2_read_data :
                           mem_read_data;

    // ── Load extension ─────────────────────────────────────
    wire [1:0] load_off;
    assign load_off = alu_result[1:0];
    always_comb begin
        unique case (load_ext)
            3'b000: mem_ext_data = bus_read_data;
            3'b001: unique case (load_off)
                2'b00: mem_ext_data = {{24{bus_read_data[7]}},  bus_read_data[7:0]};
                2'b01: mem_ext_data = {{24{bus_read_data[15]}}, bus_read_data[15:8]};
                2'b10: mem_ext_data = {{24{bus_read_data[23]}}, bus_read_data[23:16]};
                default: mem_ext_data = {{24{bus_read_data[31]}}, bus_read_data[31:24]};
            endcase
            3'b010: mem_ext_data = (load_off[1])
                ? {{16{bus_read_data[31]}}, bus_read_data[31:16]}
                : {{16{bus_read_data[15]}}, bus_read_data[15:0]};
            3'b011: unique case (load_off)
                2'b00: mem_ext_data = {24'b0, bus_read_data[7:0]};
                2'b01: mem_ext_data = {24'b0, bus_read_data[15:8]};
                2'b10: mem_ext_data = {24'b0, bus_read_data[23:16]};
                default: mem_ext_data = {24'b0, bus_read_data[31:24]};
            endcase
            3'b100: mem_ext_data = (load_off[1])
                ? {16'b0, bus_read_data[31:16]}
                : {16'b0, bus_read_data[15:0]};
            default: mem_ext_data = bus_read_data;
        endcase
    end

    // ── rd_data mux ────────────────────────────────────────
    always_comb begin
        if (csr_read)          rd_data = csr_rdata;
        else if (mem_to_reg)   rd_data = mem_ext_data;
        else if (jump)         rd_data = pc_plus_4;
        else if (lui_sel)      rd_data = imm;
        else if (auipc_sel)    rd_data = pc + imm;
        else                   rd_data = alu_result;
    end

    // ── Branch / jump ──────────────────────────────────────
    assign funct3 = instr[14:12];
    assign pc_src = branch & (
        ((funct3 == 3'b000) &  zero)  |
        ((funct3 == 3'b001) & ~zero)  |
        ((funct3 == 3'b100) &  lt)    |
        ((funct3 == 3'b101) & ~lt)    |
        ((funct3 == 3'b110) &  ltu)   |
        ((funct3 == 3'b111) & ~ltu)
    );
    assign branch_target = pc + imm;

    always_comb begin
        if (mret_flag)         next_pc = mepc_val;
        else if (exception)    next_pc = mtvec_val;
        else if (jump && alu_src) next_pc = alu_result;
        else if (jump)         next_pc = pc + imm;
        else if (pc_src)       next_pc = branch_target;
        else                   next_pc = pc_plus_4;
    end
endmodule
