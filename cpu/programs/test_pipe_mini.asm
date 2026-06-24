# Minimal pipeline test: 3 independent instructions
addi x1, x0, 42        # x1 = 42
addi x2, x0, 99        # x2 = 99
sw x2, 16(x0)          # mem[16] = 99
sw x1, 20(x0)          # mem[20] = 42
done:
beq x0, x0, done
