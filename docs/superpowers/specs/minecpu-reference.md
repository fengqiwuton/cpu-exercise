# MineCPU 参考手册

> RISC-V RV32I 单周期处理器，Harvard 架构，SystemVerilog 实现
> 版本: 2026-06-25

## 1. 项目概览

### 1.1 特性

- **指令集**: RV32I 基础整数指令集，37 条指令全部实现
- **架构**: Harvard（指令/数据存储器分离），单周期
- **语言**: SystemVerilog (`.sv`)
- **仿真**: Icarus Verilog + GTKWave
- **上板**: Vivado + EGO1 FPGA（待验证）
- **外设**: UART TX/RX、VGA 帧缓存、PS/2 键盘接口
- **Bootloader**: UART 运行时程序加载，换程序不需重综合
- **C 工具链**: RISC-V GCC 15.2 + 链接脚本 + 启动文件

### 1.2 性能

- 单周期设计，1 IPC（每条指令 1 个周期）
- 仿真: 100MHz 时钟
- 上板: 50MHz（EGO1 板载时钟）

### 1.3 设计文档

| 文档 | 内容 |
|------|------|
| `cpu-walkthrough.md` | 第一阶段：基础 CPU（11 条指令），全流程走读 |
| `cpu-walkthrough-2.md` | 第二阶段：RV32I 全指令 + UART + C 工具链 + Snake |
| `bootloader-design.md` | 引导加载器架构设计 |
| `minecpu-reference.md` | 本文档：完整参考手册 |

---

## 2. 存储架构

```
地址空间              物理存储器
───────────────────── ─────────────
0x0000_0000          ┌─────────────┐
    ↓                │  Boot ROM   │  4KB，只读，固定烧录
0x0000_0FFF          │  (boot_rom) │  上电自动执行
                     ├─────────────┤
0x0000_1000          │ Program     │  4KB，双端口
    ↓                │  BRAM       │  端口A: CPU取指(只读)
0x0000_1FFF          │ (insn_mem)  │  端口B: 引导程序写(通过MMIO)
                     └─────────────┘

0x0000_0000          ┌─────────────┐
    ↓                │  Data RAM   │  8KB，可读写
0x0000_1FFF          │ (data_mem)  │  存全局变量、栈、堆
                     └─────────────┘

0x4000_0000          ┌─────────────┐
    ↓                │  MMIO 外设   │  见 §2.1
0x4000_2FFF          │             │
                     └─────────────┘
```

### 2.1 MMIO 地址分配

| 地址范围 | 外设 | 访问 |
|----------|------|------|
| `0x4000_0000` | UART TX_DATA | W |
| `0x4000_0004` | UART RX_DATA | R |
| `0x4000_0008` | UART STATUS | R |
| `0x4000_000C` | UART BAUD_DIV | R/W |
| `0x4000_0030` | PS/2 KEY_DATA | R |
| `0x4000_0034` | PS/2 STATUS | R |
| `0x4000_1000` | BRAM 写入 | W（引导程序用） |
| `0x4000_2000+` | VGA 帧缓存 (4800B) | W（每字节一个像素） |

---

## 3. 模块清单

| 文件 | 模块 | 说明 |
|------|------|------|
| `pc.sv` | PC | 32-bit 程序计数器，支持 ±4 和分支跳转 |
| `boot_rom.sv` | Boot ROM | 引导程序（汇编→hex→综合时固化） |
| `insn_mem.sv` | Insn Mem | 双端口 BRAM，1024×32bit |
| `regfile.sv` | RegFile | 32×32bit 寄存器，x0 硬连线为 0 |
| `alu.sv` | ALU | ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU |
| `data_mem.sv` | Data Mem | 2048×32bit，支持 byte/half/word 写 |
| `imm_gen.sv` | Imm Gen | 生成 I/S/B/U/J 五种立即数 |
| `control.sv` | Control | 37条指令译码，输出 8 类控制信号 |
| `baud_gen.sv` | Baud Gen | 可编程波特率分频器 |
| `uart.sv` | UART | 16550 风格，8N1，TX+RX 状态机 |
| `vga_fb.sv` | VGA FB | 80×60 帧缓存，640×480@60Hz 输出 |
| `ps2_kbd.sv` | PS/2 Kbd | PS/2 协议接收，存扫描码到 MMIO |
| `cpu_top.sv` | Top | 顶层集成：取指路由 + MMIO 总线 |

---

## 4. 指令集

### 4.1 R-type (opcode=0110011)

