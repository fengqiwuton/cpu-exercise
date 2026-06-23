# test1_alu.asm -- add, sub, and, or
# Data memory preload: [0]=10, [4]=3
lw x1, 0(x0)
lw x2, 4(x0)
add x3, x1, x2
sub x4, x1, x2
and x5, x1, x2
or  x6, x1, x2
sw x3, 8(x0)
sw x4, 12(x0)
sw x5, 16(x0)
sw x6, 20(x0)
