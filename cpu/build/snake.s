	.file	"snake.c"
	.option nopic
	.attribute arch, "rv32i2p1"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.globl	uart_putc
	.type	uart_putc, @function
uart_putc:
	li	a4,1073741824
	addi	a4,a4,8
.L2:
	lw	a5,0(a4)
	andi	a5,a5,1
	bne	a5,zero,.L2
	li	a5,1073741824
	sw	a0,0(a5)
	ret
	.size	uart_putc, .-uart_putc
	.align	2
	.globl	uart_puts
	.type	uart_puts, @function
uart_puts:
	addi	sp,sp,-16
	sw	s0,8(sp)
	sw	ra,12(sp)
	mv	s0,a0
.L5:
	lbu	a0,0(s0)
	bne	a0,zero,.L6
	lw	ra,12(sp)
	lw	s0,8(sp)
	addi	sp,sp,16
	jr	ra
.L6:
	addi	s0,s0,1
	call	uart_putc
	j	.L5
	.size	uart_puts, .-uart_puts
	.align	2
	.globl	uart_print_num
	.type	uart_print_num, @function
uart_print_num:
	addi	sp,sp,-16
	sw	s0,8(sp)
	sw	ra,12(sp)
	mv	s0,a0
	bge	a0,zero,.L9
	li	a0,45
	call	uart_putc
	neg	s0,s0
.L9:
	li	a5,9
	ble	s0,a5,.L10
	li	a1,10
	mv	a0,s0
	call	__divsi3
	call	uart_print_num
.L10:
	mv	a0,s0
	li	a1,10
	call	__modsi3
	lw	s0,8(sp)
	lw	ra,12(sp)
	addi	a0,a0,48
	andi	a0,a0,0xff
	addi	sp,sp,16
	tail	uart_putc
	.size	uart_print_num, .-uart_print_num
	.align	2
	.globl	my_rand
	.type	my_rand, @function
my_rand:
	addi	sp,sp,-16
	sw	s0,8(sp)
	lui	s0,%hi(rng_state)
	lw	a0,%lo(rng_state)(s0)
	li	a1,1103515648
	addi	a1,a1,-403
	sw	ra,12(sp)
	call	__mulsi3
	li	a5,12288
	addi	a5,a5,57
	add	a0,a0,a5
	sw	a0,%lo(rng_state)(s0)
	lw	ra,12(sp)
	lw	s0,8(sp)
	slli	a5,a0,1
	srli	a0,a5,17
	addi	sp,sp,16
	jr	ra
	.size	my_rand, .-my_rand
	.align	2
	.globl	abs
	.type	abs, @function
abs:
	srai	a5,a0,31
	xor	a0,a5,a0
	sub	a0,a0,a5
	ret
	.size	abs, .-abs
	.align	2
	.globl	delay
	.type	delay, @function
delay:
	slli	a5,a0,1
	add	a5,a5,a0
	slli	a5,a5,3
	addi	sp,sp,-16
	add	a5,a5,a0
	sw	zero,12(sp)
	slli	a5,a5,3
.L16:
	lw	a4,12(sp)
	bgt	a5,a4,.L17
	addi	sp,sp,16
	jr	ra
.L17:
	lw	a4,12(sp)
	addi	a4,a4,1
	sw	a4,12(sp)
	j	.L16
	.size	delay, .-delay
	.align	2
	.globl	uart_getc
	.type	uart_getc, @function
uart_getc:
	li	a4,1073741824
	addi	a4,a4,8
.L20:
	lw	a5,0(a4)
	andi	a5,a5,2
	beq	a5,zero,.L20
	li	a5,1073741824
	lw	a0,4(a5)
	andi	a0,a0,0xff
	ret
	.size	uart_getc, .-uart_getc
	.align	2
	.globl	uart_kbhit
	.type	uart_kbhit, @function
