# 阶段一：协作式多任务调度器

## 目标

在现有单周期 RISC-V CPU 上，不改一行硬件，实现两个任务的协作式轮流运行。贪吃蛇在屏幕下半部分照常运行，计数器在左上角递增。

## 前置知识

### 什么是协作式多任务

当前程序结构：
```
main() {
    while(1) {
        跑贪吃蛇一帧
    }
}
```

目标结构：
```
main() {
    while(1) {
        跑计数器一帧
        yield();     ← 主动让出 CPU
        跑贪吃蛇一帧
        yield();     ← 主动让出 CPU
    }
}
```

每个任务跑一小段，主动调用 `yield()` 把 CPU 让给下一个任务。调度器负责保存当前任务的 CPU 寄存器，恢复下一个任务的寄存器。

### 上下文切换核心概念

RISC-V 有 32 个通用寄存器（x0-x31）。切换任务时需要：
1. 把当前任务的所有寄存器值保存到内存（任务 A 的"快照"）
2. 从内存恢复下一个任务的寄存器值（任务 B 的"快照"）

```
上下文切换 = 保存 x1-x31 + pc + sp → 切换到新 sp → 恢复 x1-x31 + 跳转到新 pc
```

x0 永远是 0，不需要保存。

### 任务控制块 (TCB)

每个任务在内存中有一个数据结构记录它的状态：

```c
typedef struct {
    uint32_t regs[32];   // 寄存器快照 x0-x31
    uint32_t sp;         // 栈指针
    uint32_t pc;         // 程序计数器（下次恢复时跳到哪里）
    uint8_t  sp_buf[256]; // 任务的独立栈（每个任务有自己的栈空间）
} tcb_t;
```

### 内存布局

```
0x00000000 ┌────────────┐
           │  .text     │  指令（所有任务共享）
0x00001000 ├────────────┤
           │  .data/.bss│  全局变量
           │  task_a_sp │  ← 任务 A 的栈（256 字节）
           │  task_b_sp │  ← 任务 B 的栈（256 字节）
           │  tcb_a     │  ← 任务 A 的 TCB
           │  tcb_b     │  ← 任务 B 的 TCB
0x00002000 └────────────┘  栈顶
```

## 实现计划

### Step 1：定义数据结构和全局变量

```c
// 任务状态
#define TASK_READY    0
#define TASK_RUNNING  1
#define TASK_BLOCKED  2

// 任务控制块
typedef struct {
    uint32_t sp;          // 保存的栈指针 (x2)
    uint32_t ra;          // 保存的返回地址 (x1)
    uint32_t s0_s11[12];  // 保存的 callee-saved 寄存器 (x8-x9, x18-x27)
    uint8_t  state;       // 当前状态
    uint8_t  stack[256];  // 独立栈空间
} tcb_t;

// 两个任务
tcb_t task_a;
tcb_t task_b;
tcb_t *current = &task_a;  // 当前运行的任务
int tick_counter = 0;       // 计数器任务的计数
```

### Step 2：编写上下文切换汇编

`yield()` 是调度器的核心。它用纯汇编实现：

```asm
# yield() — 保存当前上下文，切换到下一个任务
# 遵循 RISC-V calling convention：只保存 callee-saved 寄存器
# 因为 yield() 是从 C 函数中调用的，编译器已自动保存 caller-saved 寄存器

.globl yield
yield:
    # 1. 保存 callee-saved 寄存器到当前 TCB
    la   t0, current
    lw   t0, 0(t0)          # t0 = current TCB 地址
    sw   sp,  0(t0)          # 保存 sp
    sw   ra,  4(t0)          # 保存 ra
    sw   s0,  8(t0)          # 保存 s0
    sw   s1, 12(t0)          # 保存 s1
    # ... s2-s11
    sw   s11, 48(t0)

    # 2. 选择下一个任务（简单轮转：A→B→A→B）
    la   t0, current
    la   t1, task_a
    lw   t2, 0(t0)           # t2 = current
    bne  t2, t1, switch_to_a

switch_to_b:
    la   t1, task_b
    sw   t1, 0(t0)           # current = &task_b
    j    restore

switch_to_a:
    sw   t1, 0(t0)           # current = &task_a
    mv   t1, t1              # t1 = &task_a (already there)

    # 3. 恢复新任务的 callee-saved 寄存器
restore:
    lw   sp,  0(t1)          # 恢复 sp → 切换到新任务的栈
    lw   ra,  4(t1)          # 恢复 ra
    lw   s0,  8(t1)          # 恢复 s0
    # ...
    lw   s11, 48(t1)

    ret                       # 返回到新任务的调用点
```

