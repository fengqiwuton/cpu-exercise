// Dual-port instruction memory — readable by CPU, writable via MMIO
// Port A: instruction fetch (read-only)
// Port B: program load (write via MMIO at 0x4000_1000+)
module insn_mem #(parameter DEPTH = 1024) (
    // Port A — instruction fetch
    input  logic [31:0] addr_a,
    output logic [31:0] instr_a,

    // Port B — program write
    input  logic        clk,
    input  logic [31:0] addr_b,
    input  logic [31:0] data_b,
    input  logic        wr_en_b
);
    logic [31:0] mem [0:DEPTH-1];

    // Port A: combinational read (instruction fetch)
    assign instr_a = mem[addr_a[31:2]];

    // Port B: synchronous write (program load)
    always_ff @(posedge clk) begin
        if (wr_en_b)
            mem[addr_b[31:2]] <= data_b;
    end
endmodule
