# scheduler.asm — cooperative multitasking: counter(top) + snake(bottom)
.equ TCB_A,         0x1000
.equ TCB_A_STACK,   0x1040
.equ TCB_B,         0x1180
.equ TCB_B_STACK,   0x11C0
.equ CUR_TASK,      0x1300
.equ COUNTER_VAL,   0x1304
# Snake state (data memory 0x1400+)
.equ SNAKE_X,       0x1400
.equ SNAKE_Y,       0x1800
.equ SNAKE_LEN,     0x1C00
.equ SNAKE_DX,      0x1C04
.equ SNAKE_DY,      0x1C08
.equ FOOD_X,        0x1C0C
.equ FOOD_Y,        0x1C10
.equ SNAKE_RNG,     0x1C14
.equ SNAKE_OVER,    0x1C18
.equ SNAKE_SCORE,   0x1C1C
.equ UART_STATUS,   0x40000008
.equ UART_RX,       0x40000004
.equ UART_BAUD,     0x4000000C
.equ FB_BASE,       0x40002000
.equ SCREEN_W,      80
.equ SCREEN_H,      60
.equ BLACK,         0x00
.equ WHITE,         0xFF
.equ GREEN,         0x1C
.equ YELLOW,        0xFC
.equ RED,           0xE0
_start:
# Init UART
li   t0, UART_BAUD
li   t1, 20
sw   t1, 0(t0)
# Clear visible area (fast: 30 rows x 40 cols)
li   t3, 0
_s0:li   t4, 30
bge t3, t4, _s0d
mv   t0, t3
slli t1,t0,6
slli t0,t0,4
add t0,t1,t0
li   t1, FB_BASE
add t0,t1,t0
li t1,40
li t2,BLACK
_s1:addi t1,t1,-1
sb t2,0(t0)
addi t0,t0,1
bnez t1,_s1
addi t3,t3,1
j _s0
_s0d:
# Border
li   t0,FB_BASE
li t2,WHITE
li t1,SCREEN_W
_s2:addi t1,t1,-1
sb t2,0(t0)
addi t0,t0,1
bnez t1,_s2
li   t0,FB_BASE
li t1,4720
add t0,t0,t1
li t1,SCREEN_W
_s3:addi t1,t1,-1
sb t2,0(t0)
addi t0,t0,1
bnez t1,_s3
li   t3,1
_s4:li   t4,59
bge t3,t4,_s5
mv   t0,t3
slli t1,t0,6
slli t0,t0,4
add t0,t1,t0
li   t1,FB_BASE
add t0,t1,t0
sb t2,0(t0)
sb t2,79(t0)
addi t3,t3,1
j _s4
_s5:
    # Init counter
