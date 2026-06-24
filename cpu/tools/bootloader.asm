# bootloader.asm — UART program loader
# Receives raw binary, writes to BRAM at 0x40001000+, jumps to 0x1000
# Protocol: 4 bytes word_count (LE), then word_count * 4 bytes program (LE)

_start:
    lui x10, 0x40000         # x10 = UART_BASE
    addi x11, x0, 10
    sw x11, 12(x10)          # BAUD_DIV = 10

    lui x20, 0x40001         # x20 = BRAM write base (0x40001000)

    # Print "RDY\n"
    addi x12, x0, 82         # 'R'
    jal x1, uart_tx
    addi x12, x0, 68         # 'D'
    jal x1, uart_tx
    addi x12, x0, 89         # 'Y'
    jal x1, uart_tx
    addi x12, x0, 10         # '\n'
    jal x1, uart_tx

    # Read word count (4 bytes LE)
    add x22, x0, x0          # word_count = 0
    jal x1, uart_rx          # byte 0
    add x22, x12, x0
    jal x1, uart_rx          # byte 1
    slli x12, x12, 8
    or x22, x22, x12
    jal x1, uart_rx          # byte 2
    slli x12, x12, 16
    or x22, x22, x12
    jal x1, uart_rx          # byte 3
    slli x12, x12, 24
    or x22, x22, x12

    add x21, x0, x0          # offset = 0

load_loop:
    beq x22, x0, done_load

    # Read 4 bytes for one word
    jal x1, uart_rx
    add x23, x12, x0
    jal x1, uart_rx
    slli x12, x12, 8
    or x23, x23, x12
    jal x1, uart_rx
    slli x12, x12, 16
    or x23, x23, x12
    jal x1, uart_rx
    slli x12, x12, 24
    or x23, x23, x12

    # Write to BRAM *(BRAM_BASE + offset)
    slli x12, x21, 2
    add x12, x20, x12
    sw x23, 0(x12)

    addi x21, x21, 1
    addi x22, x22, -1
    jal x0, load_loop

done_load:
    lui x1, 0x00001
    jalr x0, x1, 0           # jump to 0x1000

# ── uart_tx ──
uart_tx:
    lui x15, 0x40000
tx_wait:
    lw x16, 8(x15)
    andi x16, x16, 1
    bne x16, x0, tx_wait
    sw x12, 0(x15)
    jalr x0, x1, 0

# ── uart_rx ──
uart_rx:
    lui x15, 0x40000
rx_wait:
    lw x16, 8(x15)
    andi x16, x16, 2
    beq x16, x0, rx_wait
    lw x12, 4(x15)
    andi x12, x12, 0xFF
    jalr x0, x1, 0
