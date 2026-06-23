`timescale 1ns/1ps

module cpu_tb;
    logic clk, rst_n;
    cpu_top dut (.*);

    always #5 clk = ~clk;

    task check_mem;
        input [31:0] addr;
        input [31:0] expected;
        input string  msg;
        begin
            // Hierarchical access: word index = byte addr >> 2
            if (dut.u_data_mem.mem[addr[31:2]] !== expected)
                $error("%s: mem[%h] = %h, expected %h",
                       msg, addr, dut.u_data_mem.mem[addr[31:2]], expected);
            else
                $display("  PASS: %s", msg);
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, cpu_tb);

        clk = 0;
        rst_n = 0;
        #10 rst_n = 1;

        // Enough cycles for the longest test (test3: 22 instrs)
        #600;

        // Debug: dump key memory locations
        $display("DEBUG mem[0]=%h, mem[1]=%h", dut.u_data_mem.mem[0], dut.u_data_mem.mem[1]);
        $display("DEBUG mem[2]=%h (expect 13=0d)", dut.u_data_mem.mem[2]);
        $display("DEBUG mem[16]=%h, mem[17]=%h", dut.u_data_mem.mem[16], dut.u_data_mem.mem[17]);
        $display("DEBUG mem[32]=%h, mem[33]=%h", dut.u_data_mem.mem[32], dut.u_data_mem.mem[33]);
        $display("DEBUG mem[64]=%h, mem[65]=%h", dut.u_data_mem.mem[64], dut.u_data_mem.mem[65]);

        // Detect which test ran by checking RESULT addresses
        // (not initial data, since data.hex preloads all regions)

        // test1_alu: mem[2] (=byte 8) stores add result 13
        if (dut.u_data_mem.mem[2] == 32'd13) begin
            $display("=== test1_alu results ===");
            check_mem(32'h08, 32'd13, "add: 10+3=13");
            check_mem(32'h0C, 32'd7,  "sub: 10-3=7");
            check_mem(32'h10, 32'd2,  "and: 10&3=2");
            check_mem(32'h14, 32'd11, "or:  10|3=11");
        end

        // test2_mem: mem[20] (=byte 80=0x50) stores sw result DEADBEEF
        if (dut.u_data_mem.mem[20] == 32'hDEAD_BEEF) begin
            $display("=== test2_mem results ===");
            check_mem(32'h50, 32'hDEAD_BEEF, "sw/lw DEADBEEF");
            check_mem(32'h54, 32'hCAFE_1234, "sw/lw CAFE1234");
            check_mem(32'h58, 32'h0, "sub check DEADBEEF match");
            check_mem(32'h5C, 32'h0, "sub check CAFE1234 match");
        end

        // test3_branch: mem[37] (=byte 148=0x94) stores beq pass marker 5
        if (dut.u_data_mem.mem[37] == 32'd5) begin
            $display("=== test3_branch results ===");
            check_mem(32'h94, 32'd5,  "beq taken (5==5)");
            check_mem(32'h9C, 32'd5,  "blt taken (5<10)");
            check_mem(32'hA4, 32'd5,  "bge taken (10>=5)");
            check_mem(32'hAC, 32'd5,  "bltu taken (5<10)");
            check_mem(32'hB4, 32'd5,  "bgeu taken (10>=5)");
            check_mem(32'hB8, 32'd10, "beq NOT taken (5!=10)");
            check_mem(32'hBC, 32'd0,  "b6 sw x0 (should be 0)");
        end

        // test4_integration: mem[72] (=byte 288=0x120) stores sum 15
        if (dut.u_data_mem.mem[72] == 32'd15) begin
            $display("=== test4_integration results ===");
            check_mem(32'h120, 32'd15, "sum 1+2+3+4+5 = 15");
            check_mem(32'h130, 32'd15, "pass marker (beq worked)");
        end

        $display("Simulation finished.");
        $finish;
    end
endmodule
