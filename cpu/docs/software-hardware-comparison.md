# 软硬件对比：本项目 vs 真实计算机

## 全景图

```
真实计算机                              本项目
══════════                             ════════

┌─────────────────────┐               ┌─────────────────────┐
│  C 程序             │               │  C 程序 (snake_vga.c)│
├─────────────────────┤               ├─────────────────────┤
│  gcc/clang 编译器   │  ←相同→       │  riscv-gcc 交叉编译  │
│  glibc 标准库       │               │  crt0.s 启动代码     │
│  ld 链接器          │               │  link.ld 链接脚本    │
├─────────────────────┤               ├─────────────────────┤
│  ELF 可执行文件     │               │  elf2hex.py 转换     │
│  OS loader 加载     │               │  $readmemh 直接加载  │
├─────────────────────┤               ╞═════════════════════╡
│  Linux/Windows OS   │  ←完全不同→   │  无操作系统          │
│  进程管理/驱动/中断 │               │  裸机 (bare-metal)   │
├─────────────────────┤               ╞═════════════════════╡
│  x86/ARM 物理 CPU   │  ←完全不同→   │  RISC-V 软核 (Verilog)│
│  超标量/乱序/缓存   │               │  单周期/哈佛/无缓存  │
├─────────────────────┤               ├─────────────────────┤
│  物理外设           │               │  Verilog 外设模块    │
│  GPU/USB/PCIe       │               │  UART/VGA/PS2        │
├─────────────────────┤               ├─────────────────────┤
│  硅片/晶体管        │  ←完全不同→   │  Verilator C++ 模拟  │
│  3-7nm 制程         │               │  x86 宿主机进程       │
└─────────────────────┘               └─────────────────────┘
```

## 一、软件方面

### 1.1 我们编译的软件工具链

| 工具 | 来源 | 作用 | 是否自己写 |
|------|------|------|-----------|
| **riscv-none-elf-gcc** | 预编译二进制（SiFive/riscv-collab） | C→RISC-V 机器码编译器 | ✗ 外部 |
| **crt0.s** | 自己写 | CPU 启动代码（设栈、清 BSS、调 main） | ✓ |
| **link.ld** | 自己写 | 链接脚本：代码→0x0000，数据→0x1000 | ✓ |
| **elf2hex.py** | 自己写 (99行) | 解析 ELF 文件→分离 code.hex / data.hex | ✓ |
| **assembler.py** | 自己写 | 完整 RV32I 汇编器（37条指令+伪指令） | ✓ |
| **hex2bin.py** | 自己写 | hex→二进制，用于 bootloader | ✓ |
| **hex2coe.py** | 自己写 | hex→Xilinx COE，用于 Vivado FPGA | ✓ |
| **uart_tool.py** | 自己写 | PC 端 UART 通信工具 | ✓ |

### 1.2 编译流程

```
snake_vga.c                    ← 手写的 C 游戏代码
     │
     ▼
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os -c
     │  交叉编译：在 x86 PC 上生成 RISC-V 32-bit 机器码
     │  -nostdlib: 不用标准 C 库（没有 printf/malloc）
     │  -ffreestanding: 裸机模式（没有 OS）
     ▼
snake_vga.o                    ← RISC-V ELF 目标文件
     │
     ▼
riscv-none-elf-gcc -T link.ld crt0.o snake_vga.o -o snake_vga.elf -lgcc
     │  链接：按 link.ld 脚本把代码放 0x0000，数据放 0x1000
     │  crt0.o: 启动代码（设栈指针、清 BSS、调 main）
     ▼
snake_vga.elf                  ← 完整 RISC-V ELF 可执行文件
     │
     ▼
python3 elf2hex.py snake_vga.elf --code code.hex --data data.hex
     │  手动解析 ELF 格式，提取 .text 段 → code.hex
     │  提取 .data/.rodata/.bss 段 → data.hex
     ▼
program.hex + data.hex         ← 纯文本，每行 8 位十六进制（32-bit 指令/数据字）
     │
     ▼
Verilog $readmemh("program.hex", mem)   ← 硬件仿真时直接加载到 BRAM
```

### 1.3 自研工具详解

**crt0.s** —— CPU 启动后执行的第一段代码：
```asm
_start:
    la sp, __stack_top       # 设栈指针到 0x00002000
    # 清零 BSS 段（全局未初始化变量）
    la t0, __bss_start
    la t1, __bss_end
1:  bge t0, t1, 2f
    sw zero, 0(t0)           # 写 0
    addi t0, t0, 4
    j 1b
2:  call main                # 调用 C 的 main()
3:  j 3b                     # main 返回后死循环
```

