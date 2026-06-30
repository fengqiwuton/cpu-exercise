# scheduler.asm — Cooperative multitasking: counter (top) + snake (bottom)
# Snake plays in rows 1-58, cols 1-78. Divider at row 20 separates counter area.
# All labels globally unique. No M-extension. UART for keyboard input.

# ── MMIO ─────────────────────────────────────────────────────
.equ UART_STATUS,   0x40000008
.equ UART_RX,       0x40000004
.equ UART_BAUD,     0x4000000C
.equ FB_BASE,       0x40002000

# ── Screen ───────────────────────────────────────────────────
.equ SCREEN_W,      80
.equ SCREEN_H,      60
.equ BLACK,         0x00
.equ WHITE,         0xFF
.equ GREEN,         0x1C
.equ YELLOW,        0xFC
.equ RED,           0xE0

# ── Data memory layout ───────────────────────────────────────
.equ TCB_A,         0x1000       # 56B header
.equ TCB_A_STACK,   0x1040       # 256B stack → ends at 0x1140
.equ TCB_B,         0x1180       # 56B header (no overlap!)
.equ TCB_B_STACK,   0x11C0       # 256B stack → ends at 0x12C0
.equ CUR_TASK,      0x1300
.equ COUNTER_VAL,   0x1304

# Snake state (in data memory)
.equ SNAKE_X,       0x1400       # 200 words for x coords → ends at 0x171C
.equ SNAKE_Y,       0x1800       # 200 words for y coords → ends at 0x1B1C
.equ SNAKE_LEN,     0x1C00
.equ SNAKE_DX,      0x1C04
.equ SNAKE_DY,      0x1C08
.equ FOOD_X,        0x1C0C
.equ FOOD_Y,        0x1C10
.equ SNAKE_RNG,     0x1C14
.equ SNAKE_OVER,    0x1C18
.equ SNAKE_SCORE,   0x1C1C
.equ MAX_LEN,       200

# ═══════════════════════ _start ═══════════════════════
_start:
    # Init UART baud rate
    li   t0, UART_BAUD
    li   t1, 20
    sw   t1, 0(t0)

    # Clear visible area (40 cols × 30 rows = 1200 px, fast)
    li   t3, 0
_s0:li   t4, 30
    bge  t3, t4, _s0d
    mv   t0, t3
    slli t1, t0, 6
    slli t0, t0, 4
    add  t0, t1, t0
    li   t1, FB_BASE
    add  t0, t1, t0
    li   t1, 40
    li   t2, BLACK
_s1:addi t1, t1, -1
    sb   t2, 0(t0)
    addi t0, t0, 1
    bnez t1, _s1
    addi t3, t3, 1
    j    _s0
_s0d:

    # Draw border
    li   t0, FB_BASE
    li   t2, WHITE
    li   t1, SCREEN_W
_s2:addi t1, t1, -1
    sb   t2, 0(t0)
    addi t0, t0, 1
    bnez t1, _s2
    li   t0, FB_BASE
    li   t1, 4720
    add  t0, t0, t1
    li   t1, SCREEN_W
_s3:addi t1, t1, -1
    sb   t2, 0(t0)
    addi t0, t0, 1
    bnez t1, _s3
    li   t3, 1
_s4:li   t4, 59
    bge  t3, t4, _s5
    mv   t0, t3
    slli t1, t0, 6
    slli t0, t0, 4
    add  t0, t1, t0
    li   t1, FB_BASE
    add  t0, t1, t0
    sb   t2, 0(t0)
    sb   t2, 79(t0)
    addi t3, t3, 1
    j    _s4

    # Divider at row 20
_s5:li   t0, FB_BASE
    li   t1, 1600
    add  t0, t0, t1
    li   t1, SCREEN_W
_s6:addi t1, t1, -1
    sb   t2, 0(t0)
    addi t0, t0, 1
    bnez t1, _s6

    # Init counter
    li   t0, COUNTER_VAL
    sw   zero, 0(t0)

    # Init snake state
    jal  ra, snake_init

    # Init tasks
    li   a0, TCB_A
    la   a1, task_counter
    li   a2, TCB_A_STACK
    addi a2, a2, 252
    jal  ra, task_init
    li   a0, TCB_B
    la   a1, task_snake
    li   a2, TCB_B_STACK
    addi a2, a2, 252
    jal  ra, task_init

    li   t0, TCB_A
    li   t1, CUR_TASK
    sw   t0, 0(t1)
    jal  ra, scheduler_start
