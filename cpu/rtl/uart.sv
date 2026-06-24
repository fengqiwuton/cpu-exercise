// UART 16550-style: TX + RX, 8N1, programmable baud
// MMIO registers at offsets 0x00-0x0C (relative to base 0x4000_0000)
//
// In simulation: TX prints to console, RX reads from uart_rx.dat file
module uart #(
    parameter CLK_FREQ = 50_000_000,
    parameter DEFAULT_BAUD = 115200
) (
    input  logic        clk,
    input  logic        rst_n,

    // CPU bus interface
    input  logic        cs,             // chip select
    input  logic [3:0]  addr,           // byte offset within UART space (0x00-0x0C)
    input  logic [31:0] write_data,
    input  logic        mem_write,
    input  logic [3:0]  byte_enable,    // only byte 0 used
    output logic [31:0] read_data,

    // Physical UART pins (for real hardware)
    output logic        tx_pin,
    input  logic        rx_pin         // In sim: tied to 1 (idle)
);
    // Internal registers
    logic [7:0]  tx_reg;
    logic [7:0]  rx_reg;
    logic [7:0]  status_reg;    // bit0=tx_busy, bit1=rx_ready
    logic [15:0] baud_div_reg;

    // TX state machine
    typedef enum logic [3:0] {
        TX_IDLE, TX_START, TX_BIT0, TX_BIT1, TX_BIT2, TX_BIT3,
        TX_BIT4, TX_BIT5, TX_BIT6, TX_BIT7, TX_STOP
    } tx_state_t;
    tx_state_t tx_state;
    logic [7:0] tx_shift;
    logic       tx_busy;

    // RX state machine (simplified: self-synchronized counter)
    typedef enum logic { RX_IDLE, RX_DATA } rx_state_t;
    rx_state_t rx_state;
    logic       rx_prev;
    logic [7:0] rx_shift;
    logic [3:0] rx_bit_cnt;       // 0=start, 1-8=data, 9=stop
    logic [15:0] rx_counter;      // free-running bit-period counter
    logic       rx_ready;

    // Baud tick
    logic baud_tick;
    baud_gen #(.CLK_FREQ(CLK_FREQ)) u_baud (
        .clk, .rst_n,
        .baud_div(baud_div_reg),
        .tick(baud_tick)
    );

    // ── TX ──────────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_pin   <= 1'b1;     // idle high
            tx_busy  <= 1'b0;
            tx_shift <= 8'd0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_pin  <= 1'b1;
                    tx_busy <= 1'b0;
                    // Start TX when CPU writes to TX register (addr=0, byte 0)
                    if (mem_write && addr == 4'h0 && byte_enable[0]) begin
                        tx_shift <= write_data[7:0];
                        tx_state <= TX_START;
                        tx_busy  <= 1'b1;
                    end
                end

                TX_START: if (baud_tick) begin tx_pin <= 1'b0; tx_state <= TX_BIT0; end
                TX_BIT0:  if (baud_tick) begin tx_pin <= tx_shift[0]; tx_state <= TX_BIT1; end
                TX_BIT1:  if (baud_tick) begin tx_pin <= tx_shift[1]; tx_state <= TX_BIT2; end
                TX_BIT2:  if (baud_tick) begin tx_pin <= tx_shift[2]; tx_state <= TX_BIT3; end
                TX_BIT3:  if (baud_tick) begin tx_pin <= tx_shift[3]; tx_state <= TX_BIT4; end
                TX_BIT4:  if (baud_tick) begin tx_pin <= tx_shift[4]; tx_state <= TX_BIT5; end
                TX_BIT5:  if (baud_tick) begin tx_pin <= tx_shift[5]; tx_state <= TX_BIT6; end
                TX_BIT6:  if (baud_tick) begin tx_pin <= tx_shift[6]; tx_state <= TX_BIT7; end
                TX_BIT7:  if (baud_tick) begin tx_pin <= tx_shift[7]; tx_state <= TX_STOP; end
                TX_STOP:  if (baud_tick) begin tx_pin <= 1'b1; tx_state <= TX_IDLE; end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // Simulation: print TX byte, log RX receipt
    `ifdef SIMULATION
    always_ff @(posedge clk) begin
        if (tx_state == TX_STOP && baud_tick)
            $write("%c", tx_shift);
    end
    wire rx_done_sim;
    assign rx_done_sim = (rx_state == RX_DATA) && (rx_bit_cnt == 4'd9)
                         && (rx_counter == baud_div_2 + 9 * baud_div_reg);
    always_ff @(posedge clk) begin
        if (rx_done_sim)
            $write("[RX:'%c']", rx_shift);
    end
    `endif

    // ── RX: free-running counter, samples at bit center ────
    wire [15:0] baud_div_2;
    assign baud_div_2 = (baud_div_reg == 0) ? (CLK_FREQ / DEFAULT_BAUD / 2) : (baud_div_reg >> 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state    <= RX_IDLE;
            rx_prev     <= 1'b1;
            rx_ready    <= 1'b0;
            rx_reg      <= 8'd0;
            rx_shift    <= 8'd0;
            rx_bit_cnt  <= 3'd0;
            rx_counter  <= 16'd0;
        end else begin
            rx_prev <= rx_pin;

            if (cs && !mem_write && addr == 4'h4)
                rx_ready <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (rx_prev == 1'b1 && rx_pin == 1'b0) begin
                        rx_state   <= RX_DATA;
                        rx_bit_cnt <= 3'd0;
                        rx_counter <= 16'd0;
                    end
                end

                RX_DATA: begin
                    rx_counter <= rx_counter + 1;
                    // Sample at center of each bit: offset = baud_div/2, period = baud_div
                    // bit N center = baud_div_2 + N * baud_div_reg
                    if (rx_counter == baud_div_2 + rx_bit_cnt * baud_div_reg) begin
                        if (rx_bit_cnt == 0) begin
                            // start bit: should be 0; if not, false start
                            if (rx_pin != 1'b0)
                                rx_state <= RX_IDLE;
                        end else if (rx_bit_cnt <= 8) begin
                            // data bits 0-7
                            rx_shift[rx_bit_cnt - 1] <= rx_pin;
                        end else begin
                            // stop bit
                            if (rx_pin == 1'b1) begin
                                rx_reg   <= rx_shift;
                                rx_ready <= 1'b1;
                            end
                            rx_state <= RX_IDLE;
                        end
                        if (rx_bit_cnt < 9)
                            rx_bit_cnt <= rx_bit_cnt + 1;
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // ── Register reads ─────────────────────────────────────
    assign status_reg = {6'b0, rx_ready, tx_busy};

    always_comb begin
        read_data = 32'd0;
        if (cs && !mem_write) begin  // read
            case (addr)
                4'h0: read_data = {24'd0, tx_reg};
                4'h4: read_data = {24'd0, rx_reg};
                4'h8: read_data = {24'd0, status_reg};
                4'hC: read_data = {16'd0, baud_div_reg};
                default: read_data = 32'd0;
            endcase
        end
    end

    // Baud rate register write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_div_reg <= 16'd0;  // 0 = use default
        end else if (mem_write && addr == 4'hC && byte_enable[0]) begin
            baud_div_reg <= write_data[15:0];
        end
    end

endmodule
