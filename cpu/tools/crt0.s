# crt0.s — startup code for MineCPU C programs
# Sets up stack, clears BSS, calls main(), loops forever

.section .text.init
.globl _start
_start:
    # Set stack pointer
    la sp, __stack_top

    # Clear BSS
    la t0, __bss_start
    la t1, __bss_end
1:
    bge t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:

    # Call main
    call main

    # If main returns, loop forever
3:
    j 3b