_s7:j    _s7

# ═══════════════════ snake_init ═════════════════════
snake_init:
    # DEBUG: draw RED at (15,15) to confirm init runs
    li   a0, 15
    li   a1, 15
    li   a2, RED
    jal  ra, draw_pixel

    li   t0, SNAKE_LEN
    li   t1, 5
    sw   t1, 0(t0)              # len = 5
    li   t1, 1
    sw   t1, 4(t0)              # dx = 1
    sw   zero, 8(t0)            # dy = 0
    sw   zero, 20(t0)           # score = 0
    sw   zero, 24(t0)           # over = 0
    li   t1, 12345
    sw   t1, 16(t0)             # rng = 12345

    # Snake body: starts horizontally at (10..6, 30)
    li   t0, SNAKE_X
    li   t1, SNAKE_Y
    li   t2, 5                  # i = 5
    li   t3, 10                 # start x
    li   t4, 15                 # y = 15 (visible in BMP)
_si1:addi t2, t2, -1
    slli t5, t2, 2
    add  t5, t0, t5
    sub  t6, t3, t2            # x = 10 - i
    sw   t6, 0(t5)
    add  t5, t1, t5
    sw   t4, 0(t5)
    bnez t2, _si1

    # Food at (20, 25)
    li   t0, FOOD_X
    li   t1, 20
    sw   t1, 0(t0)
    li   t1, 25
    sw   t1, 4(t0)
    ret

# ═══════════════════ helper: rand15 ══════════════════
# Returns pseudo-random 15-bit value in a0
rand15:
    li   t0, SNAKE_RNG
    lw   a0, 0(t0)
    li   t1, 1103515245
    # a0 = rng * 1103515245 + 12345
    # Multiply by shift+add (no M-extension!)
    # rng * 1103515245 = rng * (2^30 + 2^25 + 2^20 + ...)
    # Simpler: use LCG with smaller multiplier
    # rng = rng * 1664525 + 1013904223  ( Numerical Recipes LCG)
    # Even simpler: use xorshift
    # s0 = rng
    mv   s0, a0
    slli t1, s0, 13
    xor  a0, a0, t1
    srli t1, a0, 17
    xor  a0, a0, t1
    slli t1, a0, 5
    xor  a0, a0, t1
    sw   a0, 0(t0)              # save new rng
    # Return only bits for food position
    ret

# ═══════════════════ draw_pixel ═════════════════════
draw_pixel:
    bltz a0, _dp1
    li   t0, SCREEN_W
    bge  a0, t0, _dp1
    bltz a1, _dp1
    li   t0, SCREEN_H
    bge  a1, t0, _dp1
    slli t0, a1, 6
    slli t1, a1, 4
    add  t0, t0, t1
    add  t0, t0, a0
    li   t1, FB_BASE
    add  t0, t1, t0
    sb   a2, 0(t0)
_dp1:ret

# ═══════════════════ task_init ══════════════════════
task_init:
    li   t0, 12
_t1:addi a2, a2, -4
    sw   zero, 0(a2)
    addi t0, t0, -1
    bnez t0, _t1
    sw   a2, 0(a0)
    sw   a1, 4(a0)
    ret

# ═════════════════ scheduler_start ═══════════════════
scheduler_start:
    li   t0, CUR_TASK
    lw   t0, 0(t0)
    # DEBUG: write WHITE directly to fb, no function call
    li   t1, FB_BASE
    li   t2, 1217               # 15*80 + 17 = 1217
    add  t1, t1, t2
    li   t2, WHITE
    sb   t2, 0(t1)
    # Continue
    lw   sp, 0(t0)
    lw   ra, 4(t0)
    lw   s0, 8(t0)
    lw   s1, 12(t0)
    lw   s2, 16(t0)
    lw   s3, 20(t0)
    lw   s4, 24(t0)
    lw   s5, 28(t0)
    lw   s6, 32(t0)
    lw   s7, 36(t0)
    lw   s8, 40(t0)
    lw   s9, 44(t0)
    lw   s10,48(t0)
    lw   s11,52(t0)
    ret