uart_kbhit:
	li	a5,1073741824
	lw	a0,8(a5)
	srli	a0,a0,1
	andi	a0,a0,1
	ret
	.size	uart_kbhit, .-uart_kbhit
	.align	2
	.globl	init_game
	.type	init_game, @function
init_game:
	lui	a5,%hi(.LANCHOR0)
	addi	a5,a5,%lo(.LANCHOR0)
	addi	sp,sp,-16
	sw	ra,12(sp)
	addi	a1,a5,128
	mv	a2,a5
	mv	a4,a5
	li	a0,32
	li	a6,16
.L25:
	li	a3,0
.L26:
	add	a7,a2,a3
	sb	a0,0(a7)
	addi	a3,a3,1
	bne	a3,a6,.L26
	addi	a2,a2,16
	bne	a2,a1,.L25
	addi	a0,a5,16
	mv	a3,a5
	li	a2,35
.L28:
	sb	a2,0(a3)
	sb	a2,112(a3)
	addi	a3,a3,1
	bne	a3,a0,.L28
	li	a3,35
.L29:
	sb	a3,0(a5)
	sb	a3,15(a5)
	addi	a5,a5,16
	bne	a5,a1,.L29
	li	a5,3
	lui	a3,%hi(len)
	sw	a5,128(a4)
	sw	a5,%lo(len)(a3)
	li	a5,4
	li	a3,2
	sw	a5,928(a4)
	sw	a3,132(a4)
	sw	a5,932(a4)
	li	a3,1
	sw	a5,936(a4)
	lui	a5,%hi(dx)
	sw	a3,%lo(dx)(a5)
	lui	a5,%hi(dy)
	sw	zero,%lo(dy)(a5)
	lui	a5,%hi(score)
	sw	zero,%lo(score)(a5)
	lui	a5,%hi(game_over)
	sw	a3,136(a4)
	sw	zero,%lo(game_over)(a5)
	call	my_rand
	li	a1,10
	call	__modsi3
	lui	a5,%hi(fx)
	addi	a0,a0,3
	sw	a0,%lo(fx)(a5)
	call	my_rand
	lw	ra,12(sp)
	andi	a0,a0,1
	addi	a0,a0,3
	lui	a5,%hi(fy)
	sw	a0,%lo(fy)(a5)
	addi	sp,sp,16
	jr	ra
	.size	init_game, .-init_game
	.align	2
	.globl	place_food
	.type	place_food, @function
place_food:
	addi	sp,sp,-32
	sw	s0,24(sp)
	lui	s0,%hi(.LANCHOR0)
	sw	s1,20(sp)
	sw	s2,16(sp)
	sw	s3,12(sp)
	sw	ra,28(sp)
	lui	s1,%hi(fx)
	lui	s3,%hi(fy)
	addi	s0,s0,%lo(.LANCHOR0)
	li	s2,32
.L35:
	call	my_rand
	li	a1,10
	call	__modsi3
	addi	a0,a0,3
	sw	a0,%lo(fx)(s1)
	call	my_rand
	andi	a0,a0,1
	lw	a5,%lo(fx)(s1)
	addi	a0,a0,3
	sw	a0,%lo(fy)(s3)
	slli	a0,a0,4
	add	a0,s0,a0
	add	a0,a0,a5
	lbu	a5,0(a0)
	bne	a5,s2,.L35
	lw	ra,28(sp)
	lw	s0,24(sp)
	lw	s1,20(sp)
	lw	s2,16(sp)
	lw	s3,12(sp)
	addi	sp,sp,32
	jr	ra
	.size	place_food, .-place_food
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"\033[H"
	.align	2
.LC1:
	.string	"Score: "
	.align	2
.LC2:
	.string	"  WASD: move  Q: quit\n"
	.align	2
.LC3:
	.string	"\033[?25l"
	.text
	.align	2
	.globl	draw
	.type	draw, @function
