# test4_integration.asm -- sum 1+2+3+4+5 = 15
# Data: [0x100]=1, [0x104]=2, [0x108]=3, [0x10C]=4, [0x110]=5, [0x124]=15
lw x1, 256(x0)
lw x2, 260(x0)
add x3, x1, x2
lw x4, 264(x0)
add x3, x3, x4
lw x4, 268(x0)
add x3, x3, x4
lw x4, 272(x0)
add x3, x3, x4
sw x3, 288(x0)
# verify sum == 15
lw x5, 292(x0)
sub x6, x3, x5
beq x6, x0, pass
sw x0, 296(x0)
pass:
sw x3, 304(x0)
