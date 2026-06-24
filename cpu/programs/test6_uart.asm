# test6_uart.asm -- UART TX: send "Hello, CPU!"
# UART registers at 0x4000_0000:
#   0x00 = TX_DATA, 0x08 = STATUS.bit0 = tx_busy
lui x10, 0x40000        # x10 = UART base

addi x11, x0, 10
sw x11, 12(x10)         # BAUD_DIV = 10

# Store "Hello, CPU!\n" at data_mem[0x00-0x0B]
addi x12, x0, 72        # H
sb x12, 0(x0)
addi x12, x0, 101       # e
sb x12, 1(x0)
addi x12, x0, 108       # l
sb x12, 2(x0)
addi x12, x0, 108       # l
sb x12, 3(x0)
addi x12, x0, 111       # o
sb x12, 4(x0)
addi x12, x0, 44        # ,
sb x12, 5(x0)
addi x12, x0, 32        # (space)
sb x12, 6(x0)
addi x12, x0, 67        # C
sb x12, 7(x0)
addi x12, x0, 80        # P
sb x12, 8(x0)
addi x12, x0, 85        # U
sb x12, 9(x0)
addi x12, x0, 33        # !
sb x12, 10(x0)
addi x12, x0, 10        # \n
sb x12, 11(x0)

# Send 12 characters
addi x13, x0, 0         # index
addi x14, x0, 12        # count

loop:
lb x15, 0(x13)          # char = mem[index]

tx_wait:
lw x16, 8(x10)          # UART STATUS
andi x16, x16, 1
bne x16, x0, tx_wait

sw x15, 0(x10)          # UART TX = char
addi x13, x13, 1
blt x13, x14, loop

done:
beq x0, x0, done
