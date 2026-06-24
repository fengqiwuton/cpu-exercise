# RV32I Expansion Implementation Plan

> **Goal:** Expand from 11 instructions to full RV32I base integer ISA (37 instructions), enabling C compiler support.

> **Base:** Current single-cycle CPU at `/e/CPU/cpu/`

**Architecture:** Same Harvard single-cycle. Modify ALU (4 ops), data_mem (byte enable), imm_gen (U/J types), control (5 new opcodes), cpu_top (new data paths).

---
