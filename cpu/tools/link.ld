/* Linker script for MineCPU (Harvard: separate code/data memories)
 * Code: 0x0000_0000  -> insn_mem
 * Data: 0x0000_1000  -> data_mem (data_mem DEPTH=2048 for this range)
 * Stack: 0x0000_2000 -> top of data
 */
MEMORY
{
    CODE (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    DATA (rw)  : ORIGIN = 0x00001000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        *(.text.init)      /* crt0 entry */
        *(.text*)
    } > CODE

    /* .rodata in DATA because Harvard: lw can't read insn_mem */
    .rodata : {
        *(.rodata*)
    } > DATA

    .data : {
        *(.data*)
    } > DATA

    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > DATA

    /* Stack pointer starts at top of DATA region */
    __stack_top = ORIGIN(DATA) + LENGTH(DATA);
}
