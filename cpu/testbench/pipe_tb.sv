`timescale 1ns/1ps

module pipe_tb;
    logic clk, rst_n;
    logic uart_rx_pin = 1'b1;
    pipeline_top dut (.*);

    always #5 clk = ~clk;

    initial begin
        $dumpfile("pipe.vcd");
        $dumpvars(0, pipe_tb);
        clk = 0; rst_n = 0;
        #20 rst_n = 1;
        #200000;  // 20K cycles, enough for program
        $display("pipe_tb: done");
        $finish;
    end

    // Track first few writes to data_mem
    always_ff @(posedge clk) begin
        if (dut.ex_mem_mem_write && dut.ex_mem_alu_result < 128) begin
            $display("t=%0t MEM write: addr=%h data=%h", $time,
                     dut.ex_mem_alu_result, dut.ex_mem_rs2_data);
        end
    end

    // Track register writes (show actual write-back data)
    wire [31:0] wb_wr_data;
    assign wb_wr_data = dut.mem_wb_mem_to_reg ? dut.mem_wb_mem_data : dut.mem_wb_alu_result;
    always_ff @(posedge clk) begin
        if (dut.mem_wb_reg_write && dut.mem_wb_rd != 0) begin
            $display("t=%0t WB: x%0d <= %h", $time, dut.mem_wb_rd, wb_wr_data);
        end
    end

    integer cycle;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle <= 0;
        else cycle <= cycle + 1;
    end
    always_ff @(posedge clk) begin
        if (cycle < 30) begin
            $display("c=%0d PC=%h stall=%b flush=%b id_branch_taken=%b id_instr=%h",
                cycle, dut.pc, dut.stall_f, dut.flush_f,
                dut.id_branch_taken, dut.if_id_instr);
        end
    end
endmodule
