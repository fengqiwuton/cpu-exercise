# MineCPU Verilator 加速仿真

> Icarus 仿真 1 秒游戏逻辑需几分钟，Verilator 实现实时交互。

## 环境

| 组件 | 路径 |
|------|------|
| Verilator | WSL Ubuntu `apt install verilator` (v5.048) |
| g++ | WSL 自带 (v14) |
| RISC-V GCC | `/mnt/e/riscv-gcc/...` (E 盘，WSL 可访问) |

## 架构

```
sim_main.cpp (C++ 交互层)
    ├── 键盘输入 → uart_rx_pin (串行)
    ├── cpu_top (Verilog → C++)
    ├── uart_tx_byte + tx_strobe → printf (并行字节)
    └── 时钟/复位控制
```

**关键改动：** 给 UART 加了并行输出端口 `tx_byte[7:0]` + `tx_strobe`，Verilator 直接读字节而非软件解码串行信号，避免时序偏差。

## 文件

| 文件 | 说明 |
|------|------|
| `cpu/sim/sim_main.cpp` | C++ harness：键盘→UART RX，UART TX→终端 |
| `cpu/sim/Makefile` | Verilator 编译：`make sim` |
| `cpu/rtl/uart.sv` | 加 `tx_byte`, `tx_strobe` 输出 |
| `cpu/rtl/cpu_top.sv` | 加 `uart_tx_byte`, `uart_tx_strobe` 端口 |
| `cpu/rtl/regfile.sv` | 去掉写旁路（Verilator 检测到组合逻辑环路） |

## 编译运行蛇

```bash
# 1. 进入 WSL
wsl

# 2. 设置PATH
export PATH="/mnt/e/riscv-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$PATH"

# 3. 编译蛇的 C 代码
cd /mnt/e/CPU/cpu
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c programs/snake.c -o build/snake.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding \
  -T tools/link.ld build/crt0.o build/snake.o -o build/snake.elf -lgcc
python3 tools/elf2hex.py build/snake.elf --code build/snake_code.hex \
  --data build/snake_data.hex --data-base 0 --data-size 0x2000

# 4. 复制 hex 到 sim 目录
cp build/snake_code.hex sim/program.hex
cp build/snake_data.hex sim/programs/data.hex

# 5. Verilator 编译 + 运行
cd sim
make clean && make sim
```

## 操控

- `W/A/S/D` — 蛇的方向
- `Q` — 退出
- 实时交互，终端渲染

## Verilator 常用命令

```bash
# 编译（自动 make -j）
make sim

# 手动编译（分步）
verilator --cc --exe --build -DSIMULATION --top-module cpu_top \
  ../rtl/*.sv sim_main.cpp -o Vcpu_top

# 清理
make clean

# 跑其他程序（替换 program.hex）
cp ../programs/hello_code.hex program.hex
make sim
```

## 性能对比

| 指标 | Icarus | Verilator |
|------|--------|-----------|
| test1_alu (10条指令) | ~0.1s | ~0.001s |
| 蛇 1 帧 (~50条指令) | ~2s | ~0.02s |
| VGA 蛇 (千次 framebuffer 写) | 极慢 | 可实时 |

## 调试要点

| 问题 | 原因 | 修复 |
|------|------|------|
| `DIDNOTCONVERGE` | regfile 写旁路造成组合环路 | 去掉旁路 |
| 终端输出乱码 | `$write` 和 `printf` 冲突 | 删 `$write`，改用并行 `tx_byte` |
| 字符重复 | 软件 UART 解码采样偏移 | 用并行字节接口 |
| 蛇跑太快 | 游戏 `delay()` 太少 | 增大 delay 或降 BAUD |
| `pin connect empty` warning | VGA/PS2 端口悬空 | `-Wno-PINCONNECTEMPTY` |

## 注意

- `snake.c` 里 `*UART_BAUD = 20` 必须和 `sim_main.cpp` 里的 `BAUD = 20` 一致
- Verilator 的 `$readmemh` 从**当前工作目录**加载文件，hex 文件必须放在 `sim/` 下
- WSL 访问 E 盘路径：`/mnt/e/...`
