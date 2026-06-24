# MineCPU Pipeline 开发文档

> 5 级流水 RV32I 处理器：IF → ID → EX → MEM → WB

## 架构

```
         IF/ID      ID/EX      EX/MEM     MEM/WB
  IF ─────────→ ID ────────→ EX ───────→ MEM ──────→ WB
  │              │            │           │           │
PC→IMEM      Decode+RF     ALU+Bypass  DataMem    RegFile写
              Branch解      Forward     LoadExt
```

### 流水线寄存器内容

| 寄存器 | 传递信号 |
|--------|----------|
| IF/ID | pc, pc+4, instr |
| ID/EX | reg_write, mem_write, mem_to_reg, alu_control, rs1/rs2/imm, rd, pc, pc4, jump_flag |
| EX/MEM | reg_write, mem_write, mem_to_reg, alu_result, rs2_data, rd, store_type, jump_flag, pc4 |
| MEM/WB | reg_write, mem_to_reg, alu_result, mem_data, rd, jump_flag, pc4 |

### 转发路径

| 从 | 到 | 条件 |
|----|----|------|
| EX (ex_alu_result) | ID (branch operands) | id_ex.rd == id_rs × back-to-back |
| EX/MEM (alu_result) | EX (ALU operands) | ex_mem.rd == ex_rs × |
| MEM/WB (cpu result) | EX (ALU operands) | mem_wb.rd == ex_rs × |
| EX/MEM (alu_result) | EX (store data) | ex_mem.rd == id_ex_rs2 |
| MEM/WB (cpu result) | EX (store data) | mem_wb.rd == id_ex_rs2 |
| EX/MEM (alu_result) | ID (branch) | ex_mem.rd == id_rs × |
| MEM/WB (cpu result) | ID (branch) | mem_wb.rd == id_rs × |

### Hazard 处理

| 场景 | 机制 | 停顿周期 |
|------|------|----------|
| RAW (EX→EX) | 转发 | 0 |
| RAW (MEM→EX) | 转发 | 0 |
| Load-use (lw → 下一条用) | 停顿 1 周期 + 转发 | 1 |
| Branch taken | 冲刷 IF | 1 |
| JAL/JALR | 冲刷 IF | 1 |
| Regfile write-read same cycle | 写旁路 (rs_bypass) | 0 |

---

## 验证结果

### test_pipe_fwd（转发专项）

| 测试 | 内容 | 结果 |
|------|------|:--:|
| TestA | RAW: x1=10, x2=x1+5=15, x3=x2+3=18 | ✅ |
| TestB | Load-use: lw→addi, 1 cycle stall | ✅ |
| TestC | Store forward: addi→sw | ✅ |
| TestD | Double load: lw+lw→add | ✅ |

### test_pipe（综合流水线）

| 测试 | 内容 | 结果 |
|------|------|:--:|
| Test1 | RAW forwarding (10+3=13) | ✅ |
| Test2 | Load-use stall (10+10=20) | ✅ |
| Test3 | Forward cascade (10+1+2+3=16) | ✅ |
| Test4 | Branch taken flush (x5=1) | ✅ |
| Test5 | Branch NOT taken (x5=42) | ✅ |
| Test6 | JAL return address | ⚠️ JAL→sw 转发待修 |
| Test7 | BNE taken flush (x8=10) | ✅ |

### test_pipe_mini（基础流水）

| 测试 | 内容 | 结果 |
|------|------|:--:|
| 独立指令 | addi×2 + sw×2，无依赖 | ✅ |

### 性能 (CPI)

```
完整程序: 29 条指令, 5000 周期, CPI≈2.0
有用指令: ~25 条, ~50 周期, CPI≈2.0
```
CPI 含死循环的 2485 次分支冲刷，有效指令 CPI 接近 2。

---

## 文件清单

```
rtl/pipeline/
├── hazard.sv         # 转发检测 + load-use stall
└── pipeline_top.sv   # 5级流水主模块

testbench/
├── pipe_tb.sv        # 基础流水测试
├── pipe_verify_tb.sv # 综合流水验证
├── pipe_fwd_tb.sv    # 转发专项验证
└── pipe_trace_tb.sv  # 逐级追踪

programs/
├── test_pipe.asm      # 综合流水测试
├── test_pipe_fwd.asm  # 转发专项
└── test_pipe_mini.asm # 基础流水
```

## 运行命令

```bash
# 转发专项
python3 tools/assembler.py programs/test_pipe_fwd.asm -o /tmp/fwd.hex
cp /tmp/fwd.hex program.hex
cp /tmp/test_data.hex programs/data.hex
iverilog -g2012 -DSIMULATION -o simv \
  rtl/pc.sv rtl/insn_mem.sv rtl/regfile.sv rtl/alu.sv \
  rtl/data_mem.sv rtl/imm_gen.sv rtl/control.sv \
  rtl/pipeline/hazard.sv rtl/pipeline/pipeline_top.sv \
  testbench/pipe_fwd_tb.sv
vvp simv

# 综合流水
cp programs/test_pipe.hex program.hex
iverilog -g2012 -DSIMULATION -o simv \
  rtl/{pc,insn_mem,regfile,alu,data_mem,imm_gen,control}.sv \
  rtl/pipeline/{hazard.sv,pipeline_top.sv} \
  testbench/pipe_verify_tb.sv
vvp simv
```

## 已知限制

1. **JAL 返回值转发**：`jal x7, label` 写入的 x7 无法被下一条 `sw x7` 转发（JAL 的 PC+4 不走 ALU pipeline）
2. **CSR/异常未集成到流水线**：pipeline_top 不包含 CSR 模块（需后续整合）
3. **MMIO 简化**：pipeline_top 只用 data_mem，没有 UART/VGA/PS/2

## 修复记录

| Bug | 根因 | 修复 |
|-----|------|------|
| Load-use 永久停顿 | ID/EX 只清 reg_write，没清 ex_mem_read | stall 时全清 ID/EX 控制信号 |
| 数据内存写无效 | byte_enable 用 EX 级地址，不是 MEM 级 | 改用 ex_mem_alu_result |
| Store data 为旧值 | 无 store data 转发 | 加 fwd_store_data 旁路 |
| EX/MEM 锁存旧 store data | 直接从 id_ex_rs2_data 锁存 | 改用 fwd_store_data |
| 分支用旧操作数 | ID 级无转发 | 加 br_rs1/br_rs2 转发 |
| 分支 back-to-back 旧值 | 未检查 EX 级（当前指令结果） | 转发优先级: EX > EX/MEM > MEM/WB |
