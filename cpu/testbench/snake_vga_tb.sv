`timescale 1ns/1ps

module snake_vga_tb;
    localparam BAUD = 5;
    localparam IDLE = 20000;
    localparam W = 80;
    localparam H = 60;

    logic clk, rst_n;
    logic uart_rx_pin;
    cpu_top dut (.*);

    // Key injection (UART RX)
    reg [7:0] key_buf [0:255];
    integer   key_count, key_idx;
    reg       injecting;
    integer   bit_cyc, idle_cyc;

    always #5 clk = ~clk;

    initial begin
        // Snake demo: right, down, left, up, quit
        key_buf[0]="d";key_buf[1]="d";key_buf[2]="d";key_buf[3]="d";key_buf[4]="d";
        key_buf[5]="s";key_buf[6]="s";key_buf[7]="s";
        key_buf[8]="a";key_buf[9]="a";key_buf[10]="a";
        key_buf[11]="w";key_buf[12]="w";key_buf[13]="w";
        key_buf[14]="d";key_buf[15]="d";
        key_buf[16]="s";key_buf[17]="s";
        key_buf[18]="q";
        key_count = 19;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            injecting <= 0; bit_cyc <= 0; key_idx <= 0;
            uart_rx_pin <= 1'b1; idle_cyc <= IDLE * 5;
        end else begin
            if (!injecting) begin
                uart_rx_pin <= 1'b1;
                if (idle_cyc > 0) begin
                    idle_cyc <= idle_cyc - 1;
                end else if (key_idx < key_count) begin
                    injecting <= 1; bit_cyc <= 0;
                end
            end else begin
                bit_cyc <= bit_cyc + 1;
                if (bit_cyc < BAUD)
                    uart_rx_pin <= 1'b0;
                else if (bit_cyc < BAUD * 9)
                    uart_rx_pin <= key_buf[key_idx][(bit_cyc/BAUD) - 1];
                else if (bit_cyc < BAUD * 10)
                    uart_rx_pin <= 1'b1;
                else begin
                    key_idx <= key_idx + 1;
                    if (key_idx + 1 >= key_count) begin
                        injecting <= 0; idle_cyc <= IDLE;
                    end else bit_cyc <= 0;
                end
            end
        end
    end

    integer nz, i;

    // Check framebuffer after simulation
    initial begin
        $dumpfile("snake_vga.vcd");
        $dumpvars(0, snake_vga_tb);
        clk = 0; rst_n = 0; uart_rx_pin = 1'b1;
        #20 rst_n = 1;
        #5000000;  // 5M ns = 500K cycles

        $display("=== VGA Framebuffer Check ===");
        // Check border (top-left corner should be white)
        $display("FB[0]=%h (expect FF=white)", dut.u_vga.fb[0]);
        $display("FB[%0d]=%h (expect FF=white)", 79, dut.u_vga.fb[79]);
        $display("FB[%0d]=%h (expect FF=white)", 80, dut.u_vga.fb[80]);

        // Count non-black pixels
        nz = 0;
        for (i = 0; i < 4800; i = i + 1)
            if (dut.u_vga.fb[i] != 8'h00) nz = nz + 1;
        $display("Non-black pixels: %0d (expect >%0d)", nz, W*2 + H*2);
        if (nz > W*2 + H*2)
            $display("  PASS: VGA framebuffer has game content");
        else
            $display("  FAIL: VGA framebuffer may be empty");

        $display("snake_vga_tb: done");
        $finish;
    end
endmodule