draw:
	addi	sp,sp,-32
	sw	s0,24(sp)
	lui	a5,%hi(len)
	lui	s0,%hi(.LANCHOR0)
	addi	s0,s0,%lo(.LANCHOR0)
	lw	a0,%lo(len)(a5)
	addi	a2,s0,128
	sw	s1,20(sp)
	sw	ra,28(sp)
	sw	s2,16(sp)
	sw	s3,12(sp)
	addi	a1,s0,928
	li	a3,0
	mv	s1,a2
.L39:
	bgt	a0,a3,.L41
	lui	a5,%hi(game_over)
	lw	a5,%lo(game_over)(a5)
	bne	a5,zero,.L42
	lui	a5,%hi(fy)
	lw	a5,%lo(fy)(a5)
	lui	a4,%hi(fx)
	lw	a4,%lo(fx)(a4)
	slli	a5,a5,4
	add	a5,s0,a5
	add	a5,a5,a4
	li	a4,64
	sb	a4,0(a5)
.L42:
	lui	a0,%hi(.LC0)
	addi	a0,a0,%lo(.LC0)
	call	uart_puts
	lui	a0,%hi(.LC1)
	addi	a0,a0,%lo(.LC1)
	call	uart_puts
	lui	a5,%hi(score)
	lw	a0,%lo(score)(a5)
	li	s3,16
	call	uart_print_num
	lui	a0,%hi(.LC2)
	addi	a0,a0,%lo(.LC2)
	call	uart_puts
.L43:
	li	s2,0
.L44:
	add	a5,s0,s2
	lbu	a0,0(a5)
	addi	s2,s2,1
	call	uart_putc
	bne	s2,s3,.L44
	li	a0,10
	addi	s0,s0,16
	call	uart_putc
	bne	s0,s1,.L43
	lw	s0,24(sp)
	lw	ra,28(sp)
	lw	s1,20(sp)
	lw	s2,16(sp)
	lw	s3,12(sp)
	lui	a0,%hi(.LC3)
	addi	a0,a0,%lo(.LC3)
	addi	sp,sp,32
	tail	uart_puts
.L41:
	lw	a5,0(a1)
	lw	a6,0(a2)
	snez	a4,a3
	slli	a5,a5,4
	slli	a4,a4,5
	add	a5,s0,a5
	addi	a4,a4,79
	add	a5,a5,a6
	sb	a4,0(a5)
	addi	a3,a3,1
	addi	a1,a1,4
	addi	a2,a2,4
	j	.L39
	.size	draw, .-draw
	.section	.rodata.str1.4
	.align	2
.LC4:
	.string	"\nGame Over! Final Score: "
	.align	2
.LC5:
	.string	"\n"
	.text
	.align	2
	.globl	game_loop
	.type	game_loop, @function
game_loop:
	addi	sp,sp,-48
	sw	s1,36(sp)
	sw	s2,32(sp)
	sw	s3,28(sp)
	sw	s5,20(sp)
	sw	ra,44(sp)
	sw	s0,40(sp)
	sw	s4,24(sp)
	sw	s6,16(sp)
	sw	s7,12(sp)
	sw	s8,8(sp)
	lui	s2,%hi(game_over)
	li	s5,119
	lui	s1,%hi(dy)
	li	s3,1
.L68:
	lw	s4,%lo(game_over)(s2)
	bne	s4,zero,.L49
	call	draw
	li	s7,115
	li	s8,97
	lui	s6,%hi(dx)
.L51:
	call	uart_kbhit
	mv	s0,a0
	bne	a0,zero,.L59
	lui	a7,%hi(len)
	lui	a5,%hi(.LANCHOR0)
	addi	a5,a5,%lo(.LANCHOR0)
	lw	a2,%lo(len)(a7)
	addi	t1,a5,928
	addi	a4,a5,128
	mv	a6,a4
	mv	a0,t1
	li	a1,0
	li	t3,32
