# MineCPU 基础 CPU — 全流程走读

> 目标：理解每个文件的作用，亲手仿真验证 CPU 功能。

## 目录

1. [项目总览](#1-项目总览)
2. [RTL 源码逐文件解释](#2-rtl-源码逐文件解释)
3. [Testbench 解释](#3-testbench-解释)
4. [汇编器](#4-汇编器)
5. [测试程序](#5-测试程序)
6. [动手验证](#6-动手验证)
7. [波形调试](#7-波形调试)

---

## 1. 项目总览

```
E:\CPU\cpu\
├── rtl/                       # CPU 硬件源码（需要理解的核心）
│   ├── cpu_pkg.svh            #   宏定义常量
│   ├── pc.sv                  #   程序计数器
│   ├── insn_mem.sv            #   指令存储器
│   ├── regfile.sv             #   寄存器堆（32个32位寄存器）
│   ├── alu.sv                 #   算术逻辑单元
│   ├── data_mem.sv            #   数据存储器
│   ├── imm_gen.sv             #   立即数生成器
│   ├── control.sv             #   控制单元（指令译码）
│   └── cpu_top.sv             #   顶层集成（数据通路连线）
├── testbench/                 # 仿真测试
│   ├── pc_tb.sv ~ control_tb.sv  # 各模块单元测试
│   └── cpu_tb.sv              # 整CPU自检验测试
├── programs/                  # 测试程序
│   ├── test1_alu.asm          #   算术指令测试
│   ├── test2_mem.asm          #   访存指令测试
│   ├── test3_branch.asm       #   分支指令测试
│   ├── test4_integration.asm  #   综合测试
│   ├── *.hex                  #   汇编后的机器码
│   └── data.hex               #   数据存储器初始值
├── tools/
│   └── assembler.py           # 汇编器（.asm → .hex）
└── Makefile                   # 一键仿真
```

**我们实现了什么？**

一个能执行 11 条 RISC-V 指令的单周期 CPU：

| 类型 | 指令 | 作用 |
|------|------|------|
| 算术 | `add`, `sub`, `and`, `or` | 寄存器运算 |
| 访存 | `lw` (读内存), `sw` (写内存) | 数据读写 |
| 分支 | `beq`, `blt`, `bge`, `bltu`, `bgeu` | 条件跳转 |

架构：**Harvard 结构**（指令存储和数据存储分开）、**单周期**（1 条指令 = 1 个时钟周期）。

---

## 2. RTL 源码逐文件解释

### 2.1 `cpu_pkg.svh` — 常量定义

```systemverilog
`define OP_RTYPE  7'b0110011   // R-type 指令的 opcode（add/sub/and/or）
`define OP_LOAD   7'b0000011   // lw 的 opcode
`define OP_STORE  7'b0100011   // sw 的 opcode
`define OP_BRANCH 7'b1100011   // 分支指令的 opcode

`define ALU_ADD   4'b0000      // ALU 加法操作码
`define ALU_SUB   4'b0001      // ALU 减法操作码
// ... 等等
```

**作用**：给操作码、funct3、funct7、ALU 控制信号起名字，避免在代码里写 `7'b0110011` 这种"魔数"。

> 你可以打开这个文件对照着看后面的 control.sv。

---

### 2.2 `pc.sv` — 程序计数器（Program Counter）

```systemverilog
module pc (
    input  logic        clk,        // 时钟
    input  logic        rst_n,      // 复位（低有效）
    input  logic [31:0] next_pc,    // 下一条指令地址
    output logic [31:0] pc          // 当前指令地址
);
```

**工作原理**：
- 每个时钟上升沿，`pc <= next_pc`
- 复位时，`pc <= 0x0000_0000`（程序从地址 0 开始）
- `next_pc` 由上层（cpu_top）决定：顺序执行时 = `pc+4`，跳转时 = 分支目标地址

**类比**：PC 就像读书时的"当前读到第几行"。正常情况下读完一行（+4 字节）继续下一行；遇到跳转指令就跳到指定行。

**为什么是 +4？** RISC-V 每条指令固定 32 位 = 4 字节。所以下一条指令地址 = 当前地址 + 4。

---

### 2.3 `insn_mem.sv` — 指令存储器

```systemverilog
module insn_mem #(
    parameter DEPTH = 1024,          // 存 1024 条指令
    parameter string PROG_FILE = "program.hex"
) (
    input  logic [31:0] addr,        // PC 送来的地址
    output logic [31:0] instr        // 读出的 32 位指令
);
```

**工作原理**：
- 组合逻辑（不涉及时钟）：给地址，立即返回该地址的指令
- 仿真启动时用 `$readmemh` 从 `program.hex` 加载机器码
- `addr[31:2]` 取地址的高 30 位作为索引（因为指令 4 字节对齐，低 2 位永远是 0）

**理解要点**：这是 CPU 的"只读代码区"。PC 指向哪里就从这里取哪条指令。

---

### 2.4 `regfile.sv` — 寄存器堆

```systemverilog
module regfile (
    input  logic        clk,
    input  logic [4:0]  rs1_addr,    // 源寄存器 1 编号 (5位 → 32个寄存器)
    input  logic [4:0]  rs2_addr,    // 源寄存器 2 编号
    input  logic [4:0]  rd_addr,     // 目标寄存器编号
    input  logic [31:0] rd_data,     // 要写入的数据
    input  logic        reg_write,   // 写使能
    output logic [31:0] rs1_data,    // 读出的数据 1
    output logic [31:0] rs2_data     // 读出的数据 2
);
```

**工作原理**：
- **读**：组合逻辑，给寄存器编号立即返回数据。`x0` 硬连线返回 0
- **写**：时钟上升沿，如果 `reg_write=1` 且 `rd_addr≠0`，就把 `rd_data` 写进对应寄存器
- 两个读端口 + 一个写端口：可以同时读两个寄存器

**理解要点**：
- `x0` (zero) 永远是 0，写不进去——这是 RISC-V 的设计，提供常数 0
- 例如 `add x3, x1, x2`：读 x1、x2，结果写 x3
- 5 位地址 = 2^5 = 32 个寄存器

---

### 2.5 `alu.sv` — 算术逻辑单元

```systemverilog
module alu (
    input  logic [31:0] src_a, src_b,   // 两个操作数
    input  logic [3:0]  alu_control,    // 操作选择
    output logic [31:0] alu_result,     // 计算结果
    output logic        zero, lt, ltu   // 标志位
);
```

**6 种操作**：

| alu_control | 操作 | 说明 |
|-------------|------|------|
| `0000` | ADD | 加法 |
| `0001` | SUB | 减法 |
| `0010` | AND | 按位与 |
| `0011` | OR | 按位或 |
| `0100` | SLT | 有符号比较 (src_a < src_b ? 1 : 0) |
| `0101` | SLTU | 无符号比较 |

**3 个标志位**：
- `zero`：结果为 0 时为 1（用于 beq：两数相减得 0 说明相等）
- `lt`：有符号小于（用于 blt/bge）
- `ltu`：无符号小于（用于 bltu/bgeu）

**理解要点**：ALU 是"计算器"。它不关心这是什么指令，只根据 `alu_control` 做对应运算。标志位供后续分支判断使用。

---

### 2.6 `data_mem.sv` — 数据存储器

```systemverilog
module data_mem #(parameter DEPTH = 1024) (
    input  logic        clk,
    input  logic [31:0] addr,          // 地址（来自 ALU 结果）
    input  logic [31:0] write_data,    // 要写入的数据
    input  logic        mem_write,     // 写使能
    output logic [31:0] read_data      // 读出的数据
);
```

**工作原理**：
- **读**：组合逻辑，给地址立即返回数据
- **写**：时钟上升沿，`mem_write=1` 时把 `write_data` 写入 `addr` 位置
- 仿真时可从 `data.hex` 预加载初始值

**与 insn_mem 的区别**：insn_mem 只读不写（代码区），data_mem 可读可写（数据区）。这就是 Harvard 结构。

---

### 2.7 `imm_gen.sv` — 立即数生成器

```systemverilog
module imm_gen (
    input  logic [31:0] instr,    // 32 位指令
    output logic [31:0] imm       // 符号扩展到 32 位的立即数
);
```

**工作原理**：检查指令的 opcode，根据指令格式从不同位段提取立即数，并符号扩展到 32 位。

| opcode | 格式 | 用途 | 立即数位段 |
|--------|------|------|-----------|
| `0000011` | I-type | lw | `instr[31:20]` |
| `0100011` | S-type | sw | `instr[31:25]` + `instr[11:7]` |
| `1100011` | B-type | 分支 | 打散在多个位段 |

**理解要点**：
- "立即数"就是直接写在指令里的常数。比如 `lw x1, 8(x2)` 里的 `8`
- RISC-V 为了复用硬件，把 S 型和 B 型的立即数打散存放。ImmGen 负责把它们拼回来
- B 型的 imm bit 0 固定为 0（因为指令地址总是 2 字节对齐）

---

### 2.8 `control.sv` — 控制单元（指令译码）

```systemverilog
module control (
    input  logic [6:0] opcode,     // 指令的 [6:0] 位
    input  logic [2:0] funct3,     // 指令的 [14:12] 位
    input  logic [6:0] funct7,     // 指令的 [31:25] 位
    output logic        reg_write, alu_src, mem_write, mem_to_reg, branch,
    output logic [3:0]  alu_control
);
```

**工作原理**：纯组合逻辑。看 opcode / funct3 / funct7 三个字段，输出 5 个控制信号 + 1 个 ALU 操作选择。

**6 个输出信号的含义**：

| 信号 | 全称 | 作用 |
|------|------|------|
| `reg_write` | Register Write | 1=本条指令要写寄存器 |
| `alu_src` | ALU Source | 0=ALU 的 B 口来自寄存器；1=来自立即数 |
| `mem_write` | Memory Write | 1=本条指令要写数据内存（仅 sw）|
| `mem_to_reg` | Memory to Register | 0=寄存器写回来源是 ALU 结果；1=来源是内存读出（仅 lw）|
| `branch` | Branch | 1=本条是分支指令 |
| `alu_control` | ALU Control | 选择 ALU 做什么运算 |

**真值表**（这是整个 CPU 的"大脑"）：

| 指令 | opcode | reg_write | alu_src | mem_write | mem_to_reg | branch | alu_control |
|------|--------|-----------|---------|-----------|------------|--------|-------------|
| add | 0110011 | 1 | 0 | 0 | 0 | 0 | ADD |
| sub | 0110011 | 1 | 0 | 0 | 0 | 0 | SUB |
| and | 0110011 | 1 | 0 | 0 | 0 | 0 | AND |
| or | 0110011 | 1 | 0 | 0 | 0 | 0 | OR |
| lw | 0000011 | 1 | 1 | 0 | 1 | 0 | ADD |
| sw | 0100011 | 0 | 1 | 1 | — | 0 | ADD |
| beq | 1100011 | 0 | 0 | 0 | — | 1 | SUB |
| blt/bge | 1100011 | 0 | 0 | 0 | — | 1 | SLT |
| bltu/bgeu | 1100011 | 0 | 0 | 0 | — | 1 | SLTU |

**理解要点**：
- 这就是"译码"过程：CPU 看到一串 0/1，需要知道这是什么指令、该怎么处理
- 例如看到 opcode=`0000011`，就知道是 lw：需要读内存（mem_to_reg=1）、用立即数算地址（alu_src=1）、结果写寄存器（reg_write=1）

---

### 2.9 `cpu_top.sv` — 顶层集成（数据通路）

这是最大也是最重要的文件。它把 7 个子模块像积木一样连接起来。

**你可以对照这个图来看 `cpu_top.sv`：**

```
PC ──→ InsnMem ──→ Control (生成控制信号)
  │       │
  │       ├──→ ImmGen (提取立即数)
  │       │
  │       ├──→ RegFile (读 rs1, rs2) ──→ ALU (计算) ──→ DataMem (访存) ──→ RegFile (写回)
  │       │                                    │
  │       └────────────────────────────────────┤
  │                                            │
  └── PC+4 ────────────────────────────────────┤
          branch_target ────────────────────────┘ (PCSrc mux)
```

**数据通路的关键路径（以 `add x3, x1, x2` 为例）**：

1. **取指**：PC → insn_mem → 取出 `add x3, x1, x2` 的机器码
2. **译码**：control 看 opcode=0110011 → reg_write=1, alu_src=0, ALU_control=ADD
3. **读寄存器**：rs1_addr=x1, rs2_addr=x2 → RegFile 输出 x1 和 x2 的值
4. **执行**：ALU 把两个值相加
5. **写回**：mem_to_reg=0 → 选 ALU 结果 → 写进 x3
6. **更新 PC**：pc_src=0 → PC+4（顺序执行下一条）

**3 个多路选择器（Mux）**：

| Mux | 位置 | 选择 |
|-----|------|------|
| ALUSrc | ALU 的 B 输入端 | rs2 寄存器值 还是 立即数 |
| MemtoReg | RegFile 写数据端 | ALU 结果 还是 内存读出 |
| PCSrc | PC 下一值 | PC+4 还是 分支目标 |

**分支判断逻辑**（在 cpu_top 末尾）：

```systemverilog
pc_src = branch & (
    (funct3==000 & zero)  |  // beq: 两数相等
    (funct3==100 & lt)    |  // blt: 有符号小于
    (funct3==101 & ~lt)   |  // bge: 有符号大于等于
    (funct3==110 & ltu)   |  // bltu: 无符号小于
    (funct3==111 & ~ltu)     // bgeu: 无符号大于等于
);
```

**理解要点**：cpu_top 是"接线员"。它不做什么运算，只管把各模块的输入输出连对。你写新指令时主要改这里和控制单元。

---

## 3. Testbench 解释

### 单元测试（pc_tb.sv ~ control_tb.sv）

每个模块有一个对应的 `*_tb.sv`，测试该模块是否单独工作正确：

```
iverilog -g2012 -o pc_sim rtl/pc.sv testbench/pc_tb.sv && vvp pc_sim
```

验证思路：给输入，检查输出。以 `alu_tb.sv` 为例：

- 输入 src_a=10, src_b=3, alu_control=ADD
- 期望输出 alu_result=13, zero=0
- 如果不符，`$error(...)` 报错

### 顶层测试 `cpu_tb.sv`

这是整 CPU 的测试。它会：
1. 生成时钟（10ns 周期）和复位信号
2. 例化整个 cpu_top
3. 运行 600ns（足够任何测试程序跑完）
4. 用层次化引用 `dut.u_data_mem.mem[...]` 检查内存里的结果是否正确

关键参数：100MHz 时钟 = 10ns 周期 = 5ns 高 + 5ns 低。

---

## 4. 汇编器

`tools/assembler.py` — 把汇编转成机器码。

**支持语法**：
```asm
add x1, x2, x3       # R-type: 寄存器运算
lw x1, 8(x2)         # I-type: 读内存
sw x1, 8(x2)         # S-type: 写内存
beq x1, x2, label    # B-type: 分支
label:               # 标签（两遍汇编自动计算偏移）
```

**工作方式**：
- 第一遍：收集所有标签的地址
- 第二遍：翻译每条指令，标签引用替换为实际偏移量

**验证汇编器本身**：
```bash
cd /e/CPU/cpu
# 测试一条指令
echo 'add x1, x2, x3' | python3 tools/assembler.py /dev/stdin -o /tmp/t.hex
cat /tmp/t.hex
# 应该输出: 003100b3
```

---

## 5. 测试程序

### test1_alu.asm — 算术指令
```asm
lw x1, 0(x0)      # x1 = mem[0] = 10
lw x2, 4(x0)      # x2 = mem[4] = 3
add x3, x1, x2    # x3 = 13
sub x4, x1, x2    # x4 = 7
and x5, x1, x2    # x5 = 2  (10 & 3 = 2)
or  x6, x1, x2    # x6 = 11 (10 | 3 = 11)
sw x3, 8(x0)      # mem[8] = 13
sw x4, 12(x0)     # mem[12] = 7
sw x5, 16(x0)     # mem[16] = 2
sw x6, 20(x0)     # mem[20] = 11
```

### test2_mem.asm — 访存指令
```asm
lw x1, 64(x0)     # x1 = mem[0x40] = 0xDEADBEEF
lw x2, 68(x0)     # x2 = mem[0x44] = 0xCAFE1234
sw x1, 80(x0)     # 写回不同地址
sw x2, 84(x0)
lw x3, 80(x0)     # 读回来
lw x4, 84(x0)
sub x5, x1, x3    # 应该 = 0（数据一致）
sub x6, x2, x4    # 应该 = 0
```

### test3_branch.asm — 分支指令
测试全部 5 种分支类型，每种都验证"跳转"和"不跳转"两种情况：
- `beq`：相等则跳
- `blt`：有符号小于则跳
- `bge`：有符号大于等于则跳
- `bltu`：无符号小于则跳
- `bgeu`：无符号大于等于则跳

### test4_integration.asm — 综合测试
计算 1+2+3+4+5，结果写入内存，再用 beq 验证结果等于 15。

---

## 6. 动手验证

### 前提条件

```bash
# 确保 Icarus Verilog 在 PATH 中
export PATH="/e/iverilog/bin:$PATH"

# 验证安装
iverilog -V | head -2
# 应输出: Icarus Verilog version 12.0

# 进入项目目录
cd /e/CPU/cpu

# 确认文件都在
ls rtl/         # 9 个 .sv/.svh 文件
ls testbench/   # 8 个 tb 文件
ls programs/    # .asm + .hex + data.hex
ls tools/       # assembler.py
```

### 第一步：汇编测试程序

```bash
python3 tools/assembler.py programs/test1_alu.asm -o programs/test1_alu.hex
python3 tools/assembler.py programs/test2_mem.asm -o programs/test2_mem.hex
python3 tools/assembler.py programs/test3_branch.asm -o programs/test3_branch.hex
python3 tools/assembler.py programs/test4_integration.asm -o programs/test4_integration.hex
```

每个命令应该输出类似：`programs/test1_alu.asm -> programs/test1_alu.hex (10 instructions)`

### 第二步：跑单元测试（可选，验证各模块独立正确）

```bash
# PC 模块
iverilog -g2012 -o pc_sim rtl/pc.sv testbench/pc_tb.sv && vvp pc_sim
# 期望: pc: PASSED

# 指令存储
cp testbench/test_imem.hex program.hex
iverilog -g2012 -o imem_sim rtl/insn_mem.sv testbench/insn_mem_tb.sv && vvp imem_sim
# 期望: insn_mem: PASSED

# 寄存器堆
iverilog -g2012 -o rf_sim rtl/regfile.sv testbench/regfile_tb.sv && vvp rf_sim
# 期望: regfile: PASSED

# ALU
iverilog -g2012 -o alu_sim rtl/alu.sv testbench/alu_tb.sv && vvp alu_sim
# 期望: alu: PASSED

# 数据存储
iverilog -g2012 -o dmem_sim rtl/data_mem.sv testbench/data_mem_tb.sv && vvp dmem_sim
# 期望: data_mem: PASSED

# 立即数生成器
iverilog -g2012 -o imm_sim rtl/imm_gen.sv testbench/imm_gen_tb.sv && vvp imm_sim
# 期望: imm_gen: PASSED

# 控制单元
iverilog -g2012 -o ctrl_sim rtl/control.sv testbench/control_tb.sv && vvp ctrl_sim
# 期望: control: PASSED
```

### 第三步：跑整 CPU 自检（4 个测试程序）

```bash
# 测试 1：算术指令
cp programs/test1_alu.hex program.hex
iverilog -g2012 -DDATA_INIT_FILE=\"programs/data.hex\" -o simv rtl/pc.sv rtl/insn_mem.sv rtl/regfile.sv rtl/alu.sv rtl/data_mem.sv rtl/imm_gen.sv rtl/control.sv rtl/cpu_top.sv testbench/cpu_tb.sv
vvp simv

# 测试 2：访存指令
cp programs/test2_mem.hex program.hex
iverilog -g2012 -DDATA_INIT_FILE=\"programs/data.hex\" -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv

# 测试 3：分支指令
cp programs/test3_branch.hex program.hex
iverilog -g2012 -DDATA_INIT_FILE=\"programs/data.hex\" -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv

# 测试 4：综合测试
cp programs/test4_integration.hex program.hex
iverilog -g2012 -DDATA_INIT_FILE=\"programs/data.hex\" -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv
```

每次运行期望看到对应测试的 `PASS` 行。例如 test1：

```
=== test1_alu results ===
  PASS: add: 10+3=13
  PASS: sub: 10-3=7
  PASS: and: 10&3=2
  PASS: or:  10|3=11
```

### 第四步：用 Makefile 一键仿真

```bash
# 汇编所有测试
make asm_all

# 跑测试 1
make sim1

# 跑测试 2
make sim2

# 跑测试 3
make sim3

# 跑测试 4（默认）
make sim

# 清理
make clean
```

---

## 7. 波形调试

仿真后会生成 `dump.vcd`（Value Change Dump），可以用 GTKWave 打开查看波形。

```bash
# 先跑一次仿真生成 VCD
cp programs/test3_branch.hex program.hex
iverilog -g2012 -DDATA_INIT_FILE=\"programs/data.hex\" -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv

# 用 GTKWave 打开波形
gtkwave dump.vcd
# 或者：/e/iverilog/gtkwave/bin/gtkwave.exe dump.vcd
```

**在 GTKWave 中应该看什么？**

| 信号 | 怎么看 |
|------|--------|
| `dut.pc` | 观察 PC 是否按预期变化（顺序 +4，分支时跳转到目标） |
| `dut.instr` | 当前指令的 32 位机器码 |
| `dut.alu_result` | ALU 计算结果 |
| `dut.reg_write` | 高电平时表示正在写寄存器 |
| `dut.rd_data` | 写入寄存器的数据 |
| `dut.mem_write` | 高电平时表示正在写数据内存 |
| `dut.pc_src` | 高电平时表示分支被触发 |
| `dut.branch_target` | 分支目标地址 |

**调试 test3_branch 的示例**：

1. 打开 GTKWave，把 `dut.pc` 和 `dut.pc_src` 加入波形
2. 观察 `pc_src` 变成 1 的时刻——这是分支被触发了
3. 此时 `pc` 应该跳转到 `branch_target` 而不是 `pc+4`
4. 如果 `pc_src` 没变成 1，说明 branch 条件没满足——回去看 `dut.zero`/`dut.lt`/`dut.ltu`

---

## 8. 自己写新测试程序

要测试一段新的汇编程序：

1. 创建 `programs/my_test.asm`：
```asm
# 我的测试
lw x1, 0(x0)      # x1 = 10
lw x2, 4(x0)      # x2 = 3
add x3, x1, x2    # x3 = 13
sw x3, 8(x0)      # 存结果
```

2. 汇编：
```bash
python3 tools/assembler.py programs/my_test.asm -o programs/my_test.hex
```

3. 跑仿真：
```bash
cp programs/my_test.hex program.hex
iverilog -g2012 -DDATA_INIT_FILE=\"programs/data.hex\" -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv
```

4. 看波形：
```bash
gtkwave dump.vcd
```

---

## 9. 关键命令速查

```bash
# 环境
export PATH="/e/iverilog/bin:$PATH"
cd /e/CPU/cpu

# 汇编
python3 tools/assembler.py programs/test1_alu.asm -o programs/test1_alu.hex

# 单元测试（以 ALU 为例）
iverilog -g2012 -o sim rtl/alu.sv testbench/alu_tb.sv && vvp sim

# 整 CPU 仿真（以 test1 为例）
cp programs/test1_alu.hex program.hex
iverilog -g2012 -DDATA_INIT_FILE=\"programs/data.hex\" -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv

# 波形
gtkwave dump.vcd

# Makefile 方式
make asm_all    # 汇编全部测试
make sim1       # 跑测试 1
make sim        # 跑测试 4（默认）
make wave       # 跑仿真 + 开 GTKWave
make clean      # 清理
```

---

## 10. 学习路线建议

如果你想从零开始深入理解 CPU 设计：

1. **先看懂 `cpu_top.sv` 的连线**（对照第 2 节的图），理解数据怎么流动
2. **看 `control.sv` 的真值表**，理解不同指令怎么产生不同的控制信号
3. **修改 test1_alu.asm**，改操作数，重新汇编仿真，看结果变化
4. **尝试加一条新指令**（比如 `xor`），需要改 control.sv + cpu_top.sv + assembler.py
5. **阅读《计算机组成与设计：RISC-V 版》**第 4 章，对照着理解

**推荐资源**：
- RISC-V 指令集参考卡：`docs/riscv-card.pdf`
- 书籍：Patterson & Hennessy,《Computer Organization and Design: RISC-V Edition》
- RISC-V 官方规范：https://github.com/riscv/riscv-isa-manual/releases
- Icarus Verilog：https://steveicarus.github.io/iverilog/
