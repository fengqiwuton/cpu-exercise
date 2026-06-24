	.file	"hello.c"
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
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"Hello from C on MineCPU!\n"
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	sw	ra,12(sp)
	li	a5,1073741824
	li	a4,2
	lui	a0,%hi(.LC0)
	addi	a0,a0,%lo(.LC0)
	sw	a4,12(a5)
	call	uart_puts
	lw	ra,12(sp)
	li	a0,0
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.globl	UART_BAUD
	.globl	UART_STATUS
	.globl	UART_RX
	.globl	UART_TX
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
	.ident	"GCC: (xPack GNU RISC-V Embedded GCC x86_64) 15.2.0"
	.section	.note.GNU-stack,"",@progbits
