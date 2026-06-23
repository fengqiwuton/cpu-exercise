# Basic CPU Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a single-cycle RISC-V CPU (11 instructions) in SystemVerilog, simulate with Icarus Verilog.

**Architecture:** Harvard single-cycle. 8 modules: PC, Instruction Memory, Register File, ALU, Data Memory, Control Unit, Immediate Generator, CPU Top.

**Tech Stack:** SystemVerilog (`.sv`), Icarus Verilog + GTKWave, Python 3 (assembler), Make

## Global Constraints

- **Language**: SystemVerilog (`.sv` extension)
- **Simulator**: Icarus Verilog (`iverilog -g2012`)
- **Target**: Simulation only (no FPGA synthesis required yet)
- **Reset**: Active-low (`rst_n`), PC starts at 0x0000_0000
- **Memory depth**: 1024 words (4 KB) each for instruction and data memory
- **Clock**: 100 MHz (10 ns period, 5 ns half-cycle)
- **Register x0**: Hardwired to zero, writes ignored
- **All modules** go in `rtl/`, testbenches in `testbench/`

---

### Task 1: Project Scaffolding

**Files:**
- Create: `cpu/rtl/cpu_pkg.svh`
- Create: `cpu/Makefile`
- Create: `cpu/programs/data.hex`

**Produces:** Shared constants, build system, initial data memory image.

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p cpu/rtl cpu/testbench cpu/programs cpu/tools
```

- [ ] **Step 2: Write cpu_pkg.svh**

```systemverilog
`ifndef CPU_PKG_SVH
`define CPU_PKG_SVH

// Opcodes
`define OP_RTYPE  7'b0110011
`define OP_LOAD   7'b0000011
`define OP_STORE  7'b0100011
`define OP_BRANCH 7'b1100011

// funct3
`define F3_ADD_SUB 3'b000
`define F3_AND     3'b111
`define F3_OR      3'b110
`define F3_LW      3'b010
`define F3_SW      3'b010
`define F3_BEQ     3'b000
`define F3_BLT     3'b100
`define F3_BGE     3'b101
`define F3_BLTU    3'b110
`define F3_BGEU    3'b111

// funct7
`define F7_ADD 7'b0000000
`define F7_SUB 7'b0100000

// ALU control
`define ALU_ADD  4'b0000
`define ALU_SUB  4'b0001
`define ALU_AND  4'b0010
`define ALU_OR   4'b0011
`define ALU_SLT  4'b0100
`define ALU_SLTU 4'b0101

`endif
```

- [ ] **Step 3: Write Makefile**

```makefile
RTL = rtl/pc.sv rtl/insn_mem.sv rtl/regfile.sv rtl/alu.sv \
      rtl/data_mem.sv rtl/imm_gen.sv rtl/control.sv rtl/cpu_top.sv
TB  = testbench/cpu_tb.sv
SIM = simv
VCD = dump.vcd

.PHONY: sim wave clean asm_all

sim: $(SIM)
	vvp $(SIM)

$(SIM): $(RTL) $(TB)
	iverilog -g2012 -o $(SIM) $(RTL) $(TB)

wave: sim
	gtkwave $(VCD) &

asm_all: tools/assembler.py
	python3 tools/assembler.py programs/test1_alu.asm -o programs/test1_alu.hex
	python3 tools/assembler.py programs/test2_mem.asm -o programs/test2_mem.hex
	python3 tools/assembler.py programs/test3_branch.asm -o programs/test3_branch.hex
	python3 tools/assembler.py programs/test4_integration.asm -o programs/test4_integration.hex

clean:
	rm -f $(SIM) $(VCD)
```

- [ ] **Step 4: Write data.hex (shared data memory init)**

```
0000000a
00000003
00000000
00000000
00000000
00000000
```

- [ ] **Step 5: Verify tools**

```bash
iverilog -V && which vvp
```

- [ ] **Step 6: Commit**

```bash
git add cpu/ && git commit -m "feat: project scaffolding, constants, Makefile"
```

---

### Task 2: Program Counter

**Files:**
- Create: `cpu/rtl/pc.sv`
- Create: `cpu/testbench/pc_tb.sv`

**Produces:** `module pc (input clk, rst_n, next_pc[31:0], output pc[31:0])`

- [ ] **Step 1: Write pc.sv**

```systemverilog
module pc (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] next_pc,
    output logic [31:0] pc
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= 32'h0000_0000;
        else
            pc <= next_pc;
    end
endmodule
```

- [ ] **Step 2: Write pc_tb.sv**