### Step 3：初始化任务

```c
void task_init(tcb_t *task, void (*entry)(), uint8_t *stack_top) {
    // 手动构造栈帧：使得 restore 后 ret 能跳转到 entry
    uint32_t *sp = (uint32_t*)stack_top;
    *(--sp) = (uint32_t)entry;  // 压入入口地址（ret 会跳到这里）
    *(--sp) = 0;                // 压入假 ra
    // 压入假 s0-s11
    for (int i = 0; i < 12; i++) *(--sp) = 0;

    task->sp = (uint32_t)sp;    // 设置初始 sp
    task->ra = 0;
    for (int i = 0; i < 12; i++) task->s0_s11[i] = 0;
    task->state = TASK_READY;
}

void scheduler_init() {
    // 任务 A 的栈从 buffer 的末尾开始（栈向下增长）
    task_init(&task_a, task_counter, &task_a.stack[256]);
    task_init(&task_b, task_snake,   &task_b.stack[256]);
    current = &task_a;
}
```

### Step 4：编写两个任务函数

```c
// 任务 A：计数器，在左上角递增
void task_counter() {
    while (1) {
        tick_counter++;
        // 在 VGA 左上角 (2,2) 处显示数字
        draw_number(2, 2, tick_counter);
        yield();  // 主动让出 CPU
    }
}

// 任务 B：贪吃蛇（从 snake_vga.c 改）
void task_snake() {
    init_game();
    while (!over) {
        // 原 snake_vga.c 主循环的一个迭代
        clear_snake();
        process_input();
        move_snake();
        draw_food_and_snake();
        delay();
        yield();  // 主动让出 CPU
    }
    game_over_flash();
    while(1) yield();  // 游戏结束后一直让出 CPU
}
```

### Step 5：主函数

```c
int main() {
    *UART_BAUD = 20;

    // 清屏
    for (int i = 0; i < 4800; i++) FB[i] = BLACK;
    draw_border();  // 全屏边框
    // 画一条水平分割线（游戏区和计数器区）
    for (int x = 0; x < 40; x++) FB[5*80 + x] = WHITE;

    scheduler_init();
    current->state = TASK_RUNNING;

    // 调度器入口：恢复第一个任务的上下文并跳转
    scheduler_start();  // 汇编函数，类似 yield() 的 restore 部分

    return 0;  // 永不执行
}
```

### Step 6：scheduler_start 汇编

```asm
.globl scheduler_start
scheduler_start:
    la   t0, current
    lw   t0, 0(t0)          # t0 = &task_a
    lw   sp, 0(t0)          # 恢复 sp
    lw   ra, 4(t0)          # 恢复 ra
    lw   s0, 8(t0)          # 恢复 s0-s11
    # ...
    lw   s11, 48(t0)
    ret                      # 跳转到任务 A 的入口函数
```

## 函数调用约定（RISC-V calling convention）

为什么只保存 s0-s11 而不是全部寄存器？RISC-V 规定：

| 寄存器 | ABI 名称 | 保存者 | 用途 |
|--------|----------|--------|------|
| x1 | ra | **被调用者** | 返回地址 |
| x2 | sp | **被调用者** | 栈指针 |
| x5-x7 | t0-t2 | 调用者 | 临时寄存器 |
| x8-x9 | s0-s1 | **被调用者** | 保存寄存器 |
| x10-x17 | a0-a7 | 调用者 | 函数参数 |
| x18-x27 | s2-s11 | **被调用者** | 保存寄存器 |
| x28-x31 | t3-t6 | 调用者 | 临时寄存器 |

`yield()` 是 C 函数调用的，**调用者**（编译器生成的代码）已经保存了 t0-t6、a0-a7。`yield()` 只需要保存**被调用者**需要保存的：ra、sp、s0-s11。