**elf2hex.py** —— 没有操作系统 loader，必须手动提取：
- 解析 ELF 文件头，找到 PT_LOAD 段
- 按虚拟地址拆分为 code（0x0000-0x0FFF）和 data（0x1000-0x1FFF）
- 输出为 Verilog `$readmemh` 可读的 hex 格式

**assembler.py** —— 完整 RV32I 汇编器：
- 支持全部 37 条 RV32I 指令 + CSR 指令 + 伪指令（la, li, mv, call, ret, j）
- 用于编写 bootloader.asm 等底层代码

### 1.4 是不是"虚拟 CPU"上开发的？

**不是**。代码运行在真实的 RISC-V 机器码上，每次 `sb`、`lw`、`add` 都是 CPU 硬件模块实际执行的。开发流程是：

```
C 代码 → 交叉编译为真实 RISC-V 指令 → CPU 逐条取指/译码/执行
```

这里"虚拟"的只是 CPU 的实现方式——它不是硅片，而是用 Verilog 描述然后用 Verilator 模拟的。但执行的指令是真实的 RISC-V 机器码。

## 二、硬件方面

### 2.1 硬件描述语言 (Verilog/SystemVerilog)

所有硬件模块都是用 Verilog 写的 `.sv` 文件。Verilog 是**硬件描述语言**，它描述的是数字电路的连接关系，不是软件程序。

```
.___________.    .___________.    .___________.    .___________.
|           |    |           |    |           |    |           |
|  pc.sv    |    | alu.sv    |    | regfile.sv|    | uart.sv   |
| 程序计数器|    | 算术逻辑  |    | 寄存器堆  |    | 串口通信  |
|___________|    |___________|    |___________|    |___________|
     │                │                │                │
     └────────────────┼────────────────┼────────────────┘
                      │                │
                 cpu_top.sv     ← 顶层模块：把所有子模块连在一起
                      │
                 Verilator      ← 编译 Verilog→C++，用 x86 CPU 执行
                      │
            sim_vga.cpp         ← C++ 驱动：提供时钟、注入按键、读帧缓冲
                      │
                 SDL2            ← 把帧缓冲数据渲染到屏幕窗口
```

### 2.2 16 个硬件模块清单

| 模块 | 文件 | 功能 | 对应真实硬件 |
|------|------|------|-------------|
| **PC** | `pc.sv` | 程序计数器，存放下一条指令地址 | CPU 内部 PC 寄存器 |
| **指令存储器** | `insn_mem.sv` | 存放程序机器码 (BRAM, 4KB) | 主板上的 ROM/Flash |
| **寄存器堆** | `regfile.sv` | 32 个 32-bit 通用寄存器 x0-x31 | CPU 内部寄存器 |
| **ALU** | `alu.sv` | 算术逻辑运算（加减、移位、比较） | CPU 内部 ALU |
| **立即数生成** | `imm_gen.sv` | 从指令中提取 12/20-bit 立即数 | CPU 内部译码逻辑 |
| **控制单元** | `control.sv` | 译码，生成所有控制信号 | CPU 内部微码/控制逻辑 |
| **数据存储器** | `data_mem.sv` | 存放全局变量、栈 (BRAM, 4KB) | 主板上的 RAM |
| **UART** | `uart.sv` | 串口收发（与 PC 通信） | 主板上 16550 UART 芯片 |
| **波特率生成** | `baud_gen.sv` | UART 时钟分频 | UART 芯片内部 |
| **VGA 帧缓冲** | `vga_fb.sv` | 80×60 像素帧缓冲 + VGA 时序 | 显卡上的显存 + RAMDAC |
| **PS/2 键盘** | `ps2_kbd.sv` | 键盘接口 | 主板键盘控制器 |
| **CSR** | `csr.sv` | 控制状态寄存器（异常处理） | CPU 内部 CSR |
| **Boot ROM** | `boot_rom.sv` | 启动固件（可选） | 主板 BIOS/UEFI |
| **cpu_top** | `cpu_top.sv` | 顶层连线 + MMIO 地址路由 | 主板芯片组 (北桥/南桥) |
| **流水线版** | `pipeline/` | 5 级流水线版本（实验性） | — |

### 2.3 硬件如何"运行"：Verilator 模拟原理

Verilator 不是传统的模拟器——它是**编译器**：

