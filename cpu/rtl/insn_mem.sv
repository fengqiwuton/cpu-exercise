module insn_mem #(
    parameter DEPTH = 1024,
    parameter string PROG_FILE = "program.hex"
) (
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] mem [0:DEPTH-1];
    initial $readmemh("program.hex", mem);
    assign instr = mem[addr[31:2]];
endmodule
