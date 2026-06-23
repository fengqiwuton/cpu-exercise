`timescale 1ns/1ps
module regfile_tb;
    logic clk, reg_write;
    logic [4:0] rs1_addr, rs2_addr, rd_addr;
    logic [31:0] rd_data, rs1_data, rs2_data;
    regfile dut (.*);
    always #5 clk = ~clk;

    initial begin
        $dumpfile("rf_tb.vcd"); $dumpvars(0, regfile_tb);
        clk = 0; reg_write = 0;

        // x0 reads 0
        #10 rs1_addr = 0; #2;
        if (rs1_data !== 0) $error("x0 fail");

        // write x1, read back
        #10 rd_addr = 1; rd_data = 32'hDEAD_BEEF; reg_write = 1;
        #10 reg_write = 0; rs1_addr = 1; #2;
        if (rs1_data !== 32'hDEAD_BEEF) $error("x1 fail");

        // write x0 ignored
        rd_addr = 0; rd_data = 32'hCAFE_CAFE; reg_write = 1;
        #10 reg_write = 0; rs1_addr = 0; #2;
        if (rs1_data !== 0) $error("x0 write fail");

        // dual read
        #10 rd_addr = 2; rd_data = 32'hAAAA_BBBB; reg_write = 1;
        #10 reg_write = 0; rs1_addr = 1; rs2_addr = 2; #2;
        if (rs1_data !== 32'hDEAD_BEEF || rs2_data !== 32'hAAAA_BBBB)
            $error("dual read fail");

        $display("regfile: PASSED"); $finish;
    end
endmodule