```
输入: Verilog RTL (vga_fb.sv, cpu_top.sv, ...)
      ↓
Verilator 编译: Verilog → 优化过的 C++ 类
      ↓
输出: Vcpu_top.h / Vcpu_top.cpp (行为等价的 C++ 代码)
      ↓
g++ 编译: C++ → x86_64 机器码
      ↓
输出: Vcpu_top__ALL.o → Vcpu_top_vga (x86 可执行文件)
```

C++ 驱动 `sim_vga.cpp` 控制模拟：

```cpp
// 硬件时钟周期循环
top->clk = 1;              // 时钟上升沿
top->eval();               // 求值所有组合逻辑：ALU、译码、地址计算...
                           // 等效于电信号在电路中传播
top->clk = 0;              // 时钟下降沿
top->eval();               // 边沿触发：寄存器采样、存储器写入
```

每一对 `clk=1; eval(); clk=0; eval()` 就是 CPU 的一个时钟周期。一条 RISC-V 指令在单周期设计中恰好占一个周期。

### 2.4 VGA 帧缓冲：从 Verilog 数组到屏幕像素

```
硬件层 (Verilog):
  reg [7:0] fb [0:4799];     // 80×60 字节，8-bit 彩色
  CPU 写: sb to 0x40002000 + offset  →  fb[offset] <= data

模拟层 (C++):
  top->vga_dbg_addr = y*80 + x;  // 设置读地址
  top->eval();                   // 组合逻辑求值
  uint8_t pixel = top->vga_dbg_data;  // 读出像素颜色
  // 8-bit RRRGGGBB → 24-bit RGB888

显示层 (SDL2):
  40×30 纹理 → 缩放到 640×480 窗口
```

## 三、软硬件如何协同

### 3.1 完整数据流（以画一个白像素为例）

```
软件层:
  C 代码: FB[y*80 + x] = 0xFF;    // 程序员写的
     ↓ riscv-gcc 编译
  RISC-V 指令: sb t0, offset(t1)  // t0=0xFF, t1=FB基地址
     ↓ elf2hex.py 提取
  hex 文件: 0x00530023             // 32-bit 机器码

硬件层:
     ↓ $readmemh 加载
  insn_mem: mem[addr] = 0x00530023
     ↓ posedge clk
  control: 译码 → mem_write=1, store_type=01
  regfile: 读 t0→store_data, 读 t1→rs1
  ALU: rs1 + offset → alu_result = 0x40002000 + y*80 + x
  MMIO: alu_result[31:28]=0x4, [15:12]=0x2 → vga_sel=1
     ↓
  vga_fb: fb[addr] <= 0xFF        // 像素写入帧缓冲

模拟层:
     ↓ SDL2 渲染帧
  sim_vga.cpp: 读 fb[y*80+x] → 转换为 RGB → SDL 纹理 → 窗口显示
```

### 3.2 开发流程对照

| 阶段 | 真实硬件开发 | 本项目 |
|------|-------------|--------|
| 写代码 | IDE + 交叉编译 | 文本编辑器 + riscv-gcc |
| 加载程序 | JTAG/调试器烧写 Flash | `$readmemh` 直接加载到 BRAM |
| 运行 | 上电，CPU 从 Flash 取指 | Verilator 编译运行 |
| 调试 | 逻辑分析仪 / JTAG 单步 | Python 读 BMP 逐像素分析 |
| 外设交互 | 物理串口线 + 终端 | C++ `printf` UART 输出 |
| 显示输出 | VGA 显示器 | SDL2 窗口 |

## 四、总结

```
软件栈:  C 程序 ──→ gcc交叉编译 ──→ ELF ──→ elf2hex提取 ──→ hex文件
         (自己写)    (外部工具)           (自己写的 Python)
         
硬件栈:  hex文件 ──→ insn_mem 加载 ──→ RISC-V CPU 取值执行 ──→ MMIO外设
                    ($readmemh)    (16个 Verilog 模块)     (UART,VGA,PS2)
                    
模拟栈:  Verilog RTL ──→ Verilator 编译为 C++ ──→ g++ 编译为 x86 ──→ 本机运行
         (自己写的)     (外部工具)            (标准编译器)      (宿主机CPU)
```

核心区别：真实计算机的硬件是固化的硅片，本项目的硬件是 Verilog 描述 + Verilator 转译为 x86 指令在宿主机上模拟执行。但软件层面——从 C 代码到 RISC-V 机器码的编译、链接、加载过程——与真实嵌入式开发完全一致。
