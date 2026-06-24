// 5-stage pipelined RV32I CPU
// IF→ID→EX→MEM→WB with forwarding and load-use stall
module pipeline_top (
    input  logic clk, rst_n,
    input  logic uart_rx_pin
);
    // ── IF stage ────────────────────────────────────────────
    logic [31:0] pc, next_pc, pc_plus_4;
    logic [31:0] imem_instr;
    logic        stall_f, flush_f;   // IF stall/flush

    // ── IF/ID pipeline reg ──────────────────────────────────
    logic [31:0] if_id_pc, if_id_pc4, if_id_instr;
    logic        if_id_valid;

    // ── ID stage ────────────────────────────────────────────
    logic [31:0] id_pc, id_pc4, id_instr;
    logic [31:0] id_rs1_data, id_rs2_data, id_imm;
    logic [4:0]  id_rs1, id_rs2, id_rd;
    logic [6:0]  id_opcode;
    logic [2:0]  id_funct3;
    logic [6:0]  id_funct7;
    logic [11:0] id_funct12;

    // Control signals from ID
    logic       id_reg_write, id_alu_src, id_mem_write, id_mem_to_reg;
    logic       id_mem_read;
    logic       id_branch, id_jump, id_lui_sel, id_auipc_sel;
    logic [2:0] id_load_ext;
    logic [1:0] id_store_type;
    logic [3:0] id_alu_control;
    logic       id_csr_read, id_csr_write;
    logic [1:0] id_csr_op;
    logic       id_csr_imm_sel;
    logic       id_exception;
    logic [3:0] id_except_cause;
    logic       id_ecall_flag;

    // Branch resolution
    logic       id_branch_taken;
    logic [31:0]id_branch_target;

    // ── ID/EX pipeline reg ──────────────────────────────────
    logic [31:0] id_ex_pc, id_ex_pc4;
    logic [31:0] id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    logic [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    logic [2:0]  id_ex_funct3;
    logic        id_ex_reg_write, id_ex_mem_write, id_ex_mem_to_reg;
    logic        id_ex_mem_read;
    logic        id_ex_alu_src, id_ex_branch, id_ex_jump;
    logic        id_ex_lui_sel, id_ex_auipc_sel;
    logic [2:0]  id_ex_load_ext;
    logic [1:0]  id_ex_store_type;
    logic [3:0]  id_ex_alu_control;
    logic        id_ex_csr_read, id_ex_csr_write;
    logic [1:0]  id_ex_csr_op;
    logic        id_ex_csr_imm_sel;
    logic        id_ex_exception;
    logic [3:0]  id_ex_except_cause;
    logic        id_ex_jump_flag;        // JAL/JALR

    // ── EX stage ────────────────────────────────────────────
    logic [31:0] ex_alu_a, ex_alu_b, ex_alu_result;
    logic        ex_zero, ex_lt, ex_ltu;
    logic [31:0] ex_store_data;
    logic [3:0]  ex_byte_enable;

    // ── EX/MEM pipeline reg ─────────────────────────────────
    logic [31:0] ex_mem_alu_result, ex_mem_rs2_data;
    logic [4:0]  ex_mem_rd;
    logic        ex_mem_reg_write, ex_mem_mem_write, ex_mem_mem_to_reg;
    logic        ex_mem_jump_flag;
    logic [2:0]  ex_mem_load_ext;
    logic [1:0]  ex_mem_store_type;
    logic        ex_mem_exception;
    logic [3:0]  ex_mem_except_cause;
    logic [31:0] ex_mem_pc4;

    // ── MEM stage ───────────────────────────────────────────
    logic [31:0] mem_read_data, mem_ext_data;

    // ── MEM/WB pipeline reg ─────────────────────────────────
    logic        mem_wb_reg_write, mem_wb_mem_to_reg;
    logic        mem_wb_jump_flag;
    logic [31:0] mem_wb_alu_result, mem_wb_mem_data;
    logic [4:0]  mem_wb_rd;
    logic [31:0] mem_wb_pc4;
    logic        mem_wb_csr_read;
    logic [31:0] mem_wb_csr_rdata;

    // ── Hazard unit ─────────────────────────────────────────
    logic [1:0]  forward_a, forward_b;
    logic        load_stall;

    // ── MMIO (simplified — use single-cycle data_mem interface) ──
    logic        io_sel;
    assign io_sel = (ex_mem_alu_result[31:28] == 4'h4);

    // ═══════════════════════════════════════════════════════════
    //  IF: Instruction Fetch
    // ═══════════════════════════════════════════════════════════
    pc u_pc (.clk, .rst_n, .next_pc, .pc);
    assign pc_plus_4 = pc + 32'h4;

    insn_mem #(.DEPTH(1024)) u_imem (
        .addr_a(pc), .instr_a(imem_instr),
        .clk, .addr_b(32'd0), .data_b(32'd0), .wr_en_b(1'b0)
    );

    // IF/ID register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc    <= 32'd0;
            if_id_pc4   <= 32'd0;
            if_id_instr <= 32'h00000013;  // nop
        end else if (!stall_f) begin
            if (flush_f || id_branch_taken) begin
                if_id_instr <= 32'h00000013;  // nop (bubble)
            end else begin
                if_id_pc    <= pc;
                if_id_pc4   <= pc_plus_4;
                if_id_instr <= imem_instr;
            end
        end
        // on stall: hold current values
    end

    // ═══════════════════════════════════════════════════════════
    //  ID: Decode + Register Read
    // ═══════════════════════════════════════════════════════════
    assign {id_pc, id_pc4, id_instr} = {if_id_pc, if_id_pc4, if_id_instr};
    assign id_opcode  = id_instr[6:0];
    assign id_rd      = id_instr[11:7];
    assign id_funct3  = id_instr[14:12];
    assign id_funct7  = id_instr[31:25];
    assign id_funct12 = id_instr[31:20];
    assign id_rs1     = id_instr[19:15];
    assign id_rs2     = id_instr[24:20];

    control u_control (
        .opcode(id_opcode), .funct3(id_funct3), .funct7(id_funct7),
        .funct12(id_funct12),
        .reg_write(id_reg_write), .alu_src(id_alu_src),
        .mem_write(id_mem_write), .mem_to_reg(id_mem_to_reg),
        .branch(id_branch), .jump(id_jump),
        .lui_sel(id_lui_sel), .auipc_sel(id_auipc_sel),
        .load_ext(id_load_ext), .store_type(id_store_type),
        .alu_control(id_alu_control),
        .csr_read(id_csr_read), .csr_write(id_csr_write),
        .csr_op(id_csr_op), .csr_imm_sel(id_csr_imm_sel),
        .ecall_flag(id_ecall_flag), .mret_flag(),
        .exception(id_exception), .except_cause(id_except_cause)
    );
    assign id_mem_read = (id_opcode == 7'b0000011);  // load instruction

    regfile u_regfile (
        .clk,
        .rs1_addr(id_rs1), .rs2_addr(id_rs2),
        .rd_addr(mem_wb_rd),
        .rd_data(mem_wb_mem_to_reg ? mem_wb_mem_data :
                 mem_wb_jump_flag  ? mem_wb_pc4 :
                 mem_wb_alu_result),
        .reg_write(mem_wb_reg_write),
        .rs1_data(id_rs1_data), .rs2_data(id_rs2_data)
    );

    imm_gen u_imm_gen (.instr(id_instr), .imm(id_imm));

    // Branch operands with forwarding (EX → ID, plus EX/MEM, MEM/WB)
    logic [31:0] br_rs1, br_rs2;
    always_comb begin
        // Forward rs1: priority = EX > EX/MEM > MEM/WB > regfile
        if (id_ex_reg_write && id_ex_rd != 0 && id_ex_rd == id_rs1)
            br_rs1 = ex_alu_result;       // from current EX (addi→beq back-to-back)
        else if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_rs1)
            br_rs1 = ex_mem_alu_result;
        else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == id_rs1)
            br_rs1 = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;
        else
            br_rs1 = id_rs1_data;
        // Forward rs2
        if (id_ex_reg_write && id_ex_rd != 0 && id_ex_rd == id_rs2)
            br_rs2 = ex_alu_result;
        else if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_rs2)
            br_rs2 = ex_mem_alu_result;
        else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == id_rs2)
            br_rs2 = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;
        else
            br_rs2 = id_rs2_data;
    end

    // Branch resolution (in ID stage, with forwarded operands)
    always_comb begin
        id_branch_taken = 1'b0;
        id_branch_target = id_pc + id_imm;
        if (id_branch) begin
            unique case (id_funct3)
                3'b000: id_branch_taken = (br_rs1 == br_rs2);
                3'b001: id_branch_taken = (br_rs1 != br_rs2);
                3'b100: id_branch_taken = $signed(br_rs1) < $signed(br_rs2);
                3'b101: id_branch_taken = $signed(br_rs1) >= $signed(br_rs2);
                3'b110: id_branch_taken = br_rs1 < br_rs2;
                3'b111: id_branch_taken = br_rs1 >= br_rs2;
            endcase
        end
        if (id_jump) begin
            id_branch_taken = 1'b1;
            id_branch_target = (id_opcode == 7'b1100111) ? (br_rs1 + id_imm) : (id_pc + id_imm);
        end
    end

    // ID/EX register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {id_ex_reg_write, id_ex_mem_write, id_ex_mem_to_reg,
             id_ex_alu_src, id_ex_branch, id_ex_jump,
             id_ex_lui_sel, id_ex_auipc_sel,
             id_ex_csr_read, id_ex_csr_write, id_ex_exception} <= 14'd0;
            id_ex_alu_control <= 4'd0;
            id_ex_load_ext <= 3'd0; id_ex_store_type <= 2'd0;
            id_ex_rs1 <= 5'd0; id_ex_rs2 <= 5'd0; id_ex_rd <= 5'd0;
            id_ex_mem_read <= 1'b0;
        end else if (!load_stall) begin
            id_ex_pc        <= id_pc;
            id_ex_pc4       <= id_pc4;
            id_ex_rs1_data  <= id_rs1_data;
            id_ex_rs2_data  <= id_rs2_data;
            id_ex_imm       <= id_imm;
            id_ex_rs1       <= id_rs1;
            id_ex_rs2       <= id_rs2;
            id_ex_rd        <= id_rd;
            id_ex_funct3    <= id_funct3;
            id_ex_reg_write  <= id_reg_write;
            id_ex_mem_write  <= id_mem_write;
            id_ex_mem_to_reg <= id_mem_to_reg;
            id_ex_mem_read   <= id_mem_read;
            id_ex_alu_src    <= id_alu_src;
            id_ex_alu_control<= id_alu_control;
            id_ex_load_ext   <= id_load_ext;
            id_ex_store_type <= id_store_type;
            id_ex_lui_sel    <= id_lui_sel;
            id_ex_auipc_sel  <= id_auipc_sel;
            id_ex_exception  <= id_exception;
            id_ex_except_cause<=id_except_cause;
            id_ex_jump_flag  <= id_jump;
        end else begin
            // Insert bubble on load-use stall: zero all control
            id_ex_reg_write <= 1'b0; id_ex_mem_write <= 1'b0;
            id_ex_mem_to_reg <= 1'b0; id_ex_alu_src <= 1'b0;
            id_ex_mem_read <= 1'b0;
            id_ex_branch <= 1'b0; id_ex_jump <= 1'b0;
            id_ex_lui_sel <= 1'b0; id_ex_auipc_sel <= 1'b0;
            id_ex_exception <= 1'b0;
        end
    end

    // ═══════════════════════════════════════════════════════════
    //  EX: Execute
    // ═══════════════════════════════════════════════════════════
    // Forwarding mux for ALU inputs
    always_comb begin
        // ALU A
        unique case (forward_a)
            2'b01: ex_alu_a = ex_mem_alu_result;
            2'b10: ex_alu_a = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;
            default: ex_alu_a = id_ex_rs1_data;
        endcase
        // ALU B
        unique case (forward_b)
            2'b01: ex_alu_b = ex_mem_alu_result;
            2'b10: ex_alu_b = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;
            default: ex_alu_b = id_ex_rs2_data;
        endcase
        // ALU B source select (immediate vs register)
        if (id_ex_alu_src) ex_alu_b = id_ex_imm;
    end

    alu u_alu (
        .src_a(ex_alu_a), .src_b(ex_alu_b),
        .alu_control(id_ex_alu_control),
        .alu_result(ex_alu_result), .zero(ex_zero), .lt(ex_lt), .ltu(ex_ltu)
    );

    // Store data with forwarding (rs2 may depend on previous instr)
    logic [31:0] fwd_store_data;
    always_comb begin
        if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs2)
            fwd_store_data = ex_mem_alu_result;
        else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs2)
            fwd_store_data = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;
        else
            fwd_store_data = id_ex_rs2_data;
    end
    assign ex_store_data = fwd_store_data;

    // Byte enables (computed in MEM stage from EX/MEM reg)
    always_comb begin
        unique case (ex_mem_store_type)
            2'b01: ex_byte_enable = 4'b0001 << ex_mem_alu_result[1:0];
            2'b10: ex_byte_enable = (ex_mem_alu_result[1]) ? 4'b1100 : 4'b0011;
            default: ex_byte_enable = 4'b1111;
        endcase
    end

    // EX/MEM register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_write <= 1'b0;
        end else begin
            ex_mem_alu_result  <= ex_alu_result;
            ex_mem_rs2_data    <= fwd_store_data;
            ex_mem_rd          <= id_ex_rd;
            ex_mem_reg_write   <= id_ex_reg_write;
            ex_mem_mem_write   <= id_ex_mem_write;
            ex_mem_mem_to_reg  <= id_ex_mem_to_reg;
            ex_mem_load_ext    <= id_ex_load_ext;
            ex_mem_store_type  <= id_ex_store_type;
            ex_mem_exception   <= id_ex_exception;
            ex_mem_except_cause<= id_ex_except_cause;
            ex_mem_pc4         <= id_ex_pc4;
            ex_mem_jump_flag   <= id_ex_jump_flag;
        end
    end

    // ═══════════════════════════════════════════════════════════
    //  MEM: Memory access
    // ═══════════════════════════════════════════════════════════
    data_mem #(.DEPTH(2048)) u_data_mem (
        .clk, .addr(ex_mem_alu_result),
        .write_data(ex_mem_rs2_data),
        .mem_write(ex_mem_mem_write && !io_sel),
        .byte_enable(ex_byte_enable),
        .read_data(mem_read_data)
    );

    // Load extension
    always_comb begin
        unique case (ex_mem_load_ext)
            3'b000: mem_ext_data = mem_read_data;
            3'b001: mem_ext_data = {{24{mem_read_data[7]}},  mem_read_data[7:0]};
            3'b010: mem_ext_data = {{16{mem_read_data[15]}}, mem_read_data[15:0]};
            3'b011: mem_ext_data = {24'b0, mem_read_data[7:0]};
            3'b100: mem_ext_data = {16'b0, mem_read_data[15:0]};
            default: mem_ext_data = mem_read_data;
        endcase
    end

    // MEM/WB register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_reg_write <= 1'b0;
        end else begin
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
            mem_wb_jump_flag  <= ex_mem_jump_flag;
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_data   <= mem_ext_data;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_pc4        <= ex_mem_pc4;
        end
    end

    // ═══════════════════════════════════════════════════════════
    //  Hazard unit
    // ═══════════════════════════════════════════════════════════
    hazard u_hazard (
        .id_rs1(id_rs1), .id_rs2(id_rs2),
        .ex_rs1(id_ex_rs1), .ex_rs2(id_ex_rs2),
        .ex_rd(id_ex_rd),
        .ex_mem_read(id_ex_mem_read),
        .ex_mem_rd(ex_mem_rd), .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd(mem_wb_rd), .mem_wb_reg_write(mem_wb_reg_write),
        .forward_a, .forward_b,
        .stall(load_stall), .flush()
    );

    assign stall_f = load_stall;
    assign flush_f = id_branch_taken;

    // ═══════════════════════════════════════════════════════════
    //  Next PC logic
    // ═══════════════════════════════════════════════════════════
    always_comb begin
        if (id_branch_taken)
            next_pc = id_branch_target;
        else if (load_stall)
            next_pc = pc;           // don't advance
        else
            next_pc = pc_plus_4;
    end
endmodule
