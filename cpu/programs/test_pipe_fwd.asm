# test_pipe_fwd.asm — targeted forwarding tests
# Data: [0]=10, [4]=3

# === Test A: RAW forwarding through registers ===
# addi x1,x0,10; addi x2,x1,5; addi x3,x2,3
# x1=10, x2=15, x3=18 (no loads, pure forwarding)
addi x1, x0, 10
addi x2, x1, 5
addi x3, x2, 3
sw x3, 16(x0)          # mem[16] = 18

# === Test B: Load-use stall ===
# lw x4,0(x0) ; addi x5,x4,7 → needs 1 stall cycle
lw x4, 0(x0)           # x4 = 10
addi x5, x4, 7         # x5 = 17 (load-use stall)
sw x5, 20(x0)          # mem[20] = 17

# === Test C: Store after computation (store forwarding) ===
addi x6, x0, 42
sw x6, 24(x0)          # mem[24] = 42

# === Test D: Double load + dependent add ===
lw x7, 0(x0)           # x7 = 10
lw x8, 4(x0)           # x8 = 3
add x9, x7, x8         # x9 = 13 (needs double forwarding)
sw x9, 28(x0)          # mem[28] = 13

done:
beq x0, x0, done
