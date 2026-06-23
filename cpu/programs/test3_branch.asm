# test3_branch.asm -- beq, blt, bge, bltu, bgeu
# Data: [0x80]=5, [0x84]=10, [0x88]=5, [0x8C]=10
lw x1, 128(x0)
lw x2, 132(x0)
lw x3, 136(x0)
lw x4, 140(x0)
# beq taken (x1==x3, both 5)
beq x1, x3, b1
sw x0, 144(x0)
b1:
sw x1, 148(x0)
# blt taken (x1<x2: 5<10)
blt x1, x2, b2
sw x0, 152(x0)
b2:
sw x1, 156(x0)
# bge taken (x4>=x1: 10>=5)
bge x4, x1, b3
sw x0, 160(x0)
b3:
sw x1, 164(x0)
# bltu taken (5<10 unsigned)
bltu x1, x2, b4
sw x0, 168(x0)
b4:
sw x1, 172(x0)
# bgeu taken (10>=5 unsigned)
bgeu x4, x1, b5
sw x0, 176(x0)
b5:
sw x1, 180(x0)
# beq NOT taken (x1!=x2)
beq x1, x2, b6
sw x2, 184(x0)
b6:
sw x0, 188(x0)