# ═══════════════════ yield ═════════════════════════
.globl yield
yield:
    li   t0, CUR_TASK
    lw   t0, 0(t0)
    sw   sp, 0(t0)
    sw   ra, 4(t0)
    sw   s0, 8(t0)
    sw   s1, 12(t0)
    sw   s2, 16(t0)
    sw   s3, 20(t0)
    sw   s4, 24(t0)
    sw   s5, 28(t0)
    sw   s6, 32(t0)
    sw   s7, 36(t0)
    sw   s8, 40(t0)
    sw   s9, 44(t0)
    sw   s10,48(t0)
    sw   s11,52(t0)
    li   t0, CUR_TASK
    lw   t1, 0(t0)
    li   t2, TCB_A
    bne  t1, t2, _ytoa
_ytob:
    li   t2, TCB_B
    sw   t2, 0(t0)
    j    _yrest
_ytoa:
    sw   t2, 0(t0)
_yrest:
    lw   sp, 0(t2)
    lw   ra, 4(t2)
    lw   s0, 8(t2)
    lw   s1, 12(t2)
    lw   s2, 16(t2)
    lw   s3, 20(t2)
    lw   s4, 24(t2)
    lw   s5, 28(t2)
    lw   s6, 32(t2)
    lw   s7, 36(t2)
    lw   s8, 40(t2)
    lw   s9, 44(t2)
    lw   s10,48(t2)
    lw   s11,52(t2)
    ret

# ═══════════════════ uart_kbhit ════════════════════
# Returns 1 in a0 if key available, 0 otherwise
uart_kbhit:
    li   t0, UART_STATUS
    lw   t0, 0(t0)
    andi a0, t0, 2
    srli a0, a0, 1
    ret

# ═══════════════════ uart_getc ═════════════════════
# Returns byte in a0 (blocks until available)
uart_getc:
    li   t0, UART_STATUS
_ug1:lw   t1, 0(t0)
    andi t1, t1, 2
    beqz t1, _ug1
    li   t0, UART_RX
    lw   a0, 0(t0)
    andi a0, a0, 0xFF
    ret

# ═══════════════════ TASK A: Counter ═══════════════
task_counter:
    # DEBUG: draw GREEN at (14,15) to confirm counter runs
    li   a0, 14
    li   a1, 15
    li   a2, GREEN
    jal  ra, draw_pixel

    li   s0, COUNTER_VAL
    li   s1, GREEN
    li   s2, BLACK

_clock:
    # Display counter as a growing bar in top area
    lw   t0, 0(s0)
    addi t0, t0, 1
    li   t1, 60
    blt  t0, t1, _cc1
    li   t0, 0
_cc1:sw   t0, 0(s0)

    # Draw bar at row 2: fill t0 pixels green
    li   a1, 2                  # y = 2
    li   t2, 0                  # i = 0
_cc2:bge  t2, t0, _cc3
    mv   a0, t2
    addi a0, a0, 5              # x = 5 + i
    mv   a2, s1
    jal  ra, draw_pixel
    addi t2, t2, 1
    j    _cc2
    # Clear rest of bar
_cc3:li   t3, 60
_cc4:bge  t2, t3, _cc5
    mv   a0, t2
    addi a0, a0, 5
    mv   a2, s2
    jal  ra, draw_pixel
    addi t2, t2, 1
    j    _cc4
_cc5:
    li   t0, 2000
_cc6:addi t0, t0, -1
    bnez t0, _cc6
    jal  ra, yield
    j    _clock

# ═══════════════════ TASK B: Snake ══════════════════
task_snake:
    # DEBUG: draw YELLOW at (16,15) to confirm task entry
    li   a0, 16
    li   a1, 15
    li   a2, YELLOW
    jal  ra, draw_pixel

    li   s0, SNAKE_X
    li   s1, SNAKE_Y
    li   s2, SNAKE_LEN
    li   s3, FOOD_X
    li   s4, FOOD_Y
    li   s5, SNAKE_DX
    li   s6, SNAKE_DY

_snk_loop:
    # ── Check game over ──────────────────────────────
    li   t0, SNAKE_OVER
    lw   t0, 0(t0)
    bnez t0, _snk_done

    # ── Clear old snake trail ────────────────────────
    lw   t0, 0(s2)              # len
    li   t1, 0
_snk_clr:
    bge  t1, t0, _snk_clr_done
    slli t2, t1, 2
    add  t2, s0, t2
    lw   a0, 0(t2)              # a0 = sx[i]
    slli t2, t1, 2
    add  t2, s1, t2
    lw   a1, 0(t2)              # a1 = sy[i]
    li   a2, BLACK
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   t0, 4(sp)
    sw   t1, 8(sp)
    jal  ra, draw_pixel
    lw   ra, 0(sp)
    lw   t0, 4(sp)
    lw   t1, 8(sp)
    addi sp, sp, 16
    addi t1, t1, 1
    j    _snk_clr
