// timer.sv — programmable interval timer with IRQ output
// MMIO: 0x40000040 (control/status), 0x40000044 (compare value)
// Control bits: [0]=enable, [1]=clear_irq(write-1), [0]=irq_flag(read)
module timer #(
    parameter CLK_FREQ = 50_000_000
) (
    input  logic        clk, rst_n,
    input  logic        cs,
    input  logic [31:0] addr,
    input  logic [31:0] write_data,
    input  logic        mem_write,
    output logic [31:0] read_data,
    output logic        irq
);
    logic [31:0] compare;
    logic [31:0] counter;
    logic        enabled;
    logic        irq_flag;

    assign irq = irq_flag;

    // Read
    always_comb begin
        if (cs && !mem_write)
            read_data = addr[2] ? compare : {30'b0, irq_flag, enabled};
        else
            read_data = 0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compare  <= 32'd50000;   // ~1ms at 50MHz
            counter  <= 0;
            enabled  <= 0;
            irq_flag <= 0;
        end else begin
            if (cs && mem_write) begin
                if (addr[2])
                    compare <= write_data;           // set interval
                else begin
                    enabled  <= write_data[0];       // enable bit
                    if (write_data[1])               // clear IRQ
                        irq_flag <= 0;
                end
            end

            if (enabled) begin
                if (counter >= compare) begin
                    counter  <= 0;
                    irq_flag <= 1;
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end
endmodule