## 文件清单

| 文件 | 内容 | 大小估计 |
|------|------|----------|
| `programs/task_scheduler.c` | 调度器初始化、主函数、任务入口 | ~100 行 |
| `programs/task_counter.c` | 计数器任务 | ~30 行 |
| `programs/task_snake.c` | 贪吃蛇任务（从 snake_vga.c 剥离） | ~100 行 |
| `programs/yield.s` | 上下文切换汇编（yield + scheduler_start） | ~80 行 |
| `programs/draw_utils.c` | 画数字/字符的辅助函数 | ~40 行 |

## 构建命令

```bash
cd /mnt/e/CPU/cpu
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c programs/task_scheduler.c -o build/scheduler.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c programs/task_counter.c -o build/counter.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c programs/task_snake.c -o build/snake_task.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c programs/draw_utils.c -o build/draw_utils.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
  -c programs/yield.s -o build/yield.o
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding \
  -T tools/link.ld build/crt0.o build/scheduler.o build/counter.o \
  build/snake_task.o build/draw_utils.o build/yield.o \
  -o build/scheduler.elf -lgcc
python3 tools/elf2hex.py build/scheduler.elf \
  --code build/scheduler_code.hex --data build/scheduler_data.hex
cp build/scheduler_code.hex sim/program.hex
cp build/scheduler_data.hex sim/data.hex
cd sim && make clean && make dump
```

## 预期效果

BMP 输出应显示：
- 全屏白色边框
- 第 5 行一条水平分割线
- 分割线上方（行 0-4）：计数器数字递增
- 分割线下方（行 6-29）：贪吃蛇正常运行
- 蛇和计数器交替运行，互不干扰

## 调试要点

1. **yield() 后程序崩溃** → 检查寄存器保存/恢复顺序是否正确
2. **任务 A 运行后任务 B 不运行** → 检查 current 指针切换逻辑
3. **栈溢出** → 每个任务栈 256 字节。蛇的局部变量多可能不够，增大 stack 数组
4. **蛇速变快或变慢** → yield() 频率决定了每个任务分到的时间。可在 yield() 前后加延迟循环

---

# 阶段二：抢占式多任务 + 硬件定时器

## 目标

在阶段一的协作式调度基础上，加入硬件定时器模块，实现**抢占式多任务**——不再需要任务主动调用 `yield()`，定时器中断会自动触发任务切换。

## 为什么需要抢占式

协作式的致命弱点：如果任务 A 写了一个死循环忘了 `yield()`，整个系统卡死。抢占式通过硬件定时器强制每隔 N 个周期切换一次任务。

## 硬件改动

### 新增 `rtl/timer.sv`（~60 行）

```verilog
// timer.sv — 可编程间隔定时器
// MMIO 地址: 0x40000040 (控制), 0x40000044 (计数值)
// 控制寄存器 bit 0: 使能, bit 1: 中断标志（读后自动清除）
module timer #(parameter CLK_FREQ = 50_000_000) (
    input  logic        clk, rst_n,
    input  logic        cs,
    input  logic [31:0] addr,
    input  logic [31:0] write_data,
    input  logic        mem_write,
    output logic [31:0] read_data,
    output logic        irq          // 中断信号 → cpu_top
);
    logic [31:0] compare;   // 比较值（多久触发一次）
    logic [31:0] counter;   // 当前计数
    logic        enabled;
    logic        irq_flag;

    assign irq = irq_flag;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compare  <= 32'h00010000; // 默认 ~65536 周期触发
            counter  <= 0;
            enabled  <= 0;
            irq_flag <= 0;
        end else begin
            // CPU 读写
            if (cs && mem_write) begin
                if (addr[2]) compare <= write_data;     // 0x44: 设置比较值
                else begin                               // 0x40: 控制
                    enabled  <= write_data[0];
                    irq_flag <= irq_flag & ~write_data[1]; // 写 1 清除
                end
            end
            if (cs && !mem_write) read_data <= addr[2] ? compare : {30'b0, irq_flag, enabled};

            // 计数逻辑
            if (enabled) begin
                if (counter >= compare) begin
                    counter  <= 0;
                    irq_flag <= 1;  // 触发中断
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end
endmodule
```

