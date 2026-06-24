// PS/2 keyboard interface — receives scan codes, exposes via MMIO
// MMIO: read 0x40000030 = scan_code (bits 7:0), write any to clear
//        read 0x40000034 = status (bit 0 = data_ready)
// PS/2 protocol: 1 start(0) + 8 data(LSB) + 1 parity(odd) + 1 stop(1)
module ps2_kbd (
    input  logic        clk,
    input  logic        rst_n,

    // PS/2 pins
    input  logic        ps2_clk,
    input  logic        ps2_data,

    // CPU bus (MMIO at 0x4000_003x)
    input  logic        cs,
    input  logic [3:0]  addr,         // offset within PS/2 space (0 or 4)
    input  logic        mem_write,
    output logic [31:0] read_data
);
    // ── PS/2 clock edge detection ──────────────────────────
    logic [2:0] ps2_clk_sync;  // synchronizer
    logic       ps2_clk_fall;  // falling edge detect

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ps2_clk_sync  <= 3'b111;
            ps2_clk_fall  <= 1'b0;
        end else begin
            ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};
            ps2_clk_fall <= (ps2_clk_sync[2:1] == 2'b10); // 1→0
        end
    end

    // ── Shift register ─────────────────────────────────────
    logic [3:0]  bit_cnt;    // 0-10
    logic [10:0] shift_reg;  // start(0) + 8 data + parity + stop
    logic [7:0]  scan_code;
    logic        data_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt    <= 0;
            shift_reg  <= 0;
            scan_code  <= 0;
            data_ready <= 0;
        end else begin
            // Clear on read
            if (cs && !mem_write && addr == 4'h0)
                data_ready <= 0;

            if (ps2_clk_fall) begin
                if (bit_cnt == 0) begin
                    // Start bit — should be 0
                    if (ps2_data == 1'b0) begin
                        shift_reg <= {ps2_data, shift_reg[10:1]};
                        bit_cnt  <= 1;
                    end
                end else if (bit_cnt < 10) begin
                    // Data bits 0-7 + parity
                    shift_reg <= {ps2_data, shift_reg[10:1]};
                    bit_cnt   <= bit_cnt + 1;
                end else begin
                    // Stop bit
                    if (ps2_data == 1'b1) begin
                        scan_code  <= shift_reg[8:1];  // skip start bit
                        data_ready <= 1;
                    end
                    bit_cnt <= 0;
                end
            end
        end
    end

    // ── MMIO read ───────────────────────────────────────────
    assign read_data = (addr == 4'h0) ? {24'd0, scan_code} :
                       {31'd0, data_ready};
endmodule