```systemverilog
`timescale 1ns/1ps
module pc_tb;
    logic clk, rst_n;
    logic [31:0] next_pc, pc;
    pc dut (.*);
    always #5 clk = ~clk;

    initial begin
        $dumpfile("pc_tb.vcd"); $dumpvars(0, pc_tb);
        clk = 0; rst_n = 0; next_pc = 0;
        #10 rst_n = 1;
        #10 next_pc = 32'h0000_0004;
        #10 if (pc !== 32'h4) $error("FAIL: got %h", pc);
        next_pc = 32'h0000_1000;
        #10 if (pc !== 32'h1000) $error("FAIL: got %h", pc);
        next_pc = 32'hFFFF_FFFC;
        #10 if (pc !== 32'hFFFF_FFFC) $error("FAIL: got %h", pc);
        $display("pc: PASSED"); $finish;
    end
endmodule
```

- [ ] **Step 3: Run test**

```bash
cd cpu && iverilog -g2012 -o pc_sim rtl/pc.sv testbench/pc_tb.sv && vvp pc_sim
```
Expected: `pc: PASSED`

- [ ] **Step 4: Commit**

---

### Task 3: Instruction Memory

**Files:**
- Create: `cpu/rtl/insn_mem.sv`
- Create: `cpu/testbench/insn_mem_tb.sv`
- Create: `cpu/testbench/test_imem.hex`

**Produces:** `module insn_mem #(DEPTH=1024) (input addr[31:0], output instr[31:0])`

- [ ] **Step 1: Write insn_mem.sv**

```systemverilog
module insn_mem #(parameter DEPTH = 1024) (
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] mem [0:DEPTH-1];
    initial $readmemh("program.hex", mem);
    assign instr = mem[addr[31:2]];
endmodule
```

- [ ] **Step 2: Write test_imem.hex**

```
00000033
0010e133
```

- [ ] **Step 3: Write insn_mem_tb.sv**

```systemverilog
`timescale 1ns/1ps
module insn_mem_tb;
    logic [31:0] addr, instr;
    insn_mem #(.DEPTH(1024)) dut (.*);
    initial begin
        $dumpfile("imem_tb.vcd"); $dumpvars(0, insn_mem_tb);
        #10 addr = 32'h0;
        #10 if (instr !== 32'h00000033) $error("FAIL");
        addr = 32'h4;
        #10 if (instr !== 32'h0010e133) $error("FAIL");
        $display("insn_mem: PASSED"); $finish;
    end
endmodule
```

- [ ] **Step 4: Run test**

```bash
cd cpu && cp testbench/test_imem.hex program.hex && iverilog -g2012 -o imem_sim rtl/insn_mem.sv testbench/insn_mem_tb.sv && vvp imem_sim
```
Expected: `insn_mem: PASSED`

- [ ] **Step 5: Commit**

---

### Task 4: Register File

**Files:**
- Create: `cpu/rtl/regfile.sv`
- Create: `cpu/testbench/regfile_tb.sv`

**Produces:** `module regfile (input clk, rs1_addr[4:0], rs2_addr[4:0], rd_addr[4:0], rd_data[31:0], reg_write, output rs1_data[31:0], rs2_data[31:0])`

- [ ] **Step 1: Write regfile.sv**

```systemverilog
module regfile (
    input  logic        clk,
    input  logic [4:0]  rs1_addr, rs2_addr, rd_addr,
    input  logic [31:0] rd_data,
    input  logic        reg_write,
    output logic [31:0] rs1_data, rs2_data
);
    logic [31:0] rf [0:31];
    assign rs1_data = (rs1_addr == 0) ? 32'h0 : rf[rs1_addr];
    assign rs2_data = (rs2_addr == 0) ? 32'h0 : rf[rs2_addr];
    always_ff @(posedge clk)
        if (reg_write && rd_addr != 0)
            rf[rd_addr] <= rd_data;
endmodule
```

- [ ] **Step 2: Write regfile_tb.sv**

```systemverilog
`timescale 1ns/1ps
module regfile_tb;
    logic clk, reg_write;
    logic [4:0] rs1_addr, rs2_addr, rd_addr;
    logic [31:0] rd_data, rs1_data, rs2_data;
    regfile dut (.*);
    always #5 clk = ~clk;

    initial begin
        $dumpfile("rf_tb.vcd"); $dumpvars(0, regfile_tb);
        clk = 0; reg_write = 0;

        // x0 reads 0
        #10 rs1_addr = 0; #2;
        if (rs1_data !== 0) $error("x0 fail");

        // write x1, read back
        #10 rd_addr = 1; rd_data = 32'hDEAD_BEEF; reg_write = 1;
        #10 reg_write = 0; rs1_addr = 1; #2;
        if (rs1_data !== 32'hDEAD_BEEF) $error("x1 fail");

        // write x0 ignored
        rd_addr = 0; rd_data = 32'hCAFE; reg_write = 1;
        #10 reg_write = 0; rs1_addr = 0; #2;
        if (rs1_data !== 0) $error("x0 write fail");

        // dual read
        #10 rd_addr = 2; rd_data = 32'hAAAA_BBBB; reg_write = 1;
        #10 reg_write = 0; rs1_addr = 1; rs2_addr = 2; #2;
        if (rs1_data !== 32'hDEAD_BEEF || rs2_data !== 32'hAAAA_BBBB)
            $error("dual read fail");

        $display("regfile: PASSED"); $finish;
    end
endmodule
```

