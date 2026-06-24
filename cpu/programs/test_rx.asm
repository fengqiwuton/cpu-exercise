# test_rx.asm — verify UART RX receives a character
lui x10, 0x40000
addi x11, x0, 10
sw x11, 12(x10)        # BAUD_DIV = 10

# Wait for a character from UART RX
rx_wait:
lw x12, 8(x10)         # STATUS
andi x12, x12, 2       # bit1 = rx_ready
beq x12, x0, rx_wait   # wait until ready

# Read the received character
lw x13, 4(x10)         # RX_DATA

# Send it back via TX to verify
tx_wait:
lw x12, 8(x10)
andi x12, x12, 1       # bit0 = tx_busy
bne x12, x0, tx_wait
sw x13, 0(x10)         # echo back

# Done
done:
beq x0, x0, done
