# MineCPU 引导加载器设计

> 实现运行时程序加载——像真的 CPU 一样，换程序不需要重综合硬件。

## 1. 目标

```
换游戏 → PC 端发 hex → UART → 引导程序接收 → 写入指令 BRAM → CPU 跳转执行
```

引导程序（Bootloader）固定烧在 Boot ROM 里，上电自动运行，之后不再改动。

## 2. 总体架构

```
                    FPGA 板内
                    ═════════
                     ┌──────────────┐
 PC 发 prog.bin ────→│  Boot ROM    │ 地址 0x0000-0x0FFF (4KB)
 (UART 串口)         │  固定不变     │ 上电即从这里启动
                     └──────┬───────┘
                            │ 引导程序做:
                            │ 1. 等 UART 数据
                            │ 2. 逐字节收
                            │ 3. 写入 BRAM
                            │ 4. jalr 跳转
                     ┌──────▼───────┐
                     │ Program BRAM │ 地址 0x1000-0x1FFF (4KB)
                     │ 双端口可写    │ 每次加载新程序时被覆盖
                     └──────┬───────┘
                            │
                     ┌──────▼───────┐
                     │     CPU      │ 取指: boot_sel ? ROM : BRAM
                     └──────────────┘
```

## 3. 关键硬件改动

### 3.1 指令存储器改为双端口

`insn_mem.sv` — 端口 A 只读（CPU 取指），端口 B 只写（引导程序加载）：

```verilog
module insn_mem #(DEPTH=1024) (
    input  [31:0] addr_a,       // CPU 取指地址 → 读
    output [31:0] instr_a,
    input  clk,
    input  [31:0] addr_b,       // 引导程序写地址
    input  [31:0] data_b,       // 引导程序写数据
    input         wr_en_b       // 写使能
);
```

### 3.2 指令来源切换

`cpu_top.sv` 中根据 PC 地址选择取指来源：

```verilog
assign boot_sel = (pc[31:12] == 20'h0);  // PC < 0x1000 → ROM
assign instr = boot_sel ? boot_instr : bram_instr;
```

### 3.3 MMIO 地址分配

| 地址范围 | 外设 | 说明 |
|----------|------|------|
| `0x4000_0xxx` | UART | TX/RX/STATUS/BAUD |
| `0x4000_1xxx` | BRAM 写入 | 引导程序写程序代码 |

引导程序执行 `sw x23, 0x40001000(x0)` 就等价于把一个字写到 Program BRAM 的地址 0x1000。

## 4. 引导程序协议

### 4.1 二进制格式

```
[4 bytes: word_count (u32 LE)] [word_count × 4 bytes: program data]
```

`hex2bin.py` 负责把 `.hex` 文件转成这个格式。

### 4.2 流程

```
1. 上电，CPU 从 Boot ROM (0x0000) 开始执行
2. 引导程序初始化 UART (BAUD=10)
3. 打印 "RDY\n" 提示就绪
4. 读取 4 字节作为程序字数 (word_count)
5. 循环: 读 4 字节 → 拼成 32-bit → sw 到 0x40001000 + offset
6. 所有字数加载完 → jalr 跳转到 0x1000
7. 用户程序开始运行
```

### 4.3 引导程序大小

58 条指令，~232 字节，远小于 Boot ROM 的 4KB 容量。

## 5. 工作流

### 5.1 编译 C 程序

```bash
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c myprog.c -o build/myprog.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding \
  -T tools/link.ld build/crt0.o build/myprog.o -o build/myprog.elf -lgcc
python3 tools/elf2hex.py build/myprog.elf --code build/myprog.hex ...
```

### 5.2 生成可加载二进制

```bash
python3 tools/hex2bin.py build/myprog.hex prog.bin
```

### 5.3 仿真运行

```bash
# 汇编引导程序（只需做一次）
python3 tools/assembler.py tools/bootloader.asm -o build/bootloader.hex

# 仿真（引导程序自动加载 prog.bin）
iverilog -g2012 -DSIMULATION -DBOOT_HEX='"build/bootloader.hex"' \
  -o simv rtl/*.sv testbench/boot_tb.sv
vvp simv
```

### 5.4 上板运行（FPGA）

上板时串口真的连着 PC，PC 端用 Python 脚本通过串口发送 `prog.bin`：

```python
import serial, struct
with open('prog.bin', 'rb') as f:
    data = f.read()
ser = serial.Serial('COM3', 115200)
ser.write(data)
ser.close()
```

## 6. 与传统 CPU 的对应关系

| 传统 PC | MineCPU |
|---------|---------|
| BIOS / UEFI | Boot ROM (固定烧录) |
| 从硬盘加载 OS | 从 UART 接收程序 |
| 内存 | 指令 BRAM (双端口可写) |
| 换 OS = 重装系统 | 换游戏 = PC 发新 hex |
| CPU 不变 | CPU 不变 |