_snk_clr_done:

    # ── Read UART input ──────────────────────────────
_snk_input:
    jal  ra, uart_kbhit
    beqz a0, _snk_noinput
    jal  ra, uart_getc
    # a0 = key
    li   t0, 119
    bne  a0, t0, _snk_chk_s
    lw   t0, 8(s2)              # dy
    li   t1, 1
    beq  t0, t1, _snk_noinput   # can't reverse
    sw   zero, 4(s2)            # dx = 0
    li   t1, -1
    sw   t1, 8(s2)              # dy = -1
    j    _snk_noinput
_snk_chk_s:
    li   t0, 115
    bne  a0, t0, _snk_chk_a
    lw   t0, 8(s2)
    li   t1, -1
    beq  t0, t1, _snk_noinput
    sw   zero, 4(s2)
    li   t1, 1
    sw   t1, 8(s2)
    j    _snk_noinput
_snk_chk_a:
    li   t0, 97
    bne  a0, t0, _snk_chk_d
    lw   t0, 4(s2)              # dx
    li   t1, 1
    beq  t0, t1, _snk_noinput
    li   t1, -1
    sw   t1, 4(s2)
    sw   zero, 8(s2)
    j    _snk_noinput
_snk_chk_d:
    li   t0, 100
    bne  a0, t0, _snk_chk_q
    lw   t0, 4(s2)
    li   t1, -1
    beq  t0, t1, _snk_noinput
    li   t1, 1
    sw   t1, 4(s2)
    sw   zero, 8(s2)
    j    _snk_noinput
_snk_chk_q:
    li   t0, 113
    bne  a0, t0, _snk_noinput
    li   t0, SNAKE_OVER
    li   t1, 1
    sw   t1, 0(t0)
    j    _snk_loop

_snk_noinput:
    # ── Compute new head ─────────────────────────────
    lw   t0, 0(s0)              # sx[0]
    lw   t1, 4(s2)              # dx
    add  t0, t0, t1
    mv   t2, t0                 # nx = t2
    lw   t0, 0(s1)              # sy[0]
    lw   t1, 8(s2)              # dy
    add  t0, t0, t1
    mv   t3, t0                 # ny = t3

    # ── Wall collision ───────────────────────────────
    bltz t2, _snk_dead
    li   t0, SCREEN_W
    bge  t2, t0, _snk_dead
    bltz t3, _snk_dead
    li   t0, SCREEN_H
    bge  t3, t0, _snk_dead

    # ── Self collision ───────────────────────────────
    lw   t0, 0(s2)              # len
    li   t4, 1
_snk_self:
    bge  t4, t0, _snk_self_done
    slli t5, t4, 2
    add  t5, s0, t5
    lw   t6, 0(t5)              # sx[i]
    bne  t6, t2, _snk_self_next
    slli t5, t4, 2
    add  t5, s1, t5
    lw   t6, 0(t5)              # sy[i]
    beq  t6, t3, _snk_dead
_snk_self_next:
    addi t4, t4, 1
    j    _snk_self
_snk_self_done:

    # ── Check food ───────────────────────────────────
    lw   t4, 0(s3)              # food_x
    lw   t5, 0(s4)              # food_y
    bne  t2, t4, _snk_nofood
    bne  t3, t5, _snk_nofood
    # Ate food!
    lw   t0, 0(s2)
    li   t1, MAX_LEN
    bge  t0, t1, _snk_nogrow
    addi t0, t0, 1
    sw   t0, 0(s2)
_snk_nogrow:
    # Score +10
    li   t0, SNAKE_SCORE
    lw   t1, 0(t0)
    addi t1, t1, 10
    sw   t1, 0(t0)
    # New food position (random)
    jal  ra, rand15
    mv   t0, a0
    # x = 5 + (rand % 68)
    li   t1, 68
_snk_fx:
    blt  t0, t1, _snk_fx_done
    sub  t0, t0, t1
    j    _snk_fx
_snk_fx_done:
    addi t0, t0, 5
    sw   t0, 0(s3)
    jal  ra, rand15
    mv   t0, a0
    li   t1, 48
