# test2_mem.asm -- load/store verification
# Data: [0x40]=0xDEADBEEF, [0x44]=0xCAFE1234
lw x1, 64(x0)
lw x2, 68(x0)
sw x1, 80(x0)
sw x2, 84(x0)
lw x3, 80(x0)
lw x4, 84(x0)
sub x5, x1, x3
sub x6, x2, x4
sw x5, 88(x0)
sw x6, 92(x0)