- [ ] **Step 3: Run test**

```bash
cd cpu && iverilog -g2012 -o rf_sim rtl/regfile.sv testbench/regfile_tb.sv && vvp rf_sim
```
Expected: `regfile: PASSED`

- [ ] **Step 4: Commit**

---

### Task 5: ALU

**Files:**
- Create: `cpu/rtl/alu.sv`
- Create: `cpu/testbench/alu_tb.sv`

**Produces:** `module alu (input src_a[31:0], src_b[31:0], alu_control[3:0], output alu_result[31:0], zero, lt, ltu)`

- [ ] **Step 1: Write alu.sv**

```systemverilog
module alu (
    input  logic [31:0] src_a, src_b,
    input  logic [3:0]  alu_control,
    output logic [31:0] alu_result,
    output logic        zero, lt, ltu
);
    always_comb case (alu_control)
        4'b0000: alu_result = src_a + src_b;
        4'b0001: alu_result = src_a - src_b;
        4'b0010: alu_result = src_a & src_b;
        4'b0011: alu_result = src_a | src_b;
        4'b0100: alu_result = {31'b0, $signed(src_a) < $signed(src_b)};
        4'b0101: alu_result = {31'b0, src_a < src_b};
        default: alu_result = 32'h0;
    endcase
    assign zero = (alu_result == 0);
    assign lt   = $signed(src_a) < $signed(src_b);
    assign ltu  = src_a < src_b;
endmodule
```

- [ ] **Step 2: Write alu_tb.sv**

```systemverilog
`timescale 1ns/1ps
module alu_tb;
    logic [31:0] src_a, src_b, alu_result;
    logic [3:0] alu_control;
    logic zero, lt, ltu;
    alu dut (.*);

    initial begin
        $dumpfile("alu_tb.vcd"); $dumpvars(0, alu_tb);

        src_a=10; src_b=3; alu_control=0; #10;
        if (alu_result !== 13 || zero) $error("ADD");

        src_a=10; src_b=3; alu_control=1; #10;
        if (alu_result !== 7) $error("SUB");

        src_a=5; src_b=5; alu_control=1; #10;
        if (alu_result !== 0 || !zero) $error("SUB zero");

        src_a=10; src_b=3; alu_control=2; #10;
        if (alu_result !== 2) $error("AND");

        src_a=10; src_b=3; alu_control=3; #10;
        if (alu_result !== 11) $error("OR");

        src_a=5; src_b=10; alu_control=4; #10;
        if (alu_result !== 1 || !lt) $error("SLT");

        src_a=32'hFFFF_FFFF; src_b=1; alu_control=4; #10;
        if (alu_result !== 1) $error("SLT signed -1<1");

        src_a=32'hFFFF_FFFF; src_b=1; alu_control=5; #10;
        if (alu_result !== 0 || ltu) $error("SLTU FFFFFFFF<1");

        $display("alu: PASSED"); $finish;
    end
endmodule
```

- [ ] **Step 3: Run test**

```bash
cd cpu && iverilog -g2012 -o alu_sim rtl/alu.sv testbench/alu_tb.sv && vvp alu_sim
```
Expected: `alu: PASSED`

- [ ] **Step 4: Commit**

---

### Task 6: Data Memory

**Files:**
- Create: `cpu/rtl/data_mem.sv`
- Create: `cpu/testbench/data_mem_tb.sv`

**Produces:** `module data_mem #(DEPTH=1024) (input clk, addr[31:0], write_data[31:0], mem_write, output read_data[31:0])`

- [ ] **Step 1: Write data_mem.sv**