_snk_fy:
    blt  t0, t1, _snk_fy_done
    sub  t0, t0, t1
    j    _snk_fy
_snk_fy_done:
    addi t0, t0, 5
    sw   t0, 0(s4)

_snk_nofood:
    # ── Shift body ───────────────────────────────────
    lw   t0, 0(s2)              # len
    addi t0, t0, -1
_snk_shift:
    bltz t0, _snk_shift_done
    slli t4, t0, 2
    # sx[i] = sx[i-1]
    add  t5, s0, t4
    lw   t6, -4(t5)
    sw   t6, 0(t5)
    # sy[i] = sy[i-1]
    add  t5, s1, t4
    lw   t6, -4(t5)
    sw   t6, 0(t5)
    addi t0, t0, -1
    j    _snk_shift
_snk_shift_done:

    # Set new head
    sw   t2, 0(s0)
    sw   t3, 0(s1)

    # ── Draw food ────────────────────────────────────
    lw   a0, 0(s3)
    lw   a1, 0(s4)
    li   a2, RED
    jal  ra, draw_pixel

    # ── Draw snake ───────────────────────────────────
    lw   t0, 0(s2)              # len
    li   t1, 0
_snk_draw:
    bge  t1, t0, _snk_draw_done
    slli t2, t1, 2
    add  t2, s0, t2
    lw   a0, 0(t2)              # sx[i]
    slli t2, t1, 2
    add  t2, s1, t2
    lw   a1, 0(t2)              # sy[i]
    beqz t1, _snk_head
    li   a2, GREEN
    j    _snk_draw_px
_snk_head:
    li   a2, YELLOW
_snk_draw_px:
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   t0, 4(sp)
    sw   t1, 8(sp)
    jal  ra, draw_pixel
    lw   ra, 0(sp)
    lw   t0, 4(sp)
    lw   t1, 8(sp)
    addi sp, sp, 16
    addi t1, t1, 1
    j    _snk_draw
_snk_draw_done:

    # ── Delay + yield ────────────────────────────────
    li   t0, 2000
_snk_dly:
    addi t0, t0, -1
    bnez t0, _snk_dly
    jal  ra, yield
    j    _snk_loop

_snk_dead:
    li   t0, SNAKE_OVER
    li   t1, 1
    sw   t1, 0(t0)
_snk_done:
    # Game over: flash RED
    li   t0, 2
_snk_flash:
    beqz t0, _snk_flash_done
    # Fill interior with RED
    li   t3, 1
_snk_fr:
    li   t4, 59
    bge  t3, t4, _snk_fr_done
    li   t5, 1
_snk_fc:
    li   t4, 79
    bge  t5, t4, _snk_fc_done
    mv   a0, t5
    mv   a1, t3
    li   a2, RED
    jal  ra, draw_pixel
    addi t5, t5, 2
    j    _snk_fc
_snk_fc_done:
    addi t3, t3, 2
    j    _snk_fr
_snk_fr_done:
    li   t1, 3000
_snk_fd1:
    addi t1, t1, -1
    bnez t1, _snk_fd1
    # Fill with BLACK
    li   t3, 1
_snk_fr2:
    li   t4, 59
    bge  t3, t4, _snk_fr2_done
    li   t5, 1
_snk_fc2:
    li   t4, 79
    bge  t5, t4, _snk_fc2_done
    mv   a0, t5
    mv   a1, t3
    li   a2, BLACK
    jal  ra, draw_pixel
    addi t5, t5, 2
    j    _snk_fc2
_snk_fc2_done:
    addi t3, t3, 2
    j    _snk_fr2
_snk_fr2_done:
    li   t1, 2000
_snk_fd2:
    addi t1, t1, -1
    bnez t1, _snk_fd2
    addi t0, t0, -1
    j    _snk_flash
_snk_flash_done:
    # Final RED fill
    li   t3, 1
_snk_ffr:
    li   t4, 59
    bge  t3, t4, _snk_ffr_done
    li   t5, 1
_snk_ffc:
    li   t4, 79
    bge  t5, t4, _snk_ffc_done
    mv   a0, t5
    mv   a1, t3
    li   a2, RED
    jal  ra, draw_pixel
    addi t5, t5, 1
    j    _snk_ffc
_snk_ffc_done:
    addi t3, t3, 1
    j    _snk_ffr
_snk_ffr_done:
    jal  ra, yield
    j    _snk_done
