# test5_rv32i.asm -- full RV32I test (new instructions)
# Data: [0x08]=0xAB, [0x0C]=0x12345678 (for lb/lh tests)

# === addi ===
addi x1, x0, 5
addi x2, x1, 7
sw x2, 16(x0)

# === slti / sltiu ===
addi x3, x0, 10
slti x4, x3, 20
sw x4, 20(x0)
slti x4, x3, 5
sw x4, 24(x0)
sltiu x4, x3, 20
sw x4, 28(x0)

# === xori / ori / andi ===
xori x5, x3, 0xFF
sw x5, 32(x0)
ori x5, x3, 0xF0
sw x5, 36(x0)
andi x5, x3, 0xF
sw x5, 40(x0)

# === slli / srli / srai ===
addi x6, x0, 1
slli x7, x6, 4
sw x7, 44(x0)
addi x6, x0, -256
srai x7, x6, 2
sw x7, 48(x0)
addi x6, x0, 256
srli x7, x6, 4
sw x7, 52(x0)

# === xor / slt / sltu / sll / srl ===
addi x1, x0, 5
addi x2, x0, 10
slt x8, x1, x2
sw x8, 56(x0)
sltu x8, x2, x1
sw x8, 60(x0)
xor x8, x1, x2
sw x8, 64(x0)
sll x8, x1, x2
sw x8, 68(x0)
srl x8, x2, x1
sw x8, 72(x0)

# === lui ===
lui x9, 0x12345
sw x9, 76(x0)

# === bne (taken) ===
addi x10, x0, 5
addi x11, x0, 10
bne x10, x11, bne_ok
sw x0, 80(x0)
bne_ok:
sw x10, 84(x0)

# === bne (not taken) ===
bne x10, x10, bne_fail
sw x11, 88(x0)
bne_fail:
sw x0, 92(x0)

# === lb / lbu (byte load, sign/zero extend) ===
lw x12, 8(x0)
lb x13, 8(x0)
sw x13, 96(x0)
lbu x14, 8(x0)
sw x14, 100(x0)

# === lh / lhu (half-word load) ===
lw x15, 12(x0)
lh x16, 12(x0)
sw x16, 104(x0)
lhu x17, 12(x0)
sw x17, 108(x0)

# === sb (store byte) ===
addi x18, x0, 0x42
sb x18, 112(x0)
lb x19, 112(x0)
sw x19, 116(x0)

# === sh (store half) ===
addi x20, x0, 0x7AB
sh x20, 120(x0)
lhu x21, 120(x0)
sw x21, 124(x0)

# === jal (jump and link) ===
jal x1, func
sw x22, 128(x0)
end:
beq x0, x0, end

func:
addi x22, x0, 0x42
jalr x0, x1, 0
