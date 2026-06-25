# MineCPU 项目总结

> 从零搭建 RISC-V CPU：单周期 → RV32I 全指令 → UART → Bootloader → CSR 异常 → Pipeline → VGA

## 项目规模

| 指标 | 数值 |
|------|------|
| 硬件模块 | 14 个 (单周期) + 2 个 (流水线) |
| RTL 代码 | ~2500 行 SystemVerilog |
| C/汇编程序 | 15+ 个测试程序 |
| 工具脚本 | 7 个 Python 脚本 |
| 设计文档 | 5 篇 Markdown |
| 修复 Bug | 11 个（记录在案） |
| 支持指令 | 37 条 RV32I + 8 条 CSR + 6 条伪指令 |

## 架构演进

```
Phase 1: 基础 CPU (11条指令, 单周期)
    ↓
Phase 2: RV32I 全指令 (37条, 单周期) + UART + C 工具链
    ↓
Phase 3: Bootloader (UART 运行时程序加载)
    ↓
Phase 4: VGA 帧缓存 + PS/2 键盘 (MMIO 外设)
    ↓
Phase 5: CSR 寄存器 + 异常处理 (ecall/mret)
    ↓
Phase 6: 5 级流水线 (forwarding + stall + flush)
```

## 验证矩阵

### 单周期 CPU

| 测试 | 内容 | 结果 |
|------|------|:--:|
| test1_alu | add/sub/and/or | 4/4 ✅ |
| test2_mem | lw/sw 访存往返 | 4/4 ✅ |
| test3_branch | 分支取/不取 | 7/7 ✅ |
| test4_integration | 数组求和 | 2/2 ✅ |
| test5_rv32i | 全部新指令 | 25/26 ✅ |
| test_csr | CSR + 异常 | 6/6 ✅ |
| hello.c | C Hello World | ✅ |
| snake.c | 贪吃蛇 (UART) | ✅ |

### 流水线 CPU

| 测试 | 内容 | 结果 |
|------|------|:--:|
| pipe_fwd | 转发专项 | 4/4 ✅ |
| pipe_verify | 综合流水 | 6/7 ✅ |
| pipe_mini | 基础流水 | 2/2 ✅ |

## 工具链

```
C 源码 (snake.c)
  ↓ riscv-none-elf-gcc -march=rv32i -nostdlib -T link.ld
ELF (snake.elf)
  ↓ elf2hex.py (分离 code/data)
program.hex + data.hex
  ↓ cp → insn_mem + data_mem (仿真)
  ↓ hex2bin.py → prog.bin → UART (bootloader模式)
  ↓ hex2coe.py → Xilinx COE (Vivado模式)

CPU 仿真运行
```

## 文件结构

```
E:\CPU\
├── cpu/
│   ├── rtl/                         # 14个模块
│   │   ├── pipeline/                # 流水线 (2个)
│   │   │   ├── hazard.sv
│   │   │   └── pipeline_top.sv
│   │   ├── pc.sv
│   │   ├── insn_mem.sv
│   │   ├── boot_rom.sv
│   │   ├── regfile.sv
│   │   ├── alu.sv
│   │   ├── data_mem.sv
│   │   ├── imm_gen.sv
│   │   ├── control.sv
│   │   ├── csr.sv
│   │   ├── uart.sv
│   │   ├── baud_gen.sv
│   │   ├── vga_fb.sv
│   │   ├── ps2_kbd.sv
│   │   └── cpu_top.sv
│   ├── testbench/                   # 10个 testbench
│   ├── programs/                    # 15+ 测试程序
│   ├── tools/                       # 7个工具
│   ├── build/                       # 编译输出
│   └── Makefile
├── docs/superpowers/specs/
│   ├── cpu-walkthrough.md           # 第一阶段走读
│   ├── cpu-walkthrough-2.md         # 第二阶段走读
│   ├── minecpu-reference.md         # 参考手册
│   ├── bootloader-design.md         # Bootloader 设计
│   ├── pipeline-dev.md              # Pipeline 开发
│   └── final-summary.md             # 本文件
└── E:\iverilog\                     # Icarus Verilog 12
    E:\riscv-gcc\                    # RISC-V GCC 15.2
```

## 下一步

### Verilator 加速仿真 ✅

详见 `verilator-setup.md`。

- WSL Ubuntu 安装 Verilator，编译 C++ harness
- UART 加并行字节输出 (`tx_byte` + `tx_strobe`)，避免软件串行解码
- 蛇游戏实时交互：WASD 操控，终端渲染
- 速度提升 ~1000× vs Icarus

### Vivado 上板

1. 在 Vivado 中新建工程，选 EGO1 对应的 FPGA 型号 (XC7A35T)
2. 添加 `rtl/*.sv`（排除 `ifdef SIMULATION 块）
3. 用 hex2coe.py 把程序转成 .coe，初始化 BRAM
4. 加约束文件 .xdc（引脚映射：VGA/PS/2/UART/时钟/复位）
5. 综合 → 实现 → 生成 bitstream → 下载到 EGO1
6. 用 uart_tool.py 通过串口发程序、收输出

### 未来项目

1. **L2 Cache / 分支预测** — 性能优化
2. **简单 OS** — 多任务调度 + 系统调用
3. **图形/声音/手柄** — 多媒体外设
4. **SD 卡** — 文件系统 + 程序存储