.L60:
	bgt	a2,a1,.L61
	lui	a3,%hi(dx)
	lw	a3,%lo(dx)(a3)
	lw	a1,128(a5)
	lw	a0,928(a5)
	add	a1,a1,a3
	lui	a3,%hi(dy)
	lw	a3,%lo(dy)(a3)
	add	a0,a0,a3
	slli	a3,a0,4
	add	a6,a5,a3
	add	a6,a6,a1
	lbu	a6,0(a6)
	addi	t3,a6,-35
	beq	t3,zero,.L76
	addi	a6,a6,-111
	bne	a6,zero,.L62
.L76:
	add	a3,a5,a3
	li	a4,1
	add	a3,a3,a1
	li	a5,88
	sw	a4,%lo(game_over)(s2)
	sb	a5,0(a3)
	call	draw
	lui	a0,%hi(.LC4)
	addi	a0,a0,%lo(.LC4)
	call	uart_puts
	lui	a5,%hi(score)
	lw	a0,%lo(score)(a5)
	call	uart_print_num
	lw	s0,40(sp)
	lw	ra,44(sp)
	lw	s1,36(sp)
	lw	s2,32(sp)
	lw	s3,28(sp)
	lw	s4,24(sp)
	lw	s5,20(sp)
	lw	s6,16(sp)
	lw	s7,12(sp)
	lw	s8,8(sp)
	lui	a0,%hi(.LC5)
	addi	a0,a0,%lo(.LC5)
	addi	sp,sp,48
	tail	uart_puts
.L59:
	call	uart_getc
	bne	a0,s5,.L52
	lw	a5,%lo(dy)(s1)
	beq	a5,s3,.L71
	li	a5,-1
	sw	zero,%lo(dx)(s6)
	sw	a5,%lo(dy)(s1)
.L71:
	mv	s4,s0
	j	.L51
.L52:
	bne	a0,s7,.L54
	lw	a4,%lo(dy)(s1)
	li	a5,-1
	beq	a4,a5,.L71
	sw	zero,%lo(dx)(s6)
	sw	s3,%lo(dy)(s1)
	j	.L71
.L54:
	bne	a0,s8,.L56
	lw	a4,%lo(dx)(s6)
	li	a5,-1
	beq	a4,s3,.L71
.L57:
	sw	a5,%lo(dx)(s6)
	sw	zero,%lo(dy)(s1)
	j	.L71
.L72:
	lw	a3,%lo(dx)(s6)
	li	a4,-1
	mv	a5,s0
	bne	a3,a4,.L57
	j	.L71
.L61:
	lw	a3,0(a0)
	lw	t4,0(a6)
	addi	a1,a1,1
	slli	a3,a3,4
	add	a3,a5,a3
	add	a3,a3,t4
	sb	t3,0(a3)
	addi	a0,a0,4
	addi	a6,a6,4
	j	.L60
.L62:
	lui	a3,%hi(fx)
	lw	a3,%lo(fx)(a3)
	bne	a3,a1,.L64
	lui	a3,%hi(fy)
	lw	s0,%lo(fy)(a3)
	sub	s0,s0,a0
	seqz	s0,s0
.L64:
	slli	a3,a2,2
	add	a4,a3,a4
	mv	a6,a2
	add	a3,a3,t1
.L65:
	bgt	a6,zero,.L66
	sw	a1,128(a5)
	sw	a0,928(a5)
	beq	s0,zero,.L67
	lui	a4,%hi(score)
	lw	a5,%lo(score)(a4)
	addi	a2,a2,1
	sw	a2,%lo(len)(a7)
	addi	a5,a5,10
	sw	a5,%lo(score)(a4)
	call	place_food
.L67:
	li	a0,1
	call	delay
	bne	s4,zero,.L68
	li	a0,3
	call	delay
	j	.L68
.L66:
	lw	t1,-4(a4)
	addi	a3,a3,-4
	addi	a4,a4,-4
	sw	t1,4(a4)
	lw	t1,0(a3)
	addi	a6,a6,-1
	sw	t1,4(a3)
	j	.L65
