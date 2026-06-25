// VGA Frame Buffer — 80×60 pixels, 8-bit color, 640×480@60Hz
// Pixel clock = clk/4 (25MHz from 100MHz)
// MMIO: CPU writes to 0x40002000 + offset (4800 bytes)
module vga_fb #(
    parameter H_VISIBLE = 640, H_FRONT = 16, H_SYNC = 96, H_BACK = 48,
    parameter V_VISIBLE = 480, V_FRONT = 10, V_SYNC  = 2,  V_BACK  = 33,
    parameter H_TOTAL = 800, V_TOTAL = 525
) (
    input  logic        clk,           // 100 MHz system clock
    input  logic        rst_n,

    // CPU write port
    input  logic        cs,            // chip select (MMIO: 0x40002xxx)
    input  logic [31:0] addr,          // byte offset from VGA base
    input  logic [31:0] write_data,
    input  logic        mem_write,

    // VGA output
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b,
    output logic        vga_hsync,
    output logic        vga_vsync,

    // Debug read port (for Verilator)
    input  logic [12:0] dbg_addr,
    output logic [7:0]  dbg_data
);
    // ── Pixel clock divider (100MHz / 4 = 25MHz) ──────────
    logic [1:0] clk_div;
    logic       pix_clk;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div <= 0;
            pix_clk <= 0;
        end else begin
            clk_div <= clk_div + 1;
            if (clk_div == 2'd0) pix_clk <= 1;
            else pix_clk <= 0;
        end
    end

    // ── Framebuffer: 80×60 × 1 byte = 4800 bytes ──────────
    localparam FB_SIZE = 4800;
    logic [7:0] fb [0:FB_SIZE-1];
    integer     i;

    // CPU write with stride remapping
    // Old game code writes at stride-40 within a 40×30 grid but the
    // framebuffer is 80 wide.  Remap: row*40+col → row*80+col
    // Only remap writes inside the 40×30 logical area (addr < 1200).
    // Writes >= 1200 (e.g. bottom-border at FW=80) pass through unchanged.
    logic [31:0] fb_wr_off;   // zero-extended offset
    logic [31:0] fb_wr_row, fb_wr_col;
    assign fb_wr_off = {19'b0, addr[12:0]};
    assign fb_wr_row = fb_wr_off / 32'd40;
    assign fb_wr_col = fb_wr_off % 32'd40;
    wire [31:0] remap_addr = fb_wr_row * 32'd80 + fb_wr_col;
    wire [12:0] fb_wr_addr = (fb_wr_off < 32'd1200) ? remap_addr[12:0] : addr[12:0];

    always_ff @(posedge clk) begin
        if (cs && mem_write && fb_wr_addr < FB_SIZE)
            fb[fb_wr_addr] <= write_data[7:0];
    end

    // ── VGA timing generation (in pix_clk domain) ──────────
    logic [9:0]  h_cnt;
    logic [9:0]  v_cnt;
    logic        h_visible, v_visible;

    always_ff @(posedge clk) begin
        if (pix_clk) begin
            if (h_cnt < H_TOTAL - 1)
                h_cnt <= h_cnt + 1;
            else begin
                h_cnt <= 0;
                if (v_cnt < V_TOTAL - 1)
                    v_cnt <= v_cnt + 1;
                else
                    v_cnt <= 0;
            end
        end
    end

    assign h_visible = (h_cnt < H_VISIBLE);
    assign v_visible = (v_cnt < V_VISIBLE);
    assign vga_hsync = (h_cnt >= H_VISIBLE + H_FRONT &&
                        h_cnt < H_VISIBLE + H_FRONT + H_SYNC);
    assign vga_vsync = (v_cnt >= V_VISIBLE + V_FRONT &&
                        v_cnt < V_VISIBLE + V_FRONT + V_SYNC);

    // ── Framebuffer read (combinational) ───────────────────
    logic [6:0]  fb_x;  // 0-79
    logic [5:0]  fb_y;  // 0-59
    logic [12:0] fb_addr;
    logic [7:0]  pixel;

    assign fb_x    = h_cnt[9:3];  // h_cnt / 8
    assign fb_y    = v_cnt[9:3];  // v_cnt / 8
    assign fb_addr = fb_y * 80 + fb_x;
    assign pixel   = (fb_addr < FB_SIZE) ? fb[fb_addr] : 8'h00;

    // ── Color output (8-bit → 4-bit per channel) ───────────
    assign vga_r = h_visible && v_visible ? {pixel[7:5], 1'b0} : 4'h0;
    assign vga_g = h_visible && v_visible ? {pixel[4:2], 1'b0} : 4'h0;
    assign vga_b = h_visible && v_visible ? {pixel[1:0], 2'b00} : 4'h0;
    // Debug read port for Verilator
    assign dbg_data = (dbg_addr < FB_SIZE) ? fb[dbg_addr] : 8'h00;

endmodule
