`timescale 1ns/1ps

module cpu_tb;
    logic clk, rst_n;
    logic uart_rx_pin = 1'b1;  // idle, no RX input for unit tests
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

        // Enough cycles for UART hello test (12 chars × 100cyc)
        #100000;

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

        // test5_rv32i: mem[4] (=byte 16) stores addi result 12
        if (dut.u_data_mem.mem[4] == 32'd12) begin
            $display("=== test5_rv32i results ===");
            check_mem(32'h10, 32'd12, "addi: 5+7=12");
            check_mem(32'h14, 32'd1,  "slti: 10<20 -> 1");
            check_mem(32'h18, 32'd0,  "slti: 10<5 -> 0");
            check_mem(32'h1C, 32'd1,  "sltiu: 10<20 -> 1");
            check_mem(32'h20, 32'd245, "xori: 10^255=245");
            check_mem(32'h24, 32'd250, "ori: 10|240=250");
            check_mem(32'h28, 32'd10, "andi: 10&15=10");
            check_mem(32'h2C, 32'd16, "slli: 1<<4=16");
            check_mem(32'h30, 32'hFFFF_FFC0, "srai: -256>>>2");
            check_mem(32'h34, 32'd16, "srli: 256>>4=16");
            check_mem(32'h38, 32'd1,  "slt: 5<10 -> 1");
            check_mem(32'h3C, 32'd0,  "sltu: 10<5 -> 0");
            check_mem(32'h40, 32'd15, "xor: 5^10=15");
            check_mem(32'h44, 32'd5120, "sll: 5<<10=5120");
            check_mem(32'h48, 32'd0,  "srl: 10>>5=0");
            check_mem(32'h4C, 32'h1234_5000, "lui: 0x12345000");
            check_mem(32'h54, 32'd5,  "bne taken");
            check_mem(32'h58, 32'd10, "bne NOT taken");
            check_mem(32'h60, 32'hFFFF_FFAB, "lb: sext(0xAB)");
            check_mem(32'h64, 32'hAB, "lbu: 0xAB");
            check_mem(32'h68, 32'h5678, "lh: 0x5678");
            check_mem(32'h6C, 32'h5678, "lhu: 0x5678");
            check_mem(32'h74, 32'h42, "sb: 0x42");
            check_mem(32'h7C, 32'h7AB, "sh: 0x7AB");
            check_mem(32'h80, 32'h42, "jal/jalr: x22=0x42");
        end

        $display("Simulation finished.");
        $finish;
    end
endmodule
