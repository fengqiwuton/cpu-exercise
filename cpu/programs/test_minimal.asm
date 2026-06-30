# Step 2: yield + 2 tasks (moving dots)
.equ TCB_A,         0x1000
.equ TCB_A_STACK,   0x1040
.equ TCB_B,         0x1180
.equ TCB_B_STACK,   0x11C0
.equ CUR_TASK,      0x1300
.equ DOT_X,         0x1304
.equ DOT_Y,         0x1308
.equ DOT_DX,        0x130C
.equ DOT_DY,        0x1310
.equ FB_BASE,       0x40002000
.equ SCREEN_W,      80
.equ SCREEN_H,      60
.equ BLACK,         0x00
.equ WHITE,         0xFF
.equ GREEN,         0x1C
.equ YELLOW,        0xFC
.equ RED,           0xE0
_start:
# Clear + border + divider (same as step 1)
li   t3, 0
_s0:li   t4, 30
bge t3, t4, _s0d
mv   t0, t3
slli t1, t0, 6
slli t0, t0, 4
add t0, t1, t0
li   t1, FB_BASE
add t0, t1, t0
li t1, 40
li t2, BLACK
_s1:addi t1, t1, -1
sb t2, 0(t0)
addi t0, t0, 1
bnez t1, _s1
addi t3, t3, 1
j _s0
_s0d:
li   t0, FB_BASE
li t2, WHITE
li t1, SCREEN_W
_s2:addi t1, t1, -1
sb t2, 0(t0)
addi t0, t0, 1
bnez t1, _s2
li   t0, FB_BASE
li t1, 4720
add t0, t0, t1
li t1, SCREEN_W
_s3:addi t1, t1, -1
sb t2, 0(t0)
addi t0, t0, 1
bnez t1, _s3
li   t3, 1
_s4:li   t4, 59
bge t3, t4, _s5
mv   t0, t3
slli t1, t0, 6
slli t0, t0, 4
add t0, t1, t0
li   t1, FB_BASE
add t0, t1, t0
sb t2, 0(t0)
sb t2, 79(t0)
addi t3, t3, 1
j _s4
_s5:li   t0, FB_BASE
li t1, 1600
add t0, t0, t1
li t1, SCREEN_W
_s6:addi t1, t1, -1
sb t2, 0(t0)
addi t0, t0, 1
bnez t1, _s6
# Init dot state
li   t0, DOT_X
li t1, 5
sw t1, 0(t0)
sw t1, 8(t0)
sw t1, 12(t0)
li   t1, 10
sw t1, 4(t0)
# Init TCB A → task_green
li   t0, TCB_A_STACK
addi t0, t0, 252
_k1:addi t0, t0, -4
sw zero, 0(t0)
li t1, 12
_k2:addi t1, t1, -1
addi t0, t0, -4
sw zero, 0(t0)
bnez t1, _k2
li   t1, TCB_A
sw t0, 0(t1)
la   t1, task_green
li t2, TCB_A
sw t1, 4(t2)
# Init TCB B → task_yellow
li   t0, TCB_B_STACK
addi t0, t0, 252
_k3:addi t0, t0, -4
sw zero, 0(t0)
li t1, 12
_k4:addi t1, t1, -1
addi t0, t0, -4
sw zero, 0(t0)
bnez t1, _k4
li   t1, TCB_B
sw t0, 0(t1)
la   t1, task_yellow
li t2, TCB_B
sw t1, 4(t2)
li   t0, TCB_A
li t1, CUR_TASK
sw t0, 0(t1)
# RED at (15,14)
li   t0, FB_BASE
li t1, 1214
add t0, t0, t1
li t2, RED
sb t2, 0(t0)
# GREEN at (15,15)
li   t0, FB_BASE
li t1, 1215
add t0, t0, t1
li t2, GREEN
sb t2, 0(t0)
jal  ra, scheduler_start
_mx:j   _mx
# ═══════════════ scheduler_start ═══════════════
scheduler_start:
li   t0, FB_BASE
li t1, 1216
add t0, t0, t1
li t2, WHITE
sb t2, 0(t0)
li   t0, CUR_TASK
lw t0, 0(t0)
lw sp, 0(t0)
lw ra, 4(t0)
ret
# ═══════════════ yield ═══════════════
yield:
li   t0, CUR_TASK
lw t0, 0(t0)
sw   sp, 0(t0)
sw ra, 4(t0)
sw s0, 8(t0)
sw s1, 12(t0)
sw   s2, 16(t0)
sw s3, 20(t0)
sw s4, 24(t0)
sw s5, 28(t0)
sw   s6, 32(t0)
sw s7, 36(t0)
sw s8, 40(t0)
sw s9, 44(t0)
sw   s10,48(t0)
sw s11,52(t0)
li   t0, CUR_TASK
lw t1, 0(t0)
li t2, TCB_A
bne  t1, t2, _ya
li t2, TCB_B
sw t2, 0(t0)
j _yr
_ya:sw   t2, 0(t0)
_yr:lw   sp, 0(t2)
lw ra, 4(t2)
lw s0, 8(t2)
lw s1, 12(t2)
lw   s2, 16(t2)
lw s3, 20(t2)
lw s4, 24(t2)
lw s5, 28(t2)
lw   s6, 32(t2)
lw s7, 36(t2)
lw s8, 40(t2)
lw s9, 44(t2)
lw   s10,48(t2)
lw s11,52(t2)
ret
# ═══════════════ draw_pixel ═══════════════
draw_pixel:
bltz a0, _dp1
li t0, SCREEN_W
bge a0, t0, _dp1
bltz a1, _dp1
li t0, SCREEN_H
bge a1, t0, _dp1
slli t0, a1, 6
slli t1, a1, 4
add t0, t0, t1
add t0, t0, a0
li   t1, FB_BASE
add t0, t1, t0
sb a2, 0(t0)
_dp1:ret
# ═══════════════ task_green ═══════════════
task_green:
# YELLOW at (15,17)
li   t0, FB_BASE
li t1, 1217
add t0, t0, t1
li t2, YELLOW
sb t2, 0(t0)
li   s0, DOT_X
li s1, DOT_Y
li s2, DOT_DX
li s3, DOT_DY
li s4, GREEN
li s5, BLACK
_gloop:
lw   a0, 0(s0)
lw a1, 0(s1)
mv a2, s5
jal  ra, draw_pixel
lw   t0, 0(s0)
lw t1, 0(s2)
add t0, t0, t1
sw t0, 0(s0)
lw   t2, 0(s1)
lw t3, 0(s3)
add t2, t2, t3
sw t2, 0(s1)
li   t4, 38
ble t0, t4, _g1
li t1, -1
sw t1, 0(s2)
li t0, 38
sw t0, 0(s0)
j _g2
_g1:li   t4, 1
bge t0, t4, _g2
li t1, 1
sw t1, 0(s2)
li t0, 1
sw t0, 0(s0)
_g2:li   t4, 19
ble t2, t4, _g3
li t3, -1
sw t3, 0(s3)
li t2, 19
sw t2, 0(s1)
j _g4
_g3:li   t4, 1
bge t2, t4, _g4
li t3, 1
sw t3, 0(s3)
li t2, 1
sw t2, 0(s1)
_g4:lw   a0, 0(s0)
lw a1, 0(s1)
mv a2, s4
jal  ra, draw_pixel
li   t0, 1500
_g5:addi t0, t0, -1
bnez t0, _g5
jal  ra, yield
j _gloop
# ═══════════════ task_yellow ═══════════════
task_yellow:
# dot at (20,25) going left+up
li   s0, DOT_X
addi s0, s0, 16
li   s1, DOT_Y
addi s1, s1, 16
li   s2, DOT_DX
addi s2, s2, 16
li   s3, DOT_DY
addi s3, s3, 16
li   s4, YELLOW
li s5, BLACK
li   t0, 30
sw t0, 0(s0)
li t0, 25
sw t0, 0(s1)
li   t0, -1
sw t0, 0(s2)
sw t0, 0(s3)
_yloop:
lw   a0, 0(s0)
lw a1, 0(s1)
mv a2, s5
jal  ra, draw_pixel
lw   t0, 0(s0)
lw t1, 0(s2)
add t0, t0, t1
sw t0, 0(s0)
lw   t2, 0(s1)
lw t3, 0(s3)
add t2, t2, t3
sw t2, 0(s1)
li   t4, 38
ble t0, t4, _y1
li t1, -1
sw t1, 0(s2)
li t0, 38
sw t0, 0(s0)
j _y2
_y1:li   t4, 1
bge t0, t4, _y2
li t1, 1
sw t1, 0(s2)
li t0, 1
sw t0, 0(s0)
_y2:li   t4, 28
ble t2, t4, _y3
li t3, -1
sw t3, 0(s3)
li t2, 28
sw t2, 0(s1)
j _y4
_y3:li   t4, 21
bge t2, t4, _y4
li t3, 1
sw t3, 0(s3)
li t2, 21
sw t2, 0(s1)
_y4:lw   a0, 0(s0)
lw a1, 0(s1)
mv a2, s4
jal  ra, draw_pixel
li   t0, 1500
_y5:addi t0, t0, -1
bnez t0, _y5
jal  ra, yield
j _yloop