.L56:
	li	a5,100
	beq	a0,a5,.L72
	li	a5,113
	bne	a0,a5,.L71
	li	a5,1
	sw	a5,%lo(game_over)(s2)
.L49:
	lw	ra,44(sp)
	lw	s0,40(sp)
	lw	s1,36(sp)
	lw	s2,32(sp)
	lw	s3,28(sp)
	lw	s4,24(sp)
	lw	s5,20(sp)
	lw	s6,16(sp)
	lw	s7,12(sp)
	lw	s8,8(sp)
	addi	sp,sp,48
	jr	ra
	.size	game_loop, .-game_loop
	.section	.rodata.str1.4
	.align	2
.LC6:
	.string	"\033[?25l\033[2J"
	.align	2
.LC7:
	.string	"\n*** Snake for MineCPU ***\n"
	.align	2
.LC8:
	.string	"WASD to move, Q to quit\n"
	.align	2
.LC9:
	.string	"Press any key to start...\n"
	.align	2
.LC10:
	.string	"\033[?25h\n"
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	sw	ra,12(sp)
	li	a5,1073741824
	li	a4,20
	lui	a0,%hi(.LC6)
	sw	a4,12(a5)
	addi	a0,a0,%lo(.LC6)
	call	uart_puts
	call	init_game
	lui	a0,%hi(.LC7)
	addi	a0,a0,%lo(.LC7)
	call	uart_puts
	lui	a0,%hi(.LC8)
	addi	a0,a0,%lo(.LC8)
	call	uart_puts
	lui	a0,%hi(.LC9)
	addi	a0,a0,%lo(.LC9)
	call	uart_puts
	call	game_loop
	lui	a0,%hi(.LC10)
	addi	a0,a0,%lo(.LC10)
	call	uart_puts
	lw	ra,12(sp)
	li	a0,0
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.globl	rng_state
	.globl	game_over
	.globl	score
	.globl	fy
	.globl	fx
	.globl	dy
	.globl	dx
	.globl	len
	.globl	sy
	.globl	sx
	.globl	grid
	.globl	UART_BAUD
	.globl	UART_STATUS
	.globl	UART_RX
	.globl	UART_TX
	.bss
	.align	2
	.set	.LANCHOR0,. + 0
	.type	grid, @object
	.size	grid, 128
grid:
	.zero	128
	.type	sx, @object
	.size	sx, 800
sx:
	.zero	800
	.type	sy, @object
	.size	sy, 800
sy:
	.zero	800
	.section	.sbss,"aw",@nobits
	.align	2
	.type	game_over, @object
	.size	game_over, 4
game_over:
	.zero	4
	.type	score, @object
	.size	score, 4
score:
	.zero	4
	.type	fy, @object
	.size	fy, 4
fy:
	.zero	4
	.type	fx, @object
	.size	fx, 4
fx:
	.zero	4
	.type	dy, @object
	.size	dy, 4
dy:
	.zero	4
	.type	dx, @object
	.size	dx, 4
dx:
	.zero	4
	.type	len, @object
	.size	len, 4
len:
	.zero	4
	.section	.sdata,"aw"
	.align	2
	.type	rng_state, @object
	.size	rng_state, 4
rng_state:
	.word	12345
	.section	.srodata,"a"
	.align	2
	.type	UART_BAUD, @object
	.size	UART_BAUD, 4
UART_BAUD:
	.word	1073741836
	.type	UART_STATUS, @object
	.size	UART_STATUS, 4
UART_STATUS:
	.word	1073741832
	.type	UART_RX, @object
	.size	UART_RX, 4
UART_RX:
	.word	1073741828
	.type	UART_TX, @object
	.size	UART_TX, 4
UART_TX:
	.word	1073741824
	.globl	__mulsi3
	.globl	__modsi3
	.globl	__divsi3
	.ident	"GCC: (xPack GNU RISC-V Embedded GCC x86_64) 15.2.0"
	.section	.note.GNU-stack,"",@progbits