| 指令 | funct3 | funct7 | 操作 | ALU |
|------|--------|--------|------|-----|
| add | 000 | 0000000 | rd=rs1+rs2 | ADD |
| sub | 000 | 0100000 | rd=rs1-rs2 | SUB |
| sll | 001 | 0000000 | rd=rs1<<rs2[4:0] | SLL |
| slt | 010 | 0000000 | rd=rs1<rs2(signed) | SLT |
| sltu | 011 | 0000000 | rd=rs1<rs2(unsigned) | SLTU |
| xor | 100 | 0000000 | rd=rs1^rs2 | XOR |
| srl | 101 | 0000000 | rd=rs1>>rs2[4:0] | SRL |
| sra | 101 | 0100000 | rd=rs1>>>rs2[4:0] | SRA |
| or | 110 | 0000000 | rd=rs1|rs2 | OR |
| and | 111 | 0000000 | rd=rs1&rs2 | AND |

### 4.2 I-type ALU (opcode=0010011)

| 指令 | funct3 | 操作 |
|------|--------|------|
| addi | 000 | rd=rs1+imm(sext) |
| slli | 001 | rd=rs1<<shamt |
| slti | 010 | rd=rs1<imm(signed) |
| sltiu | 011 | rd=rs1<imm(unsigned) |
| xori | 100 | rd=rs1^imm |
| srli | 101 | rd=rs1>>shamt |
| srai | 101 | rd=rs1>>>shamt (funct7[5]=1) |
| ori | 110 | rd=rs1|imm |
| andi | 111 | rd=rs1&imm |

### 4.3 Load/Store/Branch/Jump

| 指令 | opcode | funct3 | 操作 |
|------|--------|--------|------|
| lb | 0000011 | 000 | rd=sext(mem[rs1+imm][7:0]) |
| lh | 0000011 | 001 | rd=sext(mem[rs1+imm][15:0]) |
| lw | 0000011 | 010 | rd=mem[rs1+imm] |
| lbu | 0000011 | 100 | rd=zext(mem[rs1+imm][7:0]) |
| lhu | 0000011 | 101 | rd=zext(mem[rs1+imm][15:0]) |
| sb | 0100011 | 000 | mem[rs1+imm][7:0]=rs2[7:0] |
| sh | 0100011 | 001 | mem[rs1+imm][15:0]=rs2[15:0] |
| sw | 0100011 | 010 | mem[rs1+imm]=rs2 |
| beq | 1100011 | 000 | branch if rs1==rs2 |
| bne | 1100011 | 001 | branch if rs1!=rs2 |
| blt | 1100011 | 100 | branch if rs1<rs2 |
| bge | 1100011 | 101 | branch if rs1>=rs2 |
| bltu | 1100011 | 110 | branch if rs1<rs2(u) |
| bgeu | 1100011 | 111 | branch if rs1>=rs2(u) |
| jal | 1101111 | — | rd=PC+4, PC+=offset |
| jalr | 1100111 | — | rd=PC+4, PC=rs1+imm |
| lui | 0110111 | — | rd=imm<<12 |
| auipc | 0010111 | — | rd=PC+(imm<<12) |

---

## 5. 验证结果

| 测试 | 说明 | 结果 |
|------|------|:--:|
| test1_alu | add/sub/and/or | 4/4 ✓ |
| test2_mem | lw/sw 访存往返 | 4/4 ✓ |
| test3_branch | 5种分支 × 取/不取 | 7/7 ✓ |
| test4_integration | 数组求和 + 分支 | 2/2 ✓ |
| test5_rv32i | 全部 26 条新指令 | 25/26 ✓ |
| test_rx | UART RX 回显 | ✓ |
| hello.c | C 程序：Hello World | ✓ |
| snake.c | Snake 游戏（UART版）| ✓ |

---

## 6. 工作流速查

### 6.1 汇编程序

```bash
cd /e/CPU/cpu
python3 tools/assembler.py programs/test.asm -o programs/test.hex
cp programs/test.hex program.hex
iverilog -g2012 -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv
```

### 6.2 C 程序

```bash
export PATH="/e/riscv-gcc/.../bin:$PATH"
export PATH="/e/iverilog/bin:$PATH"

riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c myprog.c -o build/myprog.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding \
  -T tools/link.ld build/crt0.o build/myprog.o -o build/myprog.elf -lgcc
python3 tools/elf2hex.py build/myprog.elf --code build/myprog.hex \
  --data build/myprog_data.hex --data-base 0 --data-size 0x2000
cp build/myprog.hex program.hex
cp build/myprog_data.hex programs/data.hex
iverilog -g2012 -DSIMULATION -o simv rtl/*.sv testbench/cpu_tb.sv
vvp simv
```

