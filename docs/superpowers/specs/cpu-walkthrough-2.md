# MineCPU 第二阶段 — RV32I + UART + C 工具链 + Snake 游戏

> 验证全部 37 条 RV32I 指令、UART 外设、C 编译运行、贪吃蛇游戏。

---

## 前置准备

```bash
# Icarus Verilog
export PATH="/e/iverilog/bin:$PATH"
iverilog -V | head -1
# → Icarus Verilog version 12.0

# RISC-V GCC
export PATH="/e/riscv-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$PATH"
riscv-none-elf-gcc --version | head -1
# → riscv-none-elf-gcc 15.2.0

cd /e/CPU/cpu
```

---

## 一、RV32I 全部 37 条指令验证

### 测试程序一览

| 测试 | 内容 | 检验项 |
|------|------|--------|
| test1_alu | add, sub, and, or | 4 |
| test2_mem | lw, sw 访存往返 | 4 |
| test3_branch | beq/blt/bge/bltu/bgeu 取/不取 | 7 |
| test4_integration | 数组求和 + beq 验证 | 2 |
| test5_rv32i | addi, slti, xor, slli, srai, lui, bne, jal, lb, lh, sb, sh 等全部新增指令 | 26 |

### 跑所有测试

```bash
export PATH="/e/iverilog/bin:$PATH"

# 需要先准备正确的 data.hex（见下）
for t in test1_alu test2_mem test3_branch test4_integration test5_rv32i; do
    echo "===== $t ====="
    cp programs/$t.hex program.hex
    iverilog -g2012 -o simv rtl/*.sv testbench/cpu_tb.sv 2>/dev/null
    vvp simv 2>&1 | grep -E "^===|PASS|ERROR"
    echo ""
done
```

**期望结果：全部 PASS，0 个 ERROR**（43/43 项检查通过）

---

## 二、UART 外设

### 寄存器地址

| 地址 | 名称 | R/W | 说明 |
|------|------|-----|------|
| `0x4000_0000` | TX_DATA | W | 写入字节启动发送 |
| `0x4000_0004` | RX_DATA | R | 读取接收字节 |
| `0x4000_0008` | STATUS | R | bit0=TX忙, bit1=RX就绪 |
| `0x4000_000C` | BAUD_DIV | R/W | 波特率分频值 |

### UART TX 汇编测试

```bash
python3 tools/assembler.py programs/test7_uart_debug.asm -o /tmp/t7.hex
cp /tmp/t7.hex program.hex
iverilog -g2012 -DSIMULATION -o simv rtl/*.sv testbench/cpu_tb.sv 2>/dev/null
vvp simv 2>&1 | grep "UART" | head -5
```

期望输出：`W X Y Z`（验证 `sb`/`lb` 在不同 byte 偏移下正确 + UART TX 正常）

---

## 三、C 工具链

### 文件说明

| 文件 | 作用 |
|------|------|
| `tools/link.ld` | 链接脚本：代码 `0x0000_0000`，数据 `0x0000_1000`，栈 `0x2000` |
| `tools/crt0.s` | 启动代码：设栈指针 → 清 BSS → `call main` → 死循环 |
| `tools/elf2hex.py` | ELF → code.hex + data.hex（哈佛架构：代码和数据分开） |
| `programs/hello.c` | 测试 C 程序 |
| `programs/snake.c` | 贪吃蛇游戏 |

### Hello World 编译运行

```bash
export PATH="/e/riscv-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$PATH"
export PATH="/e/iverilog/bin:$PATH"
cd /e/CPU/cpu

# 1. 编译
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c tools/crt0.s -o build/crt0.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c programs/hello.c -o build/hello.o

# 2. 链接
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding \
  -T tools/link.ld build/crt0.o build/hello.o -o build/hello.elf

# 3. ELF → hex
python3 tools/elf2hex.py build/hello.elf \
  --code build/hello_code.hex \
  --data build/hello_data.hex \
  --data-base 0x00000000 --data-size 0x2000

# 4. 运行
cp build/hello_code.hex program.hex
cp build/hello_data.hex programs/data.hex
iverilog -g2012 -DSIMULATION -o simv rtl/*.sv testbench/cpu_tb.sv 2>/dev/null
vvp simv 2>&1 | grep "UART"
```

**期望输出：** `Hello from C on MineCPU!`（25 个字符，每字符一行 UART 日志）

---

## 四、贪吃蛇游戏

### 编译

```bash
# 编译 snake.c（需要 libgcc 提供除法/取模运行时）
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c programs/snake.c -o build/snake.o

# 链接时加 -lgcc
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding \
  -T tools/link.ld build/crt0.o build/snake.o -o build/snake.elf -lgcc

# 转为 hex
python3 tools/elf2hex.py build/snake.elf \
  --code build/snake_code.hex \
  --data build/snake_data.hex \
  --data-base 0x00000000 --data-size 0x2000
```

### 运行

```bash
cp build/snake_code.hex program.hex
cp build/snake_data.hex programs/data.hex
iverilog -g2012 -DSIMULATION -o simv rtl/*.sv testbench/snake_tb.sv 2>/dev/null
vvp simv
```

