module data_mem #(parameter DEPTH = 2048) (
    input  logic        clk,
    input  logic [31:0] addr, write_data,
    input  logic        mem_write,
    input  logic [3:0]  byte_enable,
    output logic [31:0] read_data
);
    logic [31:0] mem [0:DEPTH-1];
    initial $readmemh("data.hex", mem);
    assign read_data = mem[addr[31:2]];

    always_ff @(posedge clk) begin
        if (mem_write) begin
            if (byte_enable[0]) mem[addr[31:2]][7:0]   <= write_data[7:0];
            if (byte_enable[1]) mem[addr[31:2]][15:8]  <= write_data[15:8];
            if (byte_enable[2]) mem[addr[31:2]][23:16] <= write_data[23:16];
            if (byte_enable[3]) mem[addr[31:2]][31:24] <= write_data[31:24];
        end
    end
endmodule
