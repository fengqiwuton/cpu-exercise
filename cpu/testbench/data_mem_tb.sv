`timescale 1ns/1ps
module data_mem_tb;
    logic clk, mem_write;
    logic [31:0] addr, write_data, read_data;
    logic [3:0]  byte_enable;
    data_mem #(1024) dut (.*);
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dmem_tb.vcd"); $dumpvars(0, data_mem_tb);
        clk = 0; mem_write = 0; byte_enable = 4'b1111;

        // Full word write (sw)
        #10 addr=0; write_data=32'hDEAD_BEEF; mem_write=1;
        #10 mem_write=0; addr=0; #5;
        if (read_data !== 32'hDEAD_BEEF) $error("sw fail");

        // Byte write to addr 4, byte 1 (bits 15:8)
        addr=4; write_data=32'h0000_4200; byte_enable=4'b0010; mem_write=1;
        #10 mem_write=0; addr=4; #5;
        if (read_data[15:8] !== 8'h42) $error("sb fail");
        addr=0; #5;
        if (read_data !== 32'hDEAD_BEEF) $error("sb corrupted addr0");

        // Half-word write to addr 8, bytes 2-3
        addr=8; write_data=32'hCAFE_0000; byte_enable=4'b1100; mem_write=1;
        #10 mem_write=0; addr=8; #5;
        if (read_data[31:16] !== 16'hCAFE) $error("sh fail");

        // Byte 0 write
        addr=12; write_data=32'h0000_00FF; byte_enable=4'b0001; mem_write=1;
        #10 mem_write=0; addr=12; #5;
        if (read_data[7:0] !== 8'hFF) $error("sb byte0 fail");

        $display("data_mem: PASSED"); $finish;
    end
endmodule