### 6.3 Bootloader 模式

```bash
python3 tools/assembler.py tools/bootloader.asm -o build/bootloader.hex
python3 tools/hex2bin.py build/myprog.hex prog.bin
iverilog -g2012 -DBOOT_HEX='"build/bootloader.hex"' -o simv rtl/*.sv testbench/boot_tb.sv
vvp simv
```

---

## 7. 修复过的 Bug

| Bug | 根因 | 修复 |
|-----|------|------|
| `lb` 始终读 byte 0 | load ext 没用 addr 偏移选字节 | `cpu_top`: 加 `load_off` mux |
| `sb` 非 byte 0 写失败 | `rs2_data[15:8]` 不包含 byte 值 | `cpu_top`: 加 `store_data` lane 复制 |
| `srai` 结果为逻辑移位 | Icarus `$signed()` 上下文丢失 | `alu`: 手动 sign-fill mask |
| 汇编器不编码 shift 的 funct7 | `enc_ialu` 忽略 funct7 | `assembler`: shift 指令特判 |
| UART RX 收不到 | 采样点与 bit 边界不对齐 | `uart`: 自同步计数器替代 baud_tick |
| UART RX 收到乱码 | 注入器 bit 边界计算负数除 | `snake_tb`: 固定 bit-phase 状态机 |
| 数据存储器 byte 1 写失败 | `for`+part-select Icarus 不支持 | `data_mem`: 显式 4 条 `if` |

---

## 8. 路线图

### 8.1 已完成

| 阶段 | 内容 | 状态 |
|------|------|:--:|
| 1 | 基础 CPU (11 条指令) | ✅ |
| 2 | RV32I 全指令 (37 条) | ✅ |
| 3 | UART + C 工具链 + assembler (支持 la/li/mv/call) | ✅ |
| 4 | Bootloader（UART 运行时程序加载） | ✅ |
| 5 | hex2bin + hex2coe（可调深度） + uart_tool（仿真/硬件双模式） | ✅ |
| 6 | VGA 帧缓存 + PS/2 硬件模块 | ⚠️ 已写，编译通过，待适配 |

### 8.2 下一步

| 阶段 | 内容 | 预计工作量 |
|------|------|:--:|
| A | **异常/CSR 支持** — CSR 寄存器 (mtvec/mepc/mcause/mstatus)、ecall 指令、非法指令 trap、mret 返回 | ✅ 已完成 |
| B | **Pipeline** — 5 级流水 + forwarding + load-use stall + 写旁路 | ✅ 已完成 |
| C | **VGA Snake 适配** — 把 snake.c 改到 VGA 帧缓存 + PS/2 键盘输入 | 小 |

### 8.3 未来应用层任务

| 项目 | 内容 | 关键技术点 |
|------|------|-----------|
| 🎨 **图形处理** | 在 VGA 上画线( Bresenham )、画圆、显示文字 | 像素级显存操作，字符 ROM |
| 🔊 **声音输出** | PWM / ΣΔ DAC 输出波形，播放简单音乐 | 定时器中断、音频缓冲区 |
| 🎮 **游戏手柄** | 接 PS2/NES 手柄，CPU 读按键状态 | 中断处理、SPI/并口协议 |
| 📺 **UART 终端** | PC 端 Python 脚本通过 UART 与 CPU 交互 | uart_tool.py 已就绪 |
| 💾 **SD 卡** | SPI 模式读 SD 卡，加载程序/资源 | SPI 协议、FAT32 |
| 🧠 **简单 OS** | 多任务调度、系统调用、内存管理 | 利用 ecall + CSR + 定时器中断 |

### 8.4 UART 通信工具说明

`tools/uart_tool.py`：
```bash
# 仿真模式 — 发程序
python3 tools/uart_tool.py sim send prog.bin

# 仿真模式 — 收数据
python3 tools/uart_tool.py sim recv

# 硬件模式 — 发程序到 FPGA
python3 tools/uart_tool.py hw send prog.bin -p COM3 -b 115200

# 硬件模式 — 收 FPGA 输出
python3 tools/uart_tool.py hw recv -p COM3 -b 115200

# 自动检测波特率
python3 tools/uart_tool.py hw detect -p COM3
```

### 8.5 COE 生成工具说明

`tools/hex2coe.py`：
```bash
# 自动深度（向上取 2 的幂）
python3 tools/hex2coe.py program.hex -o program.coe

# 指定深度
python3 tools/hex2coe.py program.hex -o program.coe -d 4096
```
