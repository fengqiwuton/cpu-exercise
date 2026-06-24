# test7 — verify all 4 byte positions
lui x10, 0x40000
addi x11, x0, 2
sw x11, 12(x10)

addi x12, x0, 87
sb x12, 0(x0)
addi x12, x0, 88
sb x12, 1(x0)
addi x12, x0, 89
sb x12, 2(x0)
addi x12, x0, 90
sb x12, 3(x0)

lb x15, 0(x0)
tx0:
lw x16, 8(x10)
andi x16, x16, 1
bne x16, x0, tx0
sw x15, 0(x10)

lb x15, 1(x0)
tx1:
lw x16, 8(x10)
andi x16, x16, 1
bne x16, x0, tx1
sw x15, 0(x10)

lb x15, 2(x0)
tx2:
lw x16, 8(x10)
andi x16, x16, 1
bne x16, x0, tx2
sw x15, 0(x10)

lb x15, 3(x0)
tx3:
lw x16, 8(x10)
andi x16, x16, 1
bne x16, x0, tx3
sw x15, 0(x10)

beq x0, x0, tx3