### 修改 `rtl/cpu_top.sv`（~5 行）

在 MMIO 路由中新增 timer 口，把 timer 的 `irq` 信号接入已有的异常/中断路径：

```verilog
// 新增 MMIO 选择
assign timer_sel = io_sel && (alu_result[15:12] == 4'h0) && (alu_result[5:4] == 2'd1);

// 新增 IRQ 来源
assign irq_pending = timer_irq;  // 挂到现有的异常逻辑上

// timer 实例化
timer u_timer (.clk, .rst_n, .cs(timer_sel), .addr(alu_result),
               .write_data(store_data), .mem_write(mem_write && timer_sel),
               .read_data(timer_read_data), .irq(timer_irq));
```

## 软件改动

### 中断服务例程 (ISR)

定时器中断发生时，CPU 自动跳转到 `mtvec` 指向的地址：

```asm
# isr_entry.s — 中断入口
.globl isr_entry
isr_entry:
    # 硬件已自动保存 mepc、mcause 到 CSR
    # 手动保存全部 caller-saved 寄存器
    sw   ra,  0(sp)
    sw   t0,  4(sp)
    sw   t1,  8(sp)
    # ... t2-t6, a0-a7
    addi sp, sp, -64   # 为寄存器腾空间

    # 调用 C 中断处理函数
    call isr_handler

    # 恢复寄存器
    addi sp, sp, 64
    lw   ra,  0(sp)
    # ... 恢复全部
    mret                  # 返回到被中断的指令
```

### C 中断处理函数

```c
void isr_handler() {
    uint32_t cause;
    asm volatile("csrr %0, mcause" : "=r"(cause));

    if (cause & 0x80000000) {  // 中断（bit 31=1）
        uint32_t irq_num = cause & 0x7FFFFFFF;
        if (irq_num == 7) {    // 机器定时器中断
            yield();           // 强制切换任务
            // 清除定时器中断标志
            *(volatile uint32_t*)0x40000040 |= 2;
        }
    }
}

void timer_init(uint32_t interval) {
    *(volatile uint32_t*)0x40000044 = interval;  // 设置间隔
    *(volatile uint32_t*)0x40000040 = 1;          // 使能
    // 设置 mtvec 指向 isr_entry
    asm volatile("csrw mtvec, %0" :: "r"((uint32_t)isr_entry));
    // 使能中断
    asm volatile("csrw mstatus, %0" :: "r"(1 << 3));  // MIE bit
    asm volatile("csrw mie, %0" :: "r"(1 << 7));       // MTIE bit
}
```

## 关键差异：协作式 vs 抢占式

| | 协作式（阶段一） | 抢占式（阶段二） |
|---|---|---|
| 切换触发 | 任务主动调 `yield()` | 硬件定时器中断 |
| 任务卡死 | 整个系统死 | 定时器中断强行切换 |
| 寄存器保存 | 只存 callee-saved (14个) | 全部 32 个寄存器 + CSR |
| 硬件依赖 | 无 | timer.sv 模块 |
| 中断延迟 | N/A | ~10 个周期 |
| 复杂度 | ~200 行 C + ~50 行汇编 | +~60 行 Verilog + ~100 行 ISR |

---

# 阶段三：用户态 + 系统调用

## 目标

把程序分成**内核态**和**用户态**。用户程序不能直接访问硬件（VGA、UART），必须通过 `ecall` 陷入内核。贪吃蛇作为用户进程运行。

## 为什么需要用户态

当前：任何代码可以随意写 `*(volatile uint32_t*)0x40002000 = BLACK` 破坏帧缓冲。缺少内存保护，无法运行不信任的代码。

用户态：硬件限制用户程序只能访问自己的内存区域，访问硬件必须通过内核的系统调用。这是现代操作系统安全的基石。

## 特权级设计

RISC-V 定义了三个特权级，本项目使用其中两个：

```
内核态 (Machine Mode, M-mode)
  │
  │  ecall (陷入)
  │
  ▼
用户态 (User Mode, U-mode)
```

