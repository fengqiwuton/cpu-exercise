`timescale 1ns/1ps

module pipe_verify_tb;
    logic clk, rst_n;
    logic uart_rx_pin = 1'b1;
    pipeline_top dut (.*);

    // ── Performance counters ────────────────────────────────
    integer cycle;
    integer instr_count;    // retired instructions
    integer stall_count;
    integer flush_count;
    integer prev_pc;

    always #5 clk = ~clk;

    // Cycle counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle <= 0;
        else cycle <= cycle + 1;
    end

    // Instruction retirement counter (WB stage writes)
    always_ff @(posedge clk) begin
        if (dut.mem_wb_reg_write)
            instr_count <= instr_count + 1;
    end

    // Stall counter
    always_ff @(posedge clk) begin
        if (dut.stall_f)
            stall_count <= stall_count + 1;
    end

    // Flush counter (branch taken)
    always_ff @(posedge clk) begin
        if (dut.id_branch_taken)
            flush_count <= flush_count + 1;
    end

    // ── Result verification ─────────────────────────────────
    task check_mem;
        input [31:0] addr;
        input [31:0] expected;
        input string  msg;
        begin
            if (dut.u_data_mem.mem[addr[31:2]] !== expected)
                $error("%s: mem[%h]=%h expected %h",
                       msg, addr, dut.u_data_mem.mem[addr[31:2]], expected);
            else
                $display("  PASS: %s", msg);
        end
    endtask

    // ── Simulation ──────────────────────────────────────────
    initial begin
        $dumpfile("pipe_verify.vcd");
        $dumpvars(0, pipe_verify_tb);
        clk = 0; rst_n = 0; instr_count = 0; stall_count = 0; flush_count = 0;
        #20 rst_n = 1;

        // Wait for program to finish (all SWs done)
        #50000;  // 5000 cycles should be plenty

        $display("=== Pipeline Verification ===");
        $display("Cycles: %0d", cycle);
        $display("Instructions retired: %0d", instr_count);
        $display("Stalls: %0d, Flushes: %0d", stall_count, flush_count);
        $display("CPI: %.2f", $itor(cycle) / $itor(instr_count));
        $display("");

        // Test 1: forwarding (10+3=13, data.hex has 10 and 3)
        check_mem(32'h10, 32'd13, "Test1: RAW forwarding (10+3=13)");
        // Test 2: load-use stall (10+10=20, mem[0]=10)
        check_mem(32'h14, 32'd20, "Test2: Load-use stall (10+10=20)");
        // Test 3: forwarding cascade (10+1+2+3=16)
        check_mem(32'h18, 32'd16, "Test3: Forward cascade (10+1+2+3=16)");
        // Test 4: branch taken + flush
        check_mem(32'h1C, 32'd1,  "Test4: Branch taken flush (x5=1)");
        // Test 5: branch not taken
        check_mem(32'h20, 32'd42, "Test5: Branch NOT taken (x5=42)");
        // Test 6: JAL flush — x7=return_addr (not 99)
        // word 9 = byte 36. Return address = PC of jal + 4
        $display("  Test6: JAL x7=%h (return address)", dut.u_data_mem.mem[9]);
        // Test 7: bne taken
        check_mem(32'h28, 32'd10, "Test7: BNE taken flush (x8=10)");

        $display("");
        $display("pipe_verify_tb: done");
        $finish;
    end
endmodule