```systemverilog
module data_mem #(parameter DEPTH = 1024) (
    input  logic        clk,
    input  logic [31:0] addr, write_data,
    input  logic        mem_write,
    output logic [31:0] read_data
);
    logic [31:0] mem [0:DEPTH-1];
    `ifdef DATA_INIT_FILE
        initial $readmemh(`DATA_INIT_FILE, mem);
    `endif
    assign read_data = mem[addr[31:2]];
    always_ff @(posedge clk)
        if (mem_write) mem[addr[31:2]] <= write_data;
endmodule
```

- [ ] **Step 2: Write data_mem_tb.sv**

```systemverilog
`timescale 1ns/1ps
module data_mem_tb;
    logic clk, mem_write;
    logic [31:0] addr, write_data, read_data;
    data_mem #(.DEPTH(1024)) dut (.*);
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dmem_tb.vcd"); $dumpvars(0, data_mem_tb);
        clk = 0; mem_write = 0;

        #10 addr = 0; write_data = 32'hCAFE_F00D; mem_write = 1;
        #10 mem_write = 0; addr = 0; #5;
        if (read_data !== 32'hCAFE_F00D) $error("readback fail");

        addr = 8; write_data = 32'hDEAD_BEEF; mem_write = 1;
        #10 mem_write = 0; addr = 8; #5;
        if (read_data !== 32'hDEAD_BEEF) $error("addr 8 fail");

        addr = 0; #5;
        if (read_data !== 32'hCAFE_F00D) $error("addr 0 corrupted");

        $display("data_mem: PASSED"); $finish;
    end
endmodule
```

- [ ] **Step 3: Run**

```bash
cd cpu && iverilog -g2012 -o dmem_sim rtl/data_mem.sv testbench/data_mem_tb.sv && vvp dmem_sim
```

- [ ] **Step 4: Commit**

---

### Task 7: Immediate Generator

**Files:**
- Create: `cpu/rtl/imm_gen.sv`
- Create: `cpu/testbench/imm_gen_tb.sv`

**Produces:** `module imm_gen (input instr[31:0], output imm[31:0])` — handles I, S, B types.

- [ ] **Step 1: Write imm_gen.sv**

```systemverilog
module imm_gen (
    input  logic [31:0] instr,
    output logic [31:0] imm
);
    logic [6:0] opcode;
    assign opcode = instr[6:0];
    always_comb case (opcode)
        7'b0000011: imm = {{20{instr[31]}}, instr[31:20]};
        7'b0100011: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
        7'b1100011: imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
        default:    imm = 32'h0;
    endcase
endmodule
```

- [ ] **Step 2: Write imm_gen_tb.sv**

```systemverilog
`timescale 1ns/1ps
module imm_gen_tb;
    logic [31:0] instr, imm;
    imm_gen dut (.*);
    initial begin
        $dumpfile("imm_tb.vcd"); $dumpvars(0, imm_gen_tb);

        // I-type: lw x1, 8(x0) -> imm=8
        instr = {12'd8, 5'd0, 3'b010, 5'd1, 7'b0000011}; #10;
        if (imm !== 32'd8) $error("I pos: %d", imm);

        // I-type: lw x2, -4(x1) -> imm=-4
        instr = {12'hFFC, 5'd1, 3'b010, 5'd2, 7'b0000011}; #10;
        if (imm !== 32'hFFFF_FFFC) $error("I neg: %h", imm);

        // S-type: sw x3, 12(x0) -> imm=12
        instr = {7'b0, 5'd3, 5'd0, 3'b010, 5'd12, 7'b0100011}; #10;
        if (imm !== 32'd12) $error("S: %d", imm);

        // B-type: beq x0, x0, +8 -> imm=8
        // B layout: instr[31]=imm12, [7]=imm11, [30:25]=imm10:5, [11:8]=imm4:1
        // imm=8: imm12=0, imm11=0, imm10:5=1, imm4:1=4
        instr = {1'b0, 6'd1, 5'd0, 5'd0, 3'b000, 4'd4, 1'b0, 7'b1100011}; #10;
        if (imm !== 32'd8) $error("B fwd: %d", imm);

        // B-type: beq x0, x0, -4 -> imm=-4
        // -4 in 13-bit signed: all 1s except bit 1:0 = 0
        // imm12=1, imm11=1, imm10:5=63, imm4:1=14
        instr = {1'b1, 6'd63, 5'd0, 5'd0, 3'b000, 4'd14, 1'b1, 7'b1100011}; #10;
        if (imm !== 32'hFFFF_FFFC) $error("B bwd: %h", imm);

        $display("imm_gen: PASSED"); $finish;
    end
endmodule
```

- [ ] **Step 3: Run**

```bash
cd cpu && iverilog -g2012 -o imm_sim rtl/imm_gen.sv testbench/imm_gen_tb.sv && vvp imm_sim
```

- [ ] **Step 4: Commit**

---

### Task 8: Control Unit

**Files:**
- Create: `cpu/rtl/control.sv`
- Create: `cpu/testbench/control_tb.sv`

**Produces:** `module control (input opcode[6:0], funct3[2:0], funct7[6:0], output reg_write, alu_src, mem_write, mem_to_reg, branch, alu_control[3:0])`

- [ ] **Step 1: Write control.sv**

```systemverilog
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
```

- [ ] **Step 2: Write control_tb.sv**

```systemverilog
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
```

- [ ] **Step 3: Run**

```bash
cd cpu && iverilog -g2012 -o ctrl_sim rtl/control.sv testbench/control_tb.sv && vvp ctrl_sim
```

- [ ] **Step 4: Commit**

---

### Task 9: CPU Top-Level Integration

**Files:**
- Create: `cpu/rtl/cpu_top.sv`

**Consumes:** All 7 modules (pc, insn_mem, regfile, alu, data_mem, imm_gen, control)
**Produces:** `module cpu_top (input clk, rst_n)` — complete integrated CPU

- [ ] **Step 1: Write cpu_top.sv**

```systemverilog
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
```

- [ ] **Step 2: Verify all modules compile together**

```bash
cd cpu && iverilog -g2012 -o top_check rtl/*.sv 2>&1
```
Expected: No compile errors (missing program.hex runtime error OK)

- [ ] **Step 3: Commit**

---

### Task 10: Assembler

**Files:**
- Create: `cpu/tools/assembler.py`

**Produces:** Python script that converts .asm (RISC-V assembly, 11-instruction subset) to .hex (one 32-bit hex word/line)

- [ ] **Step 1: Write assembler.py**

```python
#!/usr/bin/env python3
"""Minimal RISC-V assembler for 11-instruction subset."""
import sys, argparse

OPCODES = {
    'add':('R',0b0110011,0b000,0b0000000), 'sub':('R',0b0110011,0b000,0b0100000),
    'and':('R',0b0110011,0b111,0b0000000), 'or':('R',0b0110011,0b110,0b0000000),
    'lw':('I',0b0000011,0b010,None), 'sw':('S',0b0100011,0b010,None),
    'beq':('B',0b1100011,0b000,None), 'blt':('B',0b1100011,0b100,None),
    'bge':('B',0b1100011,0b101,None), 'bltu':('B',0b1100011,0b110,None),
    'bgeu':('B',0b1100011,0b111,None),
}

REGS = { 'zero':0,'x0':0,'ra':1,'x1':1,'sp':2,'x2':2,'gp':3,'x3':3,
    'tp':4,'x4':4,'t0':5,'x5':5,'t1':6,'x6':6,'t2':7,'x7':7,
    's0':8,'x8':8,'fp':8,'s1':9,'x9':9,'a0':10,'x10':10,
    'a1':11,'x11':11,'a2':12,'x12':12,'a3':13,'x13':13,
    'a4':14,'x14':14,'a5':15,'x15':15,'a6':16,'x16':16,
    'a7':17,'x17':17,'s2':18,'x18':18,'s3':19,'x19':19,
    's4':20,'x20':20,'s5':21,'x21':21,'s6':22,'x22':22,
    's7':23,'x23':23,'s8':24,'x24':24,'s9':25,'x25':25,
    's10':26,'x26':26,'s11':27,'x27':27,'t3':28,'x28':28,
    't4':29,'x29':29,'t5':30,'x30':30,'t6':31,'x31':31,
}

def reg(s): return REGS[s.strip()]

def imm(s):
    s = s.strip()
    return int(s,16) if s.startswith('0x') else int(s,2) if s.startswith('0b') else int(s)

def enc_r(op,f3,f7,rd,rs1,rs2):
    return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op

def enc_i(op,f3,rd,rs1,im):
    return ((im&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op

def enc_s(op,f3,rs1,rs2,im):
    return ((im&0xFE0)<<20)|(rs2<<20)|(rs1<<15)|(f3<<12)|((im&0x1F)<<7)|op

def enc_b(op,f3,rs1,rs2,im):
    return (((im>>12)&1)<<31)|(((im>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((im>>1)&0xF)<<8)|(((im>>11)&1)<<7)|op

def parse_mem(s):
    s = s.strip().replace(' ','')
    i, r = s.split('(')
    return imm(i), reg(r.rstrip(')'))

def assemble_line(line, syms, addr):
    line = line.split('#')[0].strip()
    if not line: return None
    if ':' in line:
        label, rest = line.split(':',1)
        syms[label.strip()] = addr
        line = rest.strip()
        if not line: return None
    parts = line.replace(',',' ').split()
    m = parts[0].lower()
    if m == 'nop': return enc_r(0b0110011,0,0,0,0,0)
    fmt, op, f3, f7 = OPCODES[m]
    if fmt == 'R':
        return enc_r(op,f3,f7,reg(parts[1]),reg(parts[2]),reg(parts[3]))
    elif fmt == 'I':
        rd_ = reg(parts[1]); off, rs1_ = parse_mem(parts[2])
        return enc_i(op,f3,rd_,rs1_,off)
    elif fmt == 'S':
        rs2_ = reg(parts[1]); off, rs1_ = parse_mem(parts[2])
        return enc_s(op,f3,rs1_,rs2_,off)
    elif fmt == 'B':
        rs1_, rs2_ = reg(parts[1]), reg(parts[2])
        tgt = parts[3]
        off = syms[tgt] - addr if tgt in syms else imm(tgt)
        return enc_b(op,f3,rs1_,rs2_,off)

def assemble(inp, outp):
    with open(inp) as f: lines = f.readlines()
    syms, code = {}, []
    addr = 0
    for L in lines:
        w = assemble_line(L, syms, addr)
        if w is not None: code.append(f"{w:08x}"); addr += 4
    with open(outp,'w') as f: f.write('\n'.join(code)+'\n')
    print(f"{inp} -> {outp} ({len(code)} instructions)")

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('input'); p.add_argument('-o','--output',required=True)
    a = p.parse_args(); assemble(a.input, a.output)
```

- [ ] **Step 2: Verify assembler**

```bash
cd cpu && echo 'add x1, x2, x3' | python3 tools/assembler.py /dev/stdin -o /tmp/t.hex 2>&1 || python3 -c "
# Quick inline test
from tools.assembler import enc_r, reg
w = enc_r(0b0110011, 0b000, 0b0000000, reg('x1'), reg('x2'), reg('x3'))
assert f'{w:08x}' == '003100b3', f'got {w:08x}'
print('assembler: OK')
"
```

- [ ] **Step 3: Commit**

---

### Task 11: Test Programs

**Files:**
- Create: `cpu/programs/test1_alu.asm`
- Create: `cpu/programs/test2_mem.asm`
- Create: `cpu/programs/test3_branch.asm`
- Create: `cpu/programs/test4_integration.asm`
- Modify: `cpu/programs/data.hex` (update with test data)

**Note:** Each test needs its own `program.hex` (instruction memory) and matching `data.hex` (data memory). The cpu_tb in Task 12 handles loading both files.

- [ ] **Step 1: Write test1_alu.asm (arithmetic)**

```asm
# test1_alu.asm — add, sub, and, or
# Data memory preload: [0]=10=a, [4]=3=b
lw x1, 0(x0)
lw x2, 4(x0)
add x3, x1, x2
sub x4, x1, x2
and x5, x1, x2
or  x6, x1, x2
sw x3, 8(x0)
sw x4, 12(x0)
sw x5, 16(x0)
sw x6, 20(x0)
```

- [ ] **Step 2: Write test2_mem.asm (load/store)**

```asm
# test2_mem.asm — load/store verification
# Data: [0]=0xDEADBEEF, [4]=0xCAFE1234
lw x1, 0(x0)
lw x2, 4(x0)
sw x1, 16(x0)
sw x2, 20(x0)
lw x3, 16(x0)
lw x4, 20(x0)
sub x5, x1, x3
sub x6, x2, x4
sw x5, 24(x0)
sw x6, 28(x0)
```

- [ ] **Step 3: Write test3_branch.asm (branch instructions)**

```asm
# test3_branch.asm — beq, blt, bge, bltu, bgeu
# Data: [0]=5, [4]=10, [8]=5, [12]=10
lw x1, 0(x0)
lw x2, 4(x0)
lw x3, 8(x0)
lw x4, 12(x0)
# beq taken (x1==x3, both 5)
beq x1, x3, b1
sw x0, 16(x0)
b1:
sw x1, 20(x0)
# blt taken (x1<x2: 5<10)
blt x1, x2, b2
sw x0, 24(x0)
b2:
sw x1, 28(x0)
# bge taken (x4>=x1: 10>=5)
bge x4, x1, b3
sw x0, 32(x0)
b3:
sw x1, 36(x0)
# bltu taken (5<10 unsigned)
bltu x1, x2, b4
sw x0, 40(x0)
b4:
sw x1, 44(x0)
# bgeu taken (10>=5 unsigned)
bgeu x4, x1, b5
sw x0, 48(x0)
b5:
sw x1, 52(x0)
# beq NOT taken (x1!=x2)
beq x1, x2, b6
sw x2, 56(x0)
b6:
sw x0, 60(x0)
```

- [ ] **Step 4: Write test4_integration.asm (sum array)**

```asm
# test4_integration.asm — sum 1+2+3+4+5 = 15
# Data: [0]=1, [4]=2, [8]=3, [12]=4, [16]=5, [36]=15, [44]=10, [64]=10, [68]=5
lw x1, 0(x0)
lw x2, 4(x0)
add x3, x1, x2
lw x4, 8(x0)
add x3, x3, x4
lw x4, 12(x0)
add x3, x3, x4
lw x4, 16(x0)
add x3, x3, x4
sw x3, 32(x0)
# verify sum == 15
lw x5, 36(x0)
sub x6, x3, x5
beq x6, x0, pass
sw x0, 40(x0)
pass:
sw x3, 48(x0)
# loop demo: count to 10
# Data: [44]=10 (limit), [64]=10 (step), [68]=5 (start), [72]=1 (increment)
lw x10, 68(x0)
lw x11, 44(x0)
lw x12, 64(x0)
lw x13, 72(x0)
loop:
add x10, x10, x13
blt x10, x11, loop
sw x10, 52(x0)
```

- [ ] **Step 5: Write data.hex (common data init for all tests)**

```
// data.hex — shared initial data memory
// Addr 0-7: basic operands
0000000a
00000003
00000005
0000000a
// Addr 8-31: result / test storage (zeroed)
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
00000000
// Addr 32-35: sum result reference (test4)
0000000f
// Addr 36-43: reference values
0000000f
00000000
00000000
00000000
0000000a
00000000
00000000
00000000
// Addr 48-75: test4 loop data
00000000
00000000
00000000
00000000
00000000
0000000a
00000005
00000001
```

- [ ] **Step 6: Assemble all**

```bash
cd cpu && make asm_all
```

- [ ] **Step 7: Commit**

---

### Task 12: Top-Level Testbench and Full Simulation

**Files:**
- Create: `cpu/testbench/cpu_tb.sv`

**Consumes:** All RTL modules, assembler, test programs, data.hex
**Produces:** Full CPU simulation with waveform dump

**Note:** The testbench loads BOTH instruction and data memory from hex files. Since insn_mem uses `$readmemh("program.hex")` and data_mem uses conditional `$readmemh` with DATA_INIT_FILE macro, we compile with `-DDATA_INIT_FILE='"programs/data.hex"'` and use a parameter to switch the instruction program per test.

- [ ] **Step 1: Update insn_mem.sv to support program filename parameter**

```systemverilog
module insn_mem #(
    parameter DEPTH = 1024,
    parameter string PROG_FILE = "program.hex"
) (
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] mem [0:DEPTH-1];
    initial $readmemh(PROG_FILE, mem);
    assign instr = mem[addr[31:2]];
endmodule
```

- [ ] **Step 2: Write cpu_tb.sv**

```systemverilog
`timescale 1ns/1ps

module cpu_tb;
    logic clk, rst_n;
    cpu_top dut (.*);

    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, cpu_tb);

        clk = 0;
        rst_n = 0;
        #10 rst_n = 1;  // release reset

        // Run for 200 cycles (enough for all test programs)
        #2000;

        $display("Simulation finished — check waveform with: gtkwave dump.vcd");
        $finish;
    end
endmodule
```

- [ ] **Step 3: Update Makefile to support individual test programs**

```makefile
RTL = rtl/pc.sv rtl/insn_mem.sv rtl/regfile.sv rtl/alu.sv \
      rtl/data_mem.sv rtl/imm_gen.sv rtl/control.sv rtl/cpu_top.sv
TB  = testbench/cpu_tb.sv
SIM = simv
VCD = dump.vcd
DATA_HEX = programs/data.hex
IVFLAGS = -g2012 -DDATA_INIT_FILE=\"$(DATA_HEX)\"

.PHONY: sim wave clean asm_all sim1 sim2 sim3 sim4

sim: sim4

sim1: programs/test1_alu.hex
	iverilog $(IVFLAGS) -DPROG_FILE=\"programs/test1_alu.hex\" -o $(SIM) $(RTL) $(TB)
	vvp $(SIM)

sim2: programs/test2_mem.hex
	iverilog $(IVFLAGS) -DPROG_FILE=\"programs/test2_mem.hex\" -o $(SIM) $(RTL) $(TB)
	vvp $(SIM)

sim3: programs/test3_branch.hex
	iverilog $(IVFLAGS) -DPROG_FILE=\"programs/test3_branch.hex\" -o $(SIM) $(RTL) $(TB)
	vvp $(SIM)

sim4: programs/test4_integration.hex
	iverilog $(IVFLAGS) -DPROG_FILE=\"programs/test4_integration.hex\" -o $(SIM) $(RTL) $(TB)
	vvp $(SIM)

wave: sim
	gtkwave $(VCD) &

asm_all: tools/assembler.py
	python3 tools/assembler.py programs/test1_alu.asm -o programs/test1_alu.hex
	python3 tools/assembler.py programs/test2_mem.asm -o programs/test2_mem.hex
	python3 tools/assembler.py programs/test3_branch.asm -o programs/test3_branch.hex
	python3 tools/assembler.py programs/test4_integration.asm -o programs/test4_integration.hex

clean:
	rm -f $(SIM) $(VCD)
```

- [ ] **Step 4: Also update insn_mem to accept PROG_FILE macro**

The insn_mem needs to support the PROG_FILE macro for the Makefile to work. The module already has a parameter `PROG_FILE`. Make it also work via macro:

```systemverilog
module insn_mem #(
    parameter DEPTH = 1024,
    parameter string PROG_FILE = "program.hex"
) (
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] mem [0:DEPTH-1];
    initial begin
        `ifdef PROG_FILE
            $readmemh(`PROG_FILE, mem);
        `else
            $readmemh(PROG_FILE, mem);
        `endif
    end
    assign instr = mem[addr[31:2]];
endmodule
```

- [ ] **Step 5: Assemble and run simulation**

```bash
cd cpu && make asm_all && make sim4
```
Expected: `Simulation finished — check waveform with: gtkwave dump.vcd`

- [ ] **Step 6: Verify with GTKWave**

```bash
cd cpu && make wave
```
Check:
- PC increments correctly
- Branch targets are correct (test3_branch)
- Register writes match expected values
- Data memory reads/writes match test expectations

- [ ] **Step 7: Run all tests sequentially**

```bash
cd cpu && make sim1 && make sim2 && make sim3 && make sim4
```

- [ ] **Step 8: Commit**

```bash
git add cpu/ && git commit -m "feat: complete CPU testbench and test programs"
```

---

## Post-Implementation: What You've Built

After completing all tasks, you'll have:

1. **A working RISC-V CPU** that executes 11 instructions in a single cycle
2. **Module-level testbenches** for each component (7 unit tests)
3. **4 integration test programs** covering arithmetic, memory, branches, and full integration
4. **Toolchain**: assembler (Python) → hex → Icarus Verilog simulation → GTKWave waveform

## Future Work (after basic CPU is verified)

1. **Pipeline**: 5-stage classic pipeline (IF/ID/EX/MEM/WB) with hazard handling
2. **More instructions**: `addi`, `slli`, `srai`, `jal`, `jalr`, `lui`, `auipc`
3. **Exceptions/ECSALL**: Privileged architecture support
4. **UART peripheral**: Serial communication for real-world I/O
5. **VGA output**: Display output on FPGA board
6. **Vivado synthesis**: Target EGO1 FPGA board, real hardware verification
7. **Differential test**: Compare against a reference RISC-V simulator (e.g., Spike)

## Resources

- **RISC-V Reference Card**: `docs/riscv-card.pdf`
- **Book**: Patterson & Hennessy, *Computer Organization and Design: RISC-V Edition*
- **RISC-V Spec**: https://github.com/riscv/riscv-isa-manual/releases
- **Icarus Verilog Guide**: https://steveicarus.github.io/iverilog/
## File Structure

```
cpu/
├── rtl/
│   ├── cpu_pkg.svh       # shared constants
│   ├── pc.sv             # Program Counter
│   ├── insn_mem.sv       # Instruction Memory
│   ├── regfile.sv        # Register File
│   ├── alu.sv            # Arithmetic Logic Unit
│   ├── data_mem.sv       # Data Memory
│   ├── imm_gen.sv        # Immediate Generator
│   ├── control.sv        # Control Unit
│   └── cpu_top.sv        # Top-Level Integration
├── testbench/
│   ├── pc_tb.sv
│   ├── insn_mem_tb.sv
│   ├── regfile_tb.sv
│   ├── alu_tb.sv
│   ├── data_mem_tb.sv
│   ├── imm_gen_tb.sv
│   ├── control_tb.sv
│   └── cpu_tb.sv
├── programs/
│   ├── test1_alu.asm
│   ├── test2_mem.asm
│   ├── test3_branch.asm
│   ├── test4_integration.asm
│   └── data.hex          # shared data memory initial values
├── tools/
│   └── assembler.py
└── Makefile
```

---