| 能力 | M 态（内核） | U 态（用户程序） |
|------|-------------|-----------------|
| 访问任意内存 | ✓ | ✗（只允许自己的区域） |
| 访问 MMIO (VGA/UART) | ✓ | ✗ |
| 执行 ecall | 触发异常 | ✓（进入内核） |
| 执行 mret | ✓（返回用户态） | ✗ |
| 读写 CSR | ✓ | ✗（触发异常） |
| 修改 mstatus | ✓ | ✗ |

## 系统调用表

```c
#define SYS_WRITE   1   // 写像素到 VGA
#define SYS_READ    2   // 读键盘输入
#define SYS_YIELD   3   // 让出 CPU
#define SYS_EXIT    4   // 进程退出
```

用户态程序通过 `ecall` 调用系统调用：

```c
// 用户态代码：画一个像素
void user_draw_pixel(int x, int y, int color) {
    asm volatile(
        "li a7, %0\n"      // a7 = 系统调用号 (SYS_WRITE)
        "mv a0, %1\n"      // a0 = x
        "mv a1, %2\n"      // a1 = y
        "mv a2, %3\n"      // a2 = color
        "ecall"            // 触发异常，进入内核
        :: "i"(SYS_WRITE), "r"(x), "r"(y), "r"(color)
        : "a0", "a7"
    );
}
```

内核端处理：

```c
void syscall_handler(uint32_t sysno, uint32_t a0, uint32_t a1, uint32_t a2) {
    switch (sysno) {
        case SYS_WRITE: {
            // 内核态：验证地址在用户区域，然后代理写入
            int x = (int)a0, y = (int)a1;
            if (x >= 0 && x < 80 && y >= 0 && y < 60)
                FB[y*80 + x] = (uint8_t)a2;
            break;
        }
        case SYS_READ: {
            // 从 UART 读一个按键
            while (!(*UART_STATUS & 2));  // 阻塞等待
            // 返回值写入 a0 (通过 mepc 处的指令修改)
            break;
        }
        case SYS_YIELD:
            yield();
            break;
        case SYS_EXIT:
            // 标记进程为已退出，调度器不再调度它
            current->state = TASK_EXITED;
            yield();
            break;
    }
}
```

## ecall 异常处理流

```
用户程序:
  ecall
    ↓
CPU 硬件自动:
  mepc  ← 当前 PC      (保存返回地址)
  mcause ← 8/9/11      (环境调用异常号)
  mstatus.MPP ← U-mode (保存原特权级)
  mstatus.MIE ← 0      (禁止中断嵌套)
  PC ← mtvec            (跳转到异常处理入口)
    ↓
内核 ISR:
  读取 a7 → 系统调用号
  读取 a0-a6 → 参数
  执行 syscall_handler()
  结果写入 a0
  mret                  (返回用户态)
    ↓
CPU 硬件自动:
  PC ← mepc + 4        (返回 ecall 的下一条指令)
  恢复 mstatus
    ↓
用户程序:
  继续执行
```

## 软件结构变化

```
阶段二的程序:                    阶段三的程序:
┌─────────────┐                ┌──────────────────┐
│  任务 A (蛇) │                │  用户层           │
│  任务 B (计数)│               │  ┌──────┐┌──────┐│
│      │       │               │  │蛇任务││计数任││
│   直接访问    │               │  │(U态) ││务(U态││
│   VGA/UART   │               │  └──┬───┘└──┬───┘│
└─────────────┘                │     │ecall │ecall│
                               │  ┌──┴──────┴───┐│
                               │  │  系统调用处理 ││
                               │  │  (M态内核)   ││
                               │  └──────┬───────┘│
                               │         │        │
                               │    直接访问       │
                               │    VGA/UART      │
                               └──────────────────┘
```

---

# 阶段四：文件系统 + Shell

## 目标

在数据存储器里划一块区域模拟磁盘，实现简单文件系统。写一个交互式 Shell：`ls` 列出文件、`cat` 显示内容、`run` 加载并执行程序。

## 磁盘抽象

在 data_mem 里划出 2KB 作为"磁盘"：

```
数据存储器布局 (0x1000-0x1FFF):
┌────────────┐
│ 内核数据    │  0x1000-0x13FF
├────────────┤
│ "磁盘"块0  │  0x1400  ← 第一个磁盘块
│ "磁盘"块1  │  0x1500
│ "磁盘"块2  │  0x1600
│    ...     │
│ "磁盘"块11 │  0x1F00  ← 最后一个磁盘块（每块 256 字节，共 3KB）
└────────────┘
```