输出是 ANSI 终端画面（`\e[2J` 清屏、`\e[H` 光标归位），包含 20×10 的游戏网格。

### 如何自己操控

编辑 `keys.txt`，写入方向键序列（每行一个字符）：
```
d
d
d
s
s
a
q
```

`snake_tb.sv` 会读这个文件，把按键通过 `uart_rx_pin` 串行注入 CPU。格式：wasd 移动，q 退出。

---

## 五、调试中修过的 Bug 记录

| Bug | 表现 | 根因 | 修复位置 |
|-----|------|------|----------|
| Load byte 始终读 byte 0 | `lb 1(x0)` 返回 `'A'` 而不是 `'B'` | load extension 没用 `alu_result[1:0]` 选字节 | `cpu_top.sv` load ext 加 byte offset mux |
| Store byte 写入非 byte 0 失败 | `sb x12,1(x0)` 对 `lw` 读回无影响 | `rs2_data` 的 byte 值只在 `[7:0]`，data_mem 的 `byte_enable[1]` 取 `[15:8]` 却是 0 | `cpu_top.sv` 加 `store_data` 复制 byte 到全部 4 lane |
| `srai` 算术右移结果为逻辑移位 | `0xFFFF_FF00 >>> 2` = `0x3FFF_FFC0` | Icarus 不支持 `$signed() >>>`，`6'd32` 溢出 | `alu.sv` 用手动 sign-bit fill mask |
| `addi imm` 的符号扩展 | `addi x6,0,0x800` 得到 `0xFFFF_F800` | 12-bit #imm bit11=1 符号扩展 | 测试程序用正的 12-bit 立即数（256, -256） |
| `srai/srli` 汇编器不编码 funct7 | srai 被当作 srli 执行 | `enc_ialu` 没把 funct7 放进指令高 7 位 | `assembler.py` shift 指令特判 |

---

## 六、当前状态

| 功能 | 状态 |
|------|:--:|
| RV32I 全部 37 条指令 | ✅ 43/43 测试通过 |
| UART TX | ✅ Hello World, Snake 渲染正常 |
| UART RX | ⚠️ 时序调试中（RX 状态机自同步） |
| C 工具链 | ✅ 编译→链接→hex→仿真全流程 |
| Snake 游戏 | ✅ 画面渲染和蛇移动正常，键盘输入待 RX 修好 |

---

## 七、项目文件清单

```
E:\CPU\cpu\
├── rtl/
│   ├── pc.sv            # 程序计数器
│   ├── insn_mem.sv      # 指令存储器
│   ├── regfile.sv       # 寄存器堆 (32×32)
│   ├── alu.sv           # ALU (10 种运算)
│   ├── data_mem.sv      # 数据存储器 (byte_enable)
│   ├── imm_gen.sv       # 立即数生成 (I/S/B/U/J)
│   ├── control.sv       # 控制单元 (37 条指令)
│   ├── baud_gen.sv      # 波特率分频器
│   ├── uart.sv          # UART TX+RX
│   └── cpu_top.sv       # 顶层 + MMIO 路由
├── testbench/
│   ├── pc_tb.sv ~ control_tb.sv   # 单元测试
│   ├── cpu_tb.sv                  # 整 CPU 自检
│   └── snake_tb.sv                # 蛇游戏专用（含键盘注入）
├── programs/
│   ├── test1_alu.asm ~ test5_rv32i.asm  # 汇编测试
│   ├── test7_uart_debug.asm             # UART 调试
│   ├── hello.c                          # C Hello World
│   ├── snake.c                          # 贪吃蛇
│   └── data.hex
├── tools/
│   ├── assembler.py      # 汇编器 (37 条指令)
│   ├── link.ld           # C 链接脚本
│   ├── crt0.s            # C 启动文件
│   └── elf2hex.py        # ELF → hex 转换
├── build/                # 编译输出
├── keys.txt              # 蛇游戏按键输入（可选）
└── Makefile
```

---

## 八、命令速查

```bash
# 环境
export PATH="/e/iverilog/bin:$PATH"
export PATH="/e/riscv-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$PATH"
cd /e/CPU/cpu

# 汇编器
python3 tools/assembler.py programs/test.asm -o programs/test.hex

# 单元测试（以 ALU 为例）
iverilog -g2012 -o sim rtl/alu.sv testbench/alu_tb.sv && vvp sim

# 整 CPU 测试
cp programs/test1_alu.hex program.hex
iverilog -g2012 -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv

# C 编译链接
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c myprog.c -o build/myprog.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding \
  -T tools/link.ld tools/crt0.o build/myprog.o -o build/myprog.elf -lgcc

# ELF → hex
python3 tools/elf2hex.py build/myprog.elf \
  --code build/my_code.hex --data build/my_data.hex \
  --data-base 0x00000000 --data-size 0x2000

# 运行 C 程序
cp build/my_code.hex program.hex
cp build/my_data.hex programs/data.hex
iverilog -g2012 -DSIMULATION -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv

# 波形
gtkwave dump.vcd
```

---

## 九、Bootloader — 运行时程序加载

### 架构

