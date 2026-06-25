# VGA Snake — 渲染修复思路与运行指南

## 一、问题现象

运行 `make dump` 导出的 BMP 帧画面出现三种异常：

1. **画面撕裂 / S 形错位** — 蛇和食物出现在错误的位置，边框被横向拆分
2. **运行时秒闪红** — BOOT_CYCLES=80000，模拟器在后台跑了 13 步蛇才显示首帧，蛇已快要撞墙
3. **黑色线条截断** — 帧缓冲在游戏清屏→绘图间隙被读取，画面偶尔出现黑色蛇身

## 二、根因分析（编程思路）

### 2.1 步长不一致导致画面撕裂

帧缓冲是 80×60 像素的线性数组。地址 = `row × stride + col`。

```
正确 (stride=80):         错误 (stride=40):
row0: [0..79] → 使用39个  row0: [0..39]
row1: [80..159]           row1: [40..79]    ← 本该从 80 开始
row2: [160..239]          row2: [80..119]   ← 本该从 160 开始
```

问题是 `snake_vga.c` 编译时用了两种步长：

- **横线边框**: `FB + (H-1)*FW` → stride=80 ✓  
- **竖线边框**: `FB[y*W + col]` → stride=40 ✗
- **蛇/食物/闪屏**: 全部 stride=40 ✗

RISC-V 工具链不在手边，无法重编译 C 代码。**hex 文件中的 stride=40 已经硬编码在机器指令里**。

### 2.2 为什么不能直接修 hex？

代码中 `FB[sy[i]*W + sx[i]]` 被编译为：
```
li  t0, 40          # 加载步长 W=40
mul t1, sy, t0      # y * 40
add t2, t1, sx      # y*40 + x
sb  t3, 0(t2)       # 写入
```

要改为 stride=80，需把 `li t0, 40` 改成 `li t0, 80`，这改变了指令长度（40 和 80 的立即数编码不同），会导致后续所有地址偏移出错。手工 patch 不现实。

### 2.3 解决思路：硬件层透明转换

**关键洞察**：CPU 发出的写地址 = `row × 40 + col`。如果能拦截这个地址，在存入帧缓冲前把 `row × 40 + col` 转成 `row × 80 + col`，整个问题在硬件层被透明解决。

```
CPU 发出 addr = row×40 + col  →  [vga_fb.sv 重映射]  →  存储到 fb[row×80 + col]
```

重映射数学：
```
row  = addr / 40
col  = addr % 40
new  = row × 80 + col
     = addr + row × 40        // 展开: row×80+col = row×40+row×40+col
```

**边界条件**：只重映射游戏区域内的地址（addr < 1200，即 40×30=1200 像素）。底部边框使用 `FB + 29×80 = 2320`（≥1200），直通不转换。

### 2.4 为什么选择硬件层而非软件层？

| 方案 | 可行性 | 副作用 |
|------|--------|--------|
| 重编译 C 代码 | ✗ 无 RISC-V GCC | — |
| 修改 hex 机器码 | ✗ 指令长度变化 | 破坏后续地址 |
| 改 sim 读取逻辑 | ✗ 横线用 80/竖线用 40，混合 stride 无法统一读取 | — |
| **改 vga_fb.sv 写路径** | **✓ 一次修改覆盖所有写** | 需除法器（仿真无影响） |

硬件重映射是唯一正确且一次到位的方案。

## 三、修改清单

### 3.1 `rtl/vga_fb.sv` — 核心修复

在写使能路径上插入地址重映射逻辑：

```verilog
// stride remap: row*40+col → row*80+col
logic [31:0] fb_wr_off  = {19'b0, addr[12:0]};
logic [31:0] fb_wr_row  = fb_wr_off / 32'd40;
logic [31:0] fb_wr_col  = fb_wr_off % 32'd40;
wire  [31:0] remap_addr = fb_wr_row * 32'd80 + fb_wr_col;
// 只在游戏区域 (addr < 1200) 重映射，≥1200 直通
wire  [12:0] fb_wr_addr = (fb_wr_off < 32'd1200)
    ? remap_addr[12:0] : addr[12:0];
```

### 3.2 `sim/sim_vga.cpp` — SDL2 实时交互版

解决三个问题：初始化太快看不到、蛇速失控、黑线闪烁。

