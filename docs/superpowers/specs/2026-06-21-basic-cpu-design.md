# MineCPU — Basic Single-Cycle CPU Design

> Date: 2026-06-21 | Status: Design Complete

## 1. Scope

Implement a single-cycle RISC-V CPU supporting 11 instructions:

| Type | Instructions |
|------|-------------|
| Arithmetic | `add`, `sub`, `and`, `or` |
| Memory | `lw` (load word), `sw` (store word) |
| Branch | `beq`, `blt`, `bge`, `bltu`, `bgeu` |

- **Architecture**: Harvard (separate instruction & data memory)
- **Cycle**: Single-cycle (1 instruction = 1 clock cycle)
- **Language**: SystemVerilog (`.sv`)
- **Simulation**: Icarus Verilog + GTKWave (local); Vivado xsim (lab)
- **Target board**: EGO1 (FPGA)

## 2. Project Structure

```
cpu/
├── rtl/
│   ├── pc.sv
│   ├── insn_mem.sv
│   ├── regfile.sv
│   ├── alu.sv
│   ├── data_mem.sv
│   ├── control.sv
│   ├── imm_gen.sv
│   └── cpu_top.sv
├── testbench/
│   └── cpu_tb.sv
├── programs/
│   └── test1.hex
└── Makefile
```

## 3. Module Responsibilities

| File | Module | Description |
|------|--------|-------------|
| `pc.sv` | Program Counter | 32-bit register; outputs current PC; inputs next PC (PC+4 or branch target) |
| `insn_mem.sv` | Instruction Memory | Combinational read: addr → 32-bit instruction. Initialized via `$readmemh` from hex file |
| `regfile.sv` | Register File | 32 × 32-bit registers, x0 hardwired to 0. Two read ports + one write port |
| `alu.sv` | ALU | Two 32-bit operands + 4-bit control → result + zero/lt/ltu flags |
| `data_mem.sv` | Data Memory | Combinational read, clock-edge write. `$readmemh` initialization |
| `control.sv` | Control Unit | Opcode/funct3/funct7 → all control signals (combinational) |
| `imm_gen.sv` | Immediate Generator | Extracts and sign-extends immediate from instruction (I/S/B types) |
| `cpu_top.sv` | Top-Level | Instantiates all modules and wires up the datapath |

## 4. Datapath

```
                    ┌─────────────────────────────────────────┐
                    │              Control Unit                │
                    │  opcode/funct3/funct7 ──> 控制信号       │
                    └─────────────────────────────────────────┘
                         ▲                              │
                         │ instr[31:0]        控制信号分发到各模块
                         │                              │
┌──────┐  PC  ┌──────────┐  instr   ┌──────────┐      │
│  PC  │─────>│ Insn Mem │─────────>│ Imm Gen  │──────┤
│      │      └──────────┘          └──────────┘      │
│      │                              │ imm[31:0]     │
│      │                              │               │
│      │      ┌──────────┐  rs1/rs2  │               │
│      │      │ RegFile  │<──────────┼───────────────┤
│      │      │ (x0=0)   │───> rd1 ──┼──────────┐    │
│      │      └──────────┘───> rd2 ──┤          │    │
│      │                   ▲         │          │    │
│      │                   │ write   │    ┌─────▼────┐
│      │                   │ data    │    │   ALU    │
│      │                   │         │    │ zero/lt  │
│      │                   │         │    └─────┬────┘
│      │                   │         │          │ result
│      │                   │         │    ┌─────▼────┐
│      │                   │         │    │ Data Mem │
│      │                   │         │    │  r/w     │
│      │                   │         │    └─────┬────┘
│      │                   │         │          │ read_data
│      │                   └─────────┼──────────┘
│      │                             │  (MemtoReg mux)
│      │                             │
│      └─── PC+4 ────────────────────┤
│           branch_target ────────────┘  (PCSrc mux 控制)
```

### Multiplexers

| Mux | Location | Selects |
|-----|----------|---------|
| `ALUSrc` | ALU B input | 0 = rs2 value, 1 = immediate |
| `MemtoReg` | RegFile write data | 0 = ALU result, 1 = data memory read |
| `PCSrc` | PC next value | 0 = PC+4, 1 = branch target |

## 5. ALU

| ALUControl | Operation | Used By |
|------------|-----------|---------|
| `0000` | ADD | add, lw/sw address calc |
| `0001` | SUB | sub, beq (subtract and check zero) |
| `0010` | AND | and |
| `0011` | OR | or |
| `0100` | SLT (signed) | blt, bge |
| `0101` | SLTU (unsigned) | bltu, bgeu |

Flags: `zero` (result == 0), `lt` (signed less-than), `ltu` (unsigned less-than)

## 6. Control Signals

| Instruction | RegWrite | ALUSrc | MemWrite | MemtoReg | Branch | ALUControl |
|-------------|----------|--------|----------|----------|--------|-------------|
| `add` | 1 | 0 | 0 | 0 | 0 | `0000` ADD |
| `sub` | 1 | 0 | 0 | 0 | 0 | `0001` SUB |
| `and` | 1 | 0 | 0 | 0 | 0 | `0010` AND |
| `or` | 1 | 0 | 0 | 0 | 0 | `0011` OR |
| `lw` | 1 | 1 | 0 | 1 | 0 | `0000` ADD |
| `sw` | 0 | 1 | 1 | — | 0 | `0000` ADD |
| `beq` | 0 | 0 | 0 | — | 1 | `0001` SUB |
| `blt` | 0 | 0 | 0 | — | 1 | `0100` SLT |
| `bge` | 0 | 0 | 0 | — | 1 | `0100` SLT |
| `bltu` | 0 | 0 | 0 | — | 1 | `0101` SLTU |
| `bgeu` | 0 | 0 | 0 | — | 1 | `0101` SLTU |

