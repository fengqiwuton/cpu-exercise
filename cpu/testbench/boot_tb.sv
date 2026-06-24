`timescale 1ns/1ps

// Bootloader testbench: injects program binary via UART RX, bootloader loads it
module boot_tb;
    localparam BAUD   = 10;    // bit period in cycles
    localparam IDLE   = 2000;  // idle between bytes

    logic clk, rst_n;
    logic uart_rx_pin;
    cpu_top dut (.*);

    // Program binary bytes
    reg [7:0] prog_bytes [0:16383];
    integer   prog_len;        // number of bytes
    integer   byte_idx;
    reg       injecting;
    integer   bit_cyc;         // cycle within current bit
    integer   idle_cyc;
    integer   fd, tmp;

    always #5 clk = ~clk;

    // Load program binary
    initial begin
        // Default: minimal test program at 0x1000 (just prints 'OK\n')
        // addi x10,x0,79; addi x11,x0,75; lui x12,0x40000; ...
        // For now, load from file
        fd = $fopen("prog.bin", "rb");
        if (fd) begin
            prog_len = 0;
            while (!$feof(fd) && prog_len < 16384) begin
                tmp = $fgetc(fd);
                if (tmp >= 0) begin
                    prog_bytes[prog_len] = tmp[7:0];
                    prog_len = prog_len + 1;
                end
            end
            $fclose(fd);
            $display("boot_tb: loaded %0d bytes from prog.bin", prog_len);
        end else begin
            $display("boot_tb: no prog.bin found — exiting");
            $finish;
        end
    end

    // Serial byte injector — each bit lasts BAUD cycles
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            injecting <= 0;
            bit_cyc   <= 0;
            byte_idx  <= 0;
            uart_rx_pin <= 1'b1;
            idle_cyc    <= IDLE * 5;
        end else begin
            if (!injecting) begin
                uart_rx_pin <= 1'b1;
                if (idle_cyc > 0) begin
                    idle_cyc <= idle_cyc - 1;
                end else if (byte_idx < prog_len) begin
                    injecting <= 1;
                    bit_cyc   <= 0;
                end
            end else begin
                bit_cyc <= bit_cyc + 1;
                // bit_cyc / BAUD: 0=start, 1-8=data, 9=stop, 10=done
                if (bit_cyc < BAUD)
                    uart_rx_pin <= 1'b0;  // start bit
                else if (bit_cyc < BAUD * 9)
                    uart_rx_pin <= prog_bytes[byte_idx][(bit_cyc/BAUD) - 1];
                else if (bit_cyc < BAUD * 10)
                    uart_rx_pin <= 1'b1;  // stop bit
                else begin
                    byte_idx <= byte_idx + 1;
                    if (byte_idx + 1 >= prog_len) begin
                        injecting <= 0;
                        idle_cyc <= IDLE;
                    end else begin
                        bit_cyc <= 0;  // next byte
                    end
                end
            end
        end
    end

    initial begin
        $dumpfile("boot.vcd");
        $dumpvars(0, boot_tb);
        clk = 0; rst_n = 0; uart_rx_pin = 1'b1;
        #20 rst_n = 1;
        #10000000;
        $display("boot_tb: done");
        $finish;
    end
endmodule
