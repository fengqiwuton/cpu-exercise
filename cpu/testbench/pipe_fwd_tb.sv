`timescale 1ns/1ps

module pipe_fwd_tb;
    logic clk, rst_n;
    logic uart_rx_pin = 1'b1;
    pipeline_top dut (.*);

    always #5 clk = ~clk;

    task check(input [31:0] word_idx, input [31:0] expected, input string msg);
        begin
            if (dut.u_data_mem.mem[word_idx] !== expected)
                $error("%s: mem[%0d]=%h expected %h",
                       msg, word_idx, dut.u_data_mem.mem[word_idx], expected);
            else
                $display("  PASS: %s", msg);
        end
    endtask

    // Per-stage tracing for first 15 cycles
    integer cyc;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cyc <= 0;
        else cyc <= cyc + 1;
    end

    always_ff @(posedge clk) begin
        if (cyc < 15) begin
            $display("c=%0d: PC=%h IF=%h ID=%h | EX: alu=%h fw_a=%0d fw_b=%0d | MEM: wr=%b addr=%h data=%h",
                cyc, dut.pc, dut.imem_instr, dut.if_id_instr,
                dut.ex_alu_result, dut.forward_a, dut.forward_b,
                dut.ex_mem_mem_write, dut.ex_mem_alu_result, dut.ex_mem_rs2_data);
        end
    end

    initial begin
        $dumpfile("pipe_fwd.vcd");
        $dumpvars(0, pipe_fwd_tb);
        clk = 0; rst_n = 0;
        #20 rst_n = 1;
        #10000;

        $display("");
        $display("=== Forwarding Tests ===");
        check(4, 32'd18, "TestA: x1=10,x2=15,x3=18");
        check(5, 32'd17, "TestB: Load-use (10+7=17)");
        check(6, 32'd42, "TestC: Store forward (x6=42)");
        check(7, 32'd13, "TestD: Double load (10+3=13)");

        $finish;
    end
endmodule