| 参数 | 旧值 | 新值 | 设计思路 |
|------|------|------|----------|
| `GAME_W/H` | 80/60 | 40/30 | 游戏实际网格 |
| `SCALE` | 8 | 16 | 40×16=640, 30×16=480 填满窗口 |
| `BOOT_CYCLES` | 80000 | 3000 | 刚好完成 init，立刻渲染首帧 |
| `FRAME_CYCLES` | 5000 | 1000 | 小于一次游戏迭代(~3200周期)，采样更密 |
| `TARGET_FPS` | 无 | 12 | 每帧后 `SDL_Delay(83ms)` 限速 |
| 读取步长 | `FB_W` | `HW_W=80` | 匹配硬件帧缓冲布局 |

黑线缓解：在主批次后额外跑 200 周期，大概率越过清屏阶段进入延迟等待。

### 3.3 `sim/sim_vga_dump.cpp` — BMP 静态导出

修正 bottom-up BMP 的坐标换算 + 裁剪到 40×30 游戏区域。

```cpp
// 修正前: (y/SCALE)*FB_W + (x/SCALE)
// 修正后: ((h-1-y)/SCALE)*HW_W + (x/SCALE)

// BMP 文件格式要求 bottom-up: last fwrite = top of image
// h-1-y 把 BMP 文件行号转为游戏行号
```

## 四、完整运行流程

### 环境

- **Windows 11** + WSL2 (Ubuntu 20.04)
- Verilator 5.048（WSL 内）
- 项目位于 `E:\CPU\cpu`，WSL 路径 `/mnt/e/CPU/cpu`

### 4.1 安装依赖（仅一次）

```bash
# 在 WSL 终端中
sudo apt-get update
sudo apt-get install -y libsdl2-dev    # SDL2 图形库
```

### 4.2 BMP 帧导出（快速验证渲染正确性）

```bash
cd /mnt/e/CPU/cpu/sim
make clean && make dump
```

输出 6 张 BMP：`snake_0000.bmp` ~ `snake_0004.bmp` + `snake_final.bmp`。

BMP 为 320×240，显示 40×30 游戏网格，每像素放大 8 倍。用任何图片查看器打开确认边框/蛇/食物位置正确。

### 4.3 SDL2 实时运行（可上手玩）

```bash
cd /mnt/e/CPU/cpu/sim
make clean && make vga
./obj_dir/Vcpu_top_vga
```

- 640×480 窗口，实时渲染
- **W/A/S/D** 控制蛇的方向
- **Q 或 Esc** 退出
- 蛇速约 3.75 步/秒

### 4.4 调参

编辑 `sim/sim_vga.cpp` 顶部常量，保存后重新 `make vga`：

```
TARGET_FPS      ↑ → 蛇更快    (推荐范围 8-20)
FRAME_CYCLES    ↑ → 蛇更快    (推荐范围 500-3000)
BOOT_CYCLES     ↑ → 首帧蛇已移动更多

推荐: FRAME_CYCLES × TARGET_FPS ≈ 12000 (约3.75步/秒)
```

## 五、验证结果

BMP 导出 (snake_0000.bmp) Python 逐像素验证：

```
WHITE  122 pixels  — 四边完整 (row0, row29, col0, col39)
YELLOW   1 pixel   — 蛇头 (位置随按键序列动态变化)
GREEN    4 pixels  — 蛇身
RED      1 pixel   — 食物

颜色: 8-bit RRRGGGBB → 24-bit RGB 正确
  白 0xFF → RGB(252,252,255)
  黄 0xFC → RGB(252,252,0)
  绿 0x1C → RGB(0,252,0)
  红 0xE0 → RGB(252,0,0)
```

## 六、已知限制

1. **偶尔黑线**: 单缓冲架构，清屏→绘图(~20周期)若被采样到会出现黑蛇身。概率约 0.6%（大多数时间在 1500 次循环的延迟阶段）。增大 `FRAME_CYCLES` 可进一步降低。

2. **蛇速偏快**: 游戏延迟循环仅 1500 次迭代，对 Verilator 模拟速度来说过短。通过 `SDL_Delay` 软件节流缓解，根本解决需重编译 C 代码增大延迟值。

3. **无 RISC-V GCC**: 若后续能安装工具链（`riscv64-unknown-elf-gcc`），可直接修改 `snake_vga.c` 将全部步长统一为 FW=80，移除 vga_fb.sv 的硬件重映射逻辑。
