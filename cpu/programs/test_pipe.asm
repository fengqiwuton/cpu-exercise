# test_pipe.asm — Pipeline verification: forwarding, stall, branch flush, CPI
# Data: [0]=10, [4]=3

# === Test 1: RAW forwarding EX→EX (no stall needed) ===
lw x1, 0(x0)          # x1 = 10
lw x2, 4(x0)          # x2 = 3
add x3, x1, x2        # x3 = 13 (needs forwarding from lw x2)
sw x3, 16(x0)         # mem[16] = 13

# === Test 2: Load-use stall ===
lw x1, 0(x0)          # x1 = 10
addi x4, x1, 10       # x4 = 20 (load-use: needs 1 cycle stall)
sw x4, 20(x0)         # mem[20] = 20

# === Test 3: Chain of dependencies (forwarding cascade) ===
lw x1, 0(x0)          # x1 = 10
addi x2, x1, 1        # x2 = 11 (forward from WB)
addi x3, x2, 2        # x3 = 13 (forward from EX/MEM)
addi x4, x3, 3        # x4 = 16 (forward from EX/MEM)
sw x4, 24(x0)         # mem[24] = 16

# === Test 4: Branch taken (flush IF) ===
addi x5, x0, 1        # x5 = 1
beq x5, x5, skip1     # always taken → flush IF
addi x5, x0, 99       # (should NOT execute: flushed)
skip1:
sw x5, 28(x0)         # mem[28] = 1

# === Test 5: Branch NOT taken ===
addi x6, x0, 2
beq x5, x6, skip2     # NOT taken (1 != 2) → no flush
addi x5, x0, 42       # should execute
skip2:
sw x5, 32(x0)         # mem[32] = 42

# === Test 6: JAL jump (flush) ===
jal x7, target
addi x7, x0, 99       # flushed
target:
sw x7, 36(x0)         # mem[36] = return address

# === Test 7: bne taken (flush) ===
addi x8, x0, 10
addi x9, x0, 20
bne x8, x9, skip3     # 10 != 20 → taken
addi x8, x0, 99       # flushed
skip3:
sw x8, 40(x0)         # mem[40] = 10

# Done — infinite loop
done:
beq x0, x0, done
