`timescale 1ns/1ps
module pc_tb;
    logic clk, rst_n;
    logic [31:0] next_pc, pc;
    pc dut (.*);
    always #5 clk = ~clk;

    initial begin
        $dumpfile("pc_tb.vcd"); $dumpvars(0, pc_tb);
        clk = 0; rst_n = 0; next_pc = 0;
        #10 rst_n = 1;
        #10 next_pc = 32'h0000_0004;
        #10 if (pc !== 32'h4) $error("FAIL: got %h", pc);
        next_pc = 32'h0000_1000;
        #10 if (pc !== 32'h1000) $error("FAIL: got %h", pc);
        next_pc = 32'hFFFF_FFFC;
        #10 if (pc !== 32'hFFFF_FFFC) $error("FAIL: got %h", pc);
        $display("pc: PASSED"); $finish;
    end
endmodule
