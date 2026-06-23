`timescale 1ns/1ps
module data_mem_tb;
    logic clk, mem_write;
    logic [31:0] addr, write_data, read_data;
    data_mem #(.DEPTH(1024)) dut (.*);
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dmem_tb.vcd"); $dumpvars(0, data_mem_tb);
        clk = 0; mem_write = 0;

        // Write addr 0
        #10 addr = 0; write_data = 32'hCAFE_F00D; mem_write = 1;
        #10 mem_write = 0; addr = 0; #5;
        if (read_data !== 32'hCAFE_F00D) $error("readback fail");

        // Write addr 8
        addr = 8; write_data = 32'hDEAD_BEEF; mem_write = 1;
        #10 mem_write = 0; addr = 8; #5;
        if (read_data !== 32'hDEAD_BEEF) $error("addr 8 fail");

        // addr 0 still has old value
        addr = 0; #5;
        if (read_data !== 32'hCAFE_F00D) $error("addr 0 corrupted");

        $display("data_mem: PASSED"); $finish;
    end
endmodule