```
Boot ROM (0x0000-0x0FFF)         Program BRAM (0x1000-0x1FFF)
┌─────────────────────┐          ┌─────────────────────┐
│ 引导程序（固定烧录）   │   sw指令  │ 双端口可写            │
│ 1. 等 UART RX 数据    │ ──────→  │ CPU 从这里取指执行     │
│ 2. 写入 BRAM          │   MMIO   │                     │
│ 3. jalr 跳转          │          │                     │
└─────────────────────┘          └─────────────────────┘
```

像真的 CPU 一样：换程序 = PC 发新 hex，不用重综合硬件。

### MMIO 地址映射

| 地址 | 外设 |
|------|------|
| `0x4000_0000` | UART TX/RX/STATUS/BAUD |
| `0x4000_0030` | PS/2 键盘数据 |
| `0x4000_1000` | BRAM 写入（引导程序用） |
| `0x4000_2000` | VGA 帧缓存 (80×60×8bit) |

### 引导程序使用

```bash
# 1. 汇编引导程序（只需做一次）
python3 tools/assembler.py tools/bootloader.asm -o build/bootloader.hex

# 2. C 程序 → hex → bin
riscv-none-elf-gcc ... -o build/myprog.elf -lgcc
python3 tools/elf2hex.py build/myprog.elf --code build/myprog.hex ...
python3 tools/hex2bin.py build/myprog.hex prog.bin

# 3. 仿真（引导程序自动从 UART 加载 prog.bin）
iverilog -g2012 -DBOOT_HEX='"build/bootloader.hex"' -o simv rtl/*.sv testbench/boot_tb.sv
vvp simv
```

---

## 十、VGA 帧缓存 + PS/2 键盘

### VGA 帧缓存 (vga_fb.sv)

- 80×60 像素，每像素 8-bit 颜色 (RRRGGGBB)
- 640×480@60Hz VGA 信号，3×3 像素放大
- CPU 通过 MMIO 写像素：`*(0x40002000 + y*80 + x) = color`

颜色定义：
```c
#define BLACK   0x00
#define WHITE   0xFF
#define RED     0xE0
#define GREEN   0x1C
#define BLUE    0x03
```

### PS/2 键盘 (ps2_kbd.sv)

- 接收 PS/2 扫描码，转存到 MMIO 寄存器
- 轮询：读 `0x40000034`，bit0=1 表示有按键
- 读数据：读 `0x40000030`，返回 8-bit 扫描码

### 蛇游戏 C 代码适配（示意）

```c
volatile unsigned char *fb = (unsigned char*)0x40002000;

void draw_pixel(int x, int y, unsigned char color) {
    fb[y * 80 + x] = color;
}
```

---

## 十一、当前硬件模块清单

| 文件 | 功能 |
|------|------|
| `pc.sv` | 程序计数器 |
| `insn_mem.sv` | 指令 BRAM（双端口，端口B可写） |
| `boot_rom.sv` | 引导 ROM（固定，地址0） |
| `regfile.sv` | 寄存器堆 |
| `alu.sv` | ALU（10种运算） |
| `data_mem.sv` | 数据存储器 |
| `imm_gen.sv` | 立即数生成 |
| `control.sv` | 控制单元（37条指令） |
| `baud_gen.sv` | 波特率分频 |
| `uart.sv` | UART TX+RX |
| `vga_fb.sv` | VGA 帧缓存 + 控制器 |
| `ps2_kbd.sv` | PS/2 键盘接口 |
| `csr.sv` | CSR 寄存器 + 异常捕获 |
| `cpu_top.sv` | 顶层 + MMIO 路由 + 指令来源切换 + 异常逻辑 |
```

---

## 十二、CSR 寄存器与异常处理

### CSR 寄存器

| 地址 | 名称 | 说明 |
|------|------|------|
| `0x300` | mstatus | 机器状态 |
| `0x305` | mtvec | 异常向量基址 |
| `0x341` | mepc | 异常 PC |
| `0x342` | mcause | 异常原因 |

### 异常原因码

| 值 | 含义 |
|----|------|
| 2 | 非法指令 |
| 11 | ecall from M-mode |

### 流程

```
ecall/非法指令 → 硬件: PC→mepc, mcause←原因 → 跳转mtvec
    → 异常处理函数执行 → mret → PC=mepc → 返回
```

### CSR/异常测试

```bash
python3 tools/assembler.py programs/test_csr.asm -o /tmp/test_csr.hex
cp /tmp/test_csr.hex program.hex
iverilog -g2012 -DSIMULATION -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv 2>&1 | grep "DEBUG"
# mem[5]=0000000b → mcause=11(ecall) ✓
# mem[4]=00000000 → ecall 前 marker ✓
# mem[6]=00001800 → mstatus 旧值 ✓
```

### 新增工具

| 工具 | 作用 |
|------|------|
| `hex2coe.py` | hex → Xilinx COE (可调深度) |
| `uart_tool.py` | UART 通信工具 (sim/hw 双模式) |
| `hex2bin.py` | hex → 引导加载二进制 |
| 汇编器扩展 | la/li/mv/call + csrrw/csrrs/ecall/mret + .equ |
