// Boot ROM — fixed bootloader, starts at address 0x0000
// Loads program from UART into insn_mem (BRAM) at 0x1000, then jumps there
module boot_rom #(parameter DEPTH = 256) (
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] rom [0:DEPTH-1];

    // Bootloader: receive 4-byte header (N=program size in words),
    // then N words via UART, write to BRAM, jump to 0x1000
    // UART: TX=0x40000000, RX=0x40000004, STATUS=0x40000008, BAUD=0x4000000C
    // BRAM write: 0x40001000+
    // Hand-assembled bootloader (see tools/bootloader.asm)
    assign instr = rom[addr[31:2]];

    // Default empty; real content loaded from bootloader.hex if available
    // Minimal hardcoded fallback:
    initial begin
        for (int i = 0; i < DEPTH; i++) rom[i] = 32'h00000013; // nop
        `ifdef BOOT_HEX
            $readmemh(`BOOT_HEX, rom);
        `endif
    end
endmodule
