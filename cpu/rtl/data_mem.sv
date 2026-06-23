module data_mem #(parameter DEPTH = 1024) (
    input  logic        clk,
    input  logic [31:0] addr, write_data,
    input  logic        mem_write,
    output logic [31:0] read_data
);
    logic [31:0] mem [0:DEPTH-1];
    initial $readmemh("programs/data.hex", mem);
    assign read_data = mem[addr[31:2]];
    always_ff @(posedge clk)
        if (mem_write) mem[addr[31:2]] <= write_data;
endmodule