## 微型文件系统 (MinFS)

每个文件 = 一个索引节点 (inode) + 若干数据块。

```c
#define BLOCK_SIZE 256
#define MAX_FILES 16
#define DISK_BASE  ((uint8_t*)0x00001400)

typedef struct {
    char     name[16];      // 文件名
    uint32_t size;          // 文件大小
    uint8_t  blocks[8];     // 数据块索引（最多 8 块 = 2KB）
    uint8_t  used;          // 是否在用
} inode_t;

typedef struct {
    inode_t inodes[MAX_FILES];
    uint8_t block_map[12];  // 块分配位图（12 块）
} superblock_t;              // 存放在块 0
```

### API

```c
int   minfs_create(const char *name);            // 创建文件
int   minfs_open(const char *name);              // 打开文件
int   minfs_read(int fd, void *buf, int size);   // 读文件
int   minfs_write(int fd, void *buf, int size);  // 写文件
int   minfs_list(char names[][16], int max);     // 列出文件
```

## Shell 实现

```c
void shell() {
    char cmd[32], arg[32];
    while (1) {
        uart_puts("$ ");
        shell_readline(cmd, arg);

        if      (strcmp(cmd, "ls") == 0)   shell_ls();
        else if (strcmp(cmd, "cat") == 0)  shell_cat(arg);
        else if (strcmp(cmd, "run") == 0)  shell_run(arg);
        else if (strcmp(cmd, "echo") == 0) uart_puts(arg);
        else if (strcmp(cmd, "help") == 0) shell_help();
        else uart_puts("unknown command\n");
    }
}
```

`run` 命令最关键：从磁盘加载一个 ELF 文件的 .text/.data 段到内存，创建新的用户进程，调度运行。

## 演示场景

```
$ ls
  snake.elf  2048 bytes
  counter.elf 512 bytes
  readme.txt 128 bytes
$ cat readme.txt
Welcome to MineCPU OS!
$ run snake.elf
[snake game starts running in the background]
$ run counter.elf
[counter starts in parallel]
$ ls
  snake.elf  2048 bytes
  counter.elf 512 bytes
  readme.txt 128 bytes
```

---

# 参考资源

| 资源 | 覆盖阶段 | 语言/平台 | 难度 | 备注 |
|------|---------|----------|------|------|
| **xv6 (MIT)** | 全部 | C, RISC-V | 中高 | 完整教学 OS，配套书籍《xv6: a simple, Unix-like teaching operating system》 |
| **Writing a Simple OS from Scratch** (Nick Blundell) | 一、二 | C, x86 | 低 | 从 bootloader 开始的极简教程 |
| **MMURTL** | 二、三 | C, x86 | 中 | 微内核设计，代码极度精简 |
| **rCore** (清华大学) | 全部 | Rust, RISC-V | 高 | 有详细中文文档和视频 |
| **RISC-V Privileged Spec** | 三 | — | 参考 | 第 3 章（Machine-Level ISA）是阶段三的权威参考 |
| **The Little Book About OS Development** | 一、二 | C, x86 | 低 | 入门友好，5 章即可写出简单调度器 |
| **FAT12/FAT16 规范** (Microsoft) | 四 | — | 低 | 30 页白皮书，实现文件系统的最佳参考 |
| **Build Your Own Shell** (CodeCrafters) | 四 | C | 低 | 交互式 Shell 教程 |

---

# 各阶段总览

```
阶段一 ──→ 阶段二 ──→ 阶段三 ──→ 阶段四
(不改HW)   (加timer)  (改cpu_top) (不改HW)

协作调度    抢占调度    用户态      Shell+FS
200行C      60行Verilog  改ecall     微型文件系统
50行汇编    100行ISR    系统调用表    run命令加载ELF
                        特权级隔离    ls/cat/echo

产出:       产出:       产出:        产出:
双任务轮流  定时器中断   内核态/用户  交互式操作
计数器+蛇   强制切换     态分离      系统雏形
```
