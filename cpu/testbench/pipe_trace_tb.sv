`timescale 1ns/1ps

module pipe_trace_tb;
    logic clk, rst_n;
    logic uart_rx_pin = 1'b1;
    pipeline_top dut (.*);

    always #5 clk = ~clk;

    // Trace first 20 cycles
    integer cycle;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle <= 0;
        else cycle <= cycle + 1;
    end

    always_ff @(posedge clk) begin
        if (cycle < 20) begin
            $display("c=%0d: IF(pc=%h,imem=%h) ID(instr=%h) EX(alu=%h,reg_wr=%b) MEM(wr=%b,addr=%h,data=%h) WB(wr=%b,rd=%0d,data=%h)",
                cycle,
                dut.pc, dut.imem_instr,
                dut.if_id_instr,
                dut.ex_alu_result, dut.id_ex_reg_write,
                dut.ex_mem_mem_write, dut.ex_mem_alu_result, dut.ex_mem_rs2_data,
                dut.mem_wb_reg_write, dut.mem_wb_rd,
                dut.mem_wb_mem_to_reg ? dut.mem_wb_mem_data : dut.mem_wb_alu_result
            );
        end
    end

    wire [31:0] wb_data;
    assign wb_data = dut.mem_wb_mem_to_reg ? dut.mem_wb_mem_data : dut.mem_wb_alu_result;

    initial begin
        $dumpfile("pipe_trace.vcd");
        $dumpvars(0, pipe_trace_tb);
        clk = 0; rst_n = 0;
        #20 rst_n = 1;
        #5000;
        $display("=== Final data_mem ===");
        $display("mem[4]=%h (expect 63=99)", dut.u_data_mem.mem[4]);
        $display("mem[5]=%h (expect 2a=42)", dut.u_data_mem.mem[5]);
        $display("pipe_trace_tb: done");
        $finish;
    end
endmodule
