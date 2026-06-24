`timescale 1ns/1ps

// Snake testbench: injects serial keystrokes into UART RX
module snake_tb;
    localparam BAUD = 20;    // bit period in cycles (matches BAUD_DIV)
    localparam IDLE = 50000; // idle cycles between chars

    logic clk, rst_n;
    logic uart_rx_pin;
    cpu_top dut (.*);

    // Key buffer
    reg [7:0] key_buf [0:1023];
    integer   key_count, key_idx;
    integer   key_fd, key_scan, key_char;

    // Injection state
    reg       active;        // currently sending a byte
    integer   bit_cnt;       // which bit: 0=start, 1-8=data, 9=stop
    integer   cyc_cnt;       // cycles within current bit (0..BAUD-1)
    integer   idle_cnt;      // idle cycles remaining

    always #5 clk = ~clk;

    // Load keys from file or built-in demo
    initial begin
        key_buf[0]="d";key_buf[1]="d";key_buf[2]="d";key_buf[3]="d";
        key_buf[4]="s";key_buf[5]="s";key_buf[6]="s";
        key_buf[7]="a";key_buf[8]="a";
        key_buf[9]="w";key_buf[10]="w";
        key_buf[11]="d";key_buf[12]="d";
        key_buf[13]="s";key_buf[14]="s";
        key_buf[15]="q";
        key_count = 16;
        key_fd = $fopen("keys.txt", "r");
        if (key_fd) begin
            key_count = 0;
            while (!$feof(key_fd) && key_count < 1024) begin
                key_scan = $fscanf(key_fd, "%c", key_char);
                if (key_scan == 1 && key_char > 32)
                    key_buf[key_count++] = key_char[7:0];
            end
            $fclose(key_fd);
            $display("snake_tb: loaded %0d keys from keys.txt", key_count);
        end else
            $display("snake_tb: demo %0d keys", key_count);
    end

    // Key injector — hold each bit for BAUD cycles
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active   <= 0;
            bit_cnt  <= 0;
            cyc_cnt  <= 0;
            key_idx  <= 0;
            idle_cnt <= 0;
            uart_rx_pin <= 1'b1;
            idle_cnt <= IDLE;     // initial delay for CPU to config BAUD
        end else begin
            if (!active) begin
                uart_rx_pin <= 1'b1;
                if (idle_cnt > 0) begin
                    idle_cnt <= idle_cnt - 1;
                end else if (key_idx < key_count) begin
                    active  <= 1;
                    bit_cnt <= 0;
                    cyc_cnt <= 0;
                end
            end else begin
                // Advance cycle counter; change bit when cyc_cnt wraps
                if (cyc_cnt < BAUD - 1) begin
                    cyc_cnt <= cyc_cnt + 1;
                end else begin
                    cyc_cnt <= 0;
                    bit_cnt <= bit_cnt + 1;
                end

                // Set rx_pin based on current bit
                case (bit_cnt)
                    0: uart_rx_pin <= 1'b0;  // start bit
                    1,2,3,4,5,6,7,8: uart_rx_pin <= key_buf[key_idx][bit_cnt-1];
                    9: uart_rx_pin <= 1'b1;  // stop bit
                    default: begin
                        active   <= 0;
                        key_idx  <= key_idx + 1;
                        idle_cnt <= IDLE;
                        uart_rx_pin <= 1'b1;
                    end
                endcase
            end
        end
    end

    initial begin
        $dumpfile("snake.vcd");
        $dumpvars(0, snake_tb);
        clk = 0; rst_n = 0; uart_rx_pin = 1'b1;
        #20 rst_n = 1;
        #15000000;  // enough for 9 keys
        $display("\nsnake_tb: done");
        $finish;
    end
endmodule
