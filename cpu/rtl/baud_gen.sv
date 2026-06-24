// Baud rate generator: produces a tick every (clk_freq / baud) cycles
// Default: 50MHz / 115200 = ~434, tick = 1 cycle per bit
module baud_gen #(
    parameter CLK_FREQ = 50_000_000,
    parameter DEFAULT_BAUD = 115200
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] baud_div,   // programmable: clk_freq / desired_baud
    output logic        tick         // 1-cycle pulse at baud rate
);
    localparam DEFAULT_DIV = CLK_FREQ / DEFAULT_BAUD;
    logic [15:0] counter;
    logic [15:0] divisor;

    assign divisor = (baud_div == 16'd0) ? DEFAULT_DIV : baud_div;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 16'd0;
            tick    <= 1'b0;
        end else begin
            if (counter >= divisor - 1) begin
                counter <= 16'd0;
                tick    <= 1'b1;
            end else begin
                counter <= counter + 16'd1;
                tick    <= 1'b0;
            end
        end
    end
endmodule
