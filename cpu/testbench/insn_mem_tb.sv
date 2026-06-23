`timescale 1ns/1ps
module insn_mem_tb;
    logic [31:0] addr, instr;
    insn_mem #(.DEPTH(1024)) dut (.*);
    initial begin
        $dumpfile("imem_tb.vcd"); $dumpvars(0, insn_mem_tb);
        #10 addr = 32'h0;
        #10 if (instr !== 32'h00000033) $error("FAIL at addr 0: got %h", instr);
        addr = 32'h4;
        #10 if (instr !== 32'h0010e133) $error("FAIL at addr 4: got %h", instr);
        $display("insn_mem: PASSED"); $finish;
    end
endmodule