### Branch Resolution (combinational, in cpu_top)

```verilog
PCSrc = Branch & (
    (funct3 == 3'b000 & zero)   |   // beq
    (funct3 == 3'b100 & lt)     |   // blt
    (funct3 == 3'b101 & ~lt)    |   // bge
    (funct3 == 3'b110 & ltu)    |   // bltu
    (funct3 == 3'b111 & ~ltu)       // bgeu
);
```

## 7. Instruction Encoding

RISC-V uses fixed 32-bit instructions. Four formats cover our 11 instructions.

### Format Bit Layouts

```
R-type (Register ops: add, sub, and, or)
┌──────────┬───────┬───────┬──────┬───────┬─────────┐
│ funct7   │ rs2   │ rs1   │funct3│ rd    │ opcode  │
│  31:25   │ 24:20 │ 19:15 │14:12 │ 11:7  │  6:0    │
│  7 bits  │ 5 bit │ 5 bit │3 bit │ 5 bit │ 7 bits  │
└──────────┴───────┴───────┴──────┴───────┴─────────┘

I-type (Load: lw)
┌───────────────┬───────┬──────┬───────┬─────────┐
│ imm[11:0]     │ rs1   │funct3│ rd    │ opcode  │
│    31:20      │ 19:15 │14:12 │ 11:7  │  6:0    │
│   12 bits     │ 5 bit │3 bit │ 5 bit │ 7 bits  │
└───────────────┴───────┴──────┴───────┴─────────┘

S-type (Store: sw)
┌──────────┬───────┬───────┬──────┬─────────┬─────────┐
│ imm[11:5]│ rs2   │ rs1   │funct3│imm[4:0] │ opcode  │
│   31:25  │ 24:20 │ 19:15 │14:12 │  11:7   │  6:0    │
└──────────┴───────┴───────┴──────┴─────────┴─────────┘

B-type (Branch: beq, blt, bge, bltu, bgeu)
┌──────────┬───────┬───────┬──────┬─────────┬─────────┐
│ imm[12|  │ rs2   │ rs1   │funct3│ imm[4:1 │ opcode  │
│  10:5]   │ 24:20 │ 19:15 │14:12 │   |11]  │  6:0    │
└──────────┴───────┴───────┴──────┴─────────┴─────────┘
```

Notes:
- S-type and B-type immediates are split across bit fields (to reuse register read ports). ImmGen must reassemble them.
- B-type immediate bit 0 is always 0 (instruction addresses are 2-byte aligned), so imm is stored starting from bit 1.

### Encoding Table

| Instruction | opcode[6:0] | funct3[14:12] | funct7[31:25] | Format |
|-------------|-------------|---------------|---------------|--------|
| add | `0110011` | `000` | `0000000` | R |
| sub | `0110011` | `000` | `0100000` | R |
| and | `0110011` | `111` | `0000000` | R |
| or | `0110011` | `110` | `0000000` | R |
| lw | `0000011` | `010` | — | I |
| sw | `0100011` | `010` | — | S |
| beq | `1100011` | `000` | — | B |
| blt | `1100011` | `100` | — | B |
| bge | `1100011` | `101` | — | B |
| bltu | `1100011` | `110` | — | B |
| bgeu | `1100011` | `111` | — | B |

## 8. Testing Strategy

### Testbench (`cpu_tb.sv`)

```
cpu_tb.sv
├── Generate clock (10ns period)
├── Generate reset (active high, first 2 cycles)
├── Instantiate cpu_top
├── Load program.hex via $readmemh into insn_mem
├── Monitor: PC, instruction, register writes, memory access
└── $finish after N cycles
```

### Test Program Hierarchy

| Test | Size | What It Verifies |
|------|------|------------------|
| Test 1 | 5–10 instructions | add/sub/and/or: check RegFile write-back values |
| Test 2 | ~15 instructions | lw/sw: sw to memory, lw back, compare |
| Test 3 | ~20 instructions | All 5 branch types: verify PC jumps correctly |
| Test 4 | ~30 instructions | Integration: a small meaningful program |

### From Assembly to Machine Code

Two options:
1. **Python assembler** (`tools/assembler.py`): Minimal assembler supporting only our 11 instructions. Input `.asm`, output `.hex`.
2. **RARS** (RISC-V Assembler and Runtime Simulator): [https://github.com/TheThirdOne/rars](https://github.com/TheThirdOne/rars) — GUI tool, generates machine code dumps.

### Defaults and Parameters

- **Reset PC**: 0x0000_0000
- **Instruction Memory depth**: parameter `IMEM_DEPTH = 1024` (4 KB)
- **Data Memory depth**: parameter `DMEM_DEPTH = 1024` (4 KB)
- **Clock freq (simulation)**: 100 MHz (10 ns period)

### Waveform Verification Checklist

For each cycle in GTKWave:
1. PC follows expected sequence (sequential or branch target)
2. RegFile write data matches expected computation result
3. Data Mem read/write address and data are correct

## 9. Resources

- **RISC-V Reference Card**: `docs/riscv-card.pdf` — quick lookup for instruction formats and encodings
- **Book**: Patterson & Hennessy, *Computer Organization and Design: RISC-V Edition* — Chapters 4 (datapath) and 6 (pipelining for later)
- **RISC-V Spec**: [Volume 1: Unprivileged ISA](https://github.com/riscv/riscv-isa-manual/releases)
- **Icarus Verilog Guide**: https://steveicarus.github.io/iverilog/