li   t0,COUNTER_VAL
sw zero,0(t0)
# Init snake
jal  ra,snake_init
# Init TCB A -> task_counter
li   t0,TCB_A_STACK
addi t0,t0,252
li   t1,12
_k1:addi t1,t1,-1
addi t0,t0,-4
sw zero,0(t0)
bnez t1,_k1
li   t1,TCB_A
sw t0,0(t1)
la   t1,task_counter
li t2,TCB_A
sw t1,4(t2)
# Init TCB B -> task_snake
li   t0,TCB_B_STACK
addi t0,t0,252
li   t1,12
_k2:addi t1,t1,-1
addi t0,t0,-4
sw zero,0(t0)
bnez t1,_k2
li   t1,TCB_B
sw t0,0(t1)
la   t1,task_snake
li t2,TCB_B
sw t1,4(t2)
li   t0,TCB_A
li t1,CUR_TASK
sw t0,0(t1)
jal  ra,scheduler_start
_mx:j   _mx
# ═══════════════ snake_init ═════════════════════
snake_init:
li   t0,SNAKE_LEN
li t1,5
sw t1,0(t0)
li   t1,1
sw t1,4(t0)
sw zero,8(t0)
sw   zero,20(t0)
sw zero,24(t0)
li   t1,12345
sw t1,16(t0)
# Body: (10..6, 30)
li   t2,5
li t3,10
li t4,35
_si1:addi t2,t2,-1
slli t5,t2,2
li   t6,SNAKE_X
add  t5,t6,t5
sub  t6,t3,t2
sw   t6,0(t5)
slli t5,t2,2
li   t6,SNAKE_Y
add  t5,t6,t5
sw   t4,0(t5)
bnez t2,_si1
# Food at (20,25)
li   t0,FOOD_X
li   t1,20
sw   t1,0(t0)
li   t1,35
sw   t1,4(t0)
ret
# ═══════════════ scheduler_start ═════════════════
scheduler_start:
li   t0,CUR_TASK
lw t0,0(t0)
lw sp,0(t0)
lw ra,4(t0)
ret
# ═══════════════ yield ══════════════════════════
yield:
li   t0,CUR_TASK
lw t0,0(t0)
sw   sp,0(t0)
sw ra,4(t0)
sw s0,8(t0)
sw s1,12(t0)
sw   s2,16(t0)
sw s3,20(t0)
sw s4,24(t0)
sw s5,28(t0)
sw   s6,32(t0)
sw s7,36(t0)
sw s8,40(t0)
sw s9,44(t0)
sw   s10,48(t0)
sw s11,52(t0)
li   t0,CUR_TASK
lw t1,0(t0)
li t2,TCB_A
bne  t1,t2,_ya
li t2,TCB_B
sw t2,0(t0)
j _yr
_ya:sw   t2,0(t0)
_yr:lw   sp,0(t2)
lw ra,4(t2)
lw s0,8(t2)
lw s1,12(t2)
lw   s2,16(t2)
lw s3,20(t2)
lw s4,24(t2)
lw s5,28(t2)
lw   s6,32(t2)
lw s7,36(t2)
lw s8,40(t2)
lw s9,44(t2)
lw   s10,48(t2)
lw s11,52(t2)
ret
# ═══════════════ draw_pixel ════════════════════
draw_pixel:
bltz a0,_dp1
li t0,SCREEN_W
bge a0,t0,_dp1
bltz a1,_dp1
li t0,SCREEN_H
bge a1,t0,_dp1
slli t0,a1,6
slli t1,a1,4
add t0,t0,t1
add t0,t0,a0
li   t1,FB_BASE
add t0,t1,t0
sb a2,0(t0)
_dp1:ret
# ═══════════════ uart_kbhit ════════════════════
uart_kbhit:
li   t0,UART_STATUS
lw t0,0(t0)
andi a0,t0,2
srli a0,a0,1
ret
# ═══════════════ uart_getc ════════════════════
uart_getc:
li   t0,UART_STATUS
_ug1:lw   t1,0(t0)
andi t1,t1,2
beqz t1,_ug1
li   t0,UART_RX
lw a0,0(t0)
andi a0,a0,0xFF
ret
# ═══════════════ rand ══════════════════════════
rand:
li   t0,SNAKE_RNG
lw a0,0(t0)
slli t1,a0,13
xor a0,a0,t1
srli t1,a0,17
xor a0,a0,t1
slli t1,a0,5
xor a0,a0,t1
sw a0,0(t0)
ret
# ═══════════════ TASK A: blink dot ═══════════════
task_counter:
li   s0,COUNTER_VAL
li   s1,GREEN
li   s2,YELLOW
_bloop:
lw   t0,0(s0)
addi t0,t0,1
sw   t0,0(s0)
andi t0,t0,1
bnez t0,_byel
li   a0,2
li   a1,2
mv   a2,s1
jal  ra,draw_pixel
j    _bdly
_byel:
li   a0,2
li   a1,2
mv   a2,s2
jal  ra,draw_pixel
_bdly:
li   t0,3000
_bd2:addi t0,t0,-1
bnez t0,_bd2
jal  ra,yield
j    _bloop
# ═══════════════ TASK B: SNAKE ═════════════════
task_snake:
li   s0,SNAKE_X
li s1,SNAKE_Y
li s2,SNAKE_LEN
li   s3,SNAKE_DX
li s4,SNAKE_DY
li s5,FOOD_X
li s6,FOOD_Y
_sloop:
li   t0,SNAKE_OVER
lw t0,0(t0)
bnez t0,_sdead
# Clear old trail
lw   t0,0(s2)
li t1,0
_sclr:bge  t1,t0,_scdone
slli t2,t1,2
add  t2,s0,t2
lw   a0,0(t2)
slli t2,t1,2
add  t2,s1,t2
lw   a1,0(t2)
li a2,BLACK
addi sp,sp,-16
sw ra,0(sp)
sw t0,4(sp)
sw t1,8(sp)
jal  ra,draw_pixel
lw ra,0(sp)
lw t0,4(sp)
lw t1,8(sp)
addi sp,sp,16
addi t1,t1,1
j _sclr
_scdone:
# Input
jal  ra,uart_kbhit
beqz a0,_snone
jal  ra,uart_getc
li   t0,119
bne a0,t0,_scs
lw t0,8(s2)
li t1,1
beq t0,t1,_snone
sw   zero,4(s2)
li t1,-1
sw t1,8(s2)
j _snone
_scs:li   t0,115
bne a0,t0,_sca
lw t0,8(s2)
li t1,-1
beq t0,t1,_snone
sw   zero,4(s2)
li t1,1
sw t1,8(s2)
j _snone
_sca:li   t0,97
bne a0,t0,_scd
lw t0,4(s2)
li t1,1
beq t0,t1,_snone
li   t1,-1
sw t1,4(s2)
sw zero,8(s2)
j _snone
_scd:li   t0,100
bne a0,t0,_snone
lw t0,4(s2)
li t1,-1
beq t0,t1,_snone
li   t1,1
sw t1,4(s2)
sw zero,8(s2)
_snone:
# New head
lw   t0,0(s0)
lw t1,4(s2)
add t2,t0,t1
lw   t0,0(s1)
lw t1,8(s2)
add t3,t0,t1
# Wall
bltz t2,_sdead
li t0,80
bge t2,t0,_sdead
bltz t3,_sdead
li t0,60
bge t3,t0,_sdead
# Self
lw   t0,0(s2)
li t4,1
_sself:bge  t4,t0,_ssdone
slli t5,t4,2
add  t5,s0,t5
lw   t6,0(t5)
bne  t6,t2,_ssnxt
slli t5,t4,2
add  t5,s1,t5
lw   t6,0(t5)
beq  t6,t3,_sdead
_ssnxt:addi t4,t4,1
j _sself
_ssdone:
# Food?
lw   t4,0(s5)
lw t5,0(s6)
bne t2,t4,_snof
bne t3,t5,_snof
lw   t0,0(s2)
li t1,200
bge t0,t1,_snog
addi t0,t0,1
sw t0,0(s2)
_snog:li   t0,SNAKE_SCORE
lw t1,0(t0)
addi t1,t1,10
sw t1,0(t0)
# New food
jal  ra,rand
mv t0,a0
li t1,68
_sfx:blt  t0,t1,_sfxd
sub t0,t0,t1
j _sfx
_sfxd:addi t0,t0,5
sw t0,0(s5)
jal  ra,rand
mv t0,a0
li t1,48
_sfy:blt  t0,t1,_sfyd
sub t0,t0,t1
j _sfy
_sfyd:addi t0,t0,5
sw t0,0(s6)
_snof:
# Shift body
lw   t0,0(s2)
addi t0,t0,-1
_ssft:bltz t0,_ssfd
slli t4,t0,2
add  t5,s0,t4
lw t6,-4(t5)
sw t6,0(t5)
add  t5,s1,t4
lw t6,-4(t5)
sw t6,0(t5)
addi t0,t0,-1
j _ssft
_ssfd:sw   t2,0(s0)
sw t3,0(s1)
# Draw food
lw   a0,0(s5)
lw a1,0(s6)
li a2,RED
jal ra,draw_pixel
# Draw snake
lw   t0,0(s2)
li t1,0
_sdrw:bge  t1,t0,_sdrd
slli t2,t1,2
add  t2,s0,t2
lw   a0,0(t2)
slli t2,t1,2
add  t2,s1,t2
lw   a1,0(t2)
beqz t1,_shead
li a2,GREEN
j _sdpx
_shead:li   a2,YELLOW
_sdpx:addi sp,sp,-16
sw ra,0(sp)
sw t0,4(sp)
sw t1,8(sp)
jal  ra,draw_pixel
lw ra,0(sp)
lw t0,4(sp)
lw t1,8(sp)
addi sp,sp,16
addi t1,t1,1
j _sdrw
_sdrd:
li   t0,8000
_sdly:addi t0,t0,-1
bnez t0,_sdly
jal ra,yield
j _sloop
_sdead:
li   t0,SNAKE_OVER
li t1,1
sw t1,0(t0)
_sdd:jal  ra,yield
j _sdd