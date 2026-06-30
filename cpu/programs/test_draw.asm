# test_draw.asm — draw pixels using shift+add (no M-extension mul/div)
.equ FB_BASE, 0x40002000
.equ SCREEN_W, 80
.equ YELLOW, 0xFC
.equ WHITE, 0xFF
.equ GREEN, 0x1C

_start:
    # Draw YELLOW at (20, 10)
    li   t0, FB_BASE
    li   t1, 10                 # y = 10
    slli t2, t1, 6              # y * 64
    slli t1, t1, 4              # y * 16
    add  t1, t2, t1             # y * 80
    addi t1, t1, 20             # + x = 20
    add  t0, t0, t1
    li   t2, YELLOW
    sb   t2, 0(t0)

    # Draw GREEN at (10, 10)
    li   t0, FB_BASE
    li   t1, 10
    slli t2, t1, 6
    slli t1, t1, 4
    add  t1, t2, t1
    addi t1, t1, 10
    add  t0, t0, t1
    li   t2, GREEN
    sb   t2, 0(t0)

    # Draw WHITE at (15, 15)
    li   t0, FB_BASE
    li   t1, 15
    slli t2, t1, 6
    slli t1, t1, 4
    add  t1, t2, t1
    addi t1, t1, 15
    add  t0, t0, t1
    li   t2, WHITE
    sb   t2, 0(t0)

1:  j 1b
