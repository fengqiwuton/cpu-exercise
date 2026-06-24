# test_csr.asm — CSR + exception test
# Tests: csrrw, csrrs, csrrc, ecall, mret

# 1. Set up mtvec to point to exception handler
la x5, handler          # x5 = handler address
csrrw x0, mtvec, x5     # mtvec = handler address

# 2. Write to mstatus via csrrw (read old, write new)
csrrw x6, mstatus, x0   # x6 = old mstatus
# Set MIE bit (bit 3)
csrrsi x0, mstatus, 8   # mstatus |= (1<<3) — set MIE

# 3. Test csrrc (read and clear)
csrrw x7, mcause, x0    # x7 = mcause (should be 0)
csrrci x0, mcause, 0    # clear mcause

# 4. Test ecall — triggers exception, handler runs
sw x0, 16(x0)           # mem[16] = 0 (reset marker)
ecall                    # trap to handler!

# After mret, we return here
sw x6, 24(x0)           # mem[24] = old mstatus value

# Infinite loop at end
done:
beq x0, x0, done

# ── Exception handler ─────────────────────────────────
handler:
    # Save registers we'll use
    sw x10, 32(x0)
    sw x11, 36(x0)

    # Read mcause (should be 11 = ecall from M-mode)
    csrrw x10, mcause, x0
    sw x10, 20(x0)       # mem[20] = mcause (expect 11)

    # Write to mepc to advance past ecall (ecall is 4 bytes)
    csrrw x11, mepc, x0  # x11 = mepc (address of ecall)
    addi x11, x11, 4     # advance past ecall
    csrrw x0, mepc, x11  # mepc = ecall_addr + 4

    # Restore registers
    lw x10, 32(x0)
    lw x11, 36(x0)

    mret                  # return from exception

# ── CSR address definitions (for assembler) ───────────
.equ mstatus, 0x300
.equ mtvec,   0x305
.equ mepc,    0x341
.equ mcause,  0x342
