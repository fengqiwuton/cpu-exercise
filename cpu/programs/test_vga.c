// test_vga.c — minimal VGA framebuffer test: draw colored rectangles
volatile unsigned char * const FB = (unsigned char*)0x40002000;

void draw_pixel(int x, int y, unsigned char c) { FB[y*80 + x] = c; }

void draw_rect(int x, int y, int w, int h, unsigned char c) {
    for (int i = 0; i < h; i++)
        for (int j = 0; j < w; j++)
            draw_pixel(x+j, y+i, c);
}

int main(void) {
    // Top-left: red rectangle
    draw_rect(0, 0, 10, 10, 0xE0);     // red
    // Top-right: green
    draw_rect(70, 0, 10, 10, 0x1C);     // green
    // Bottom-left: blue
    draw_rect(0, 50, 10, 10, 0x03);     // blue
    // Bottom-right: white
    draw_rect(70, 50, 10, 10, 0xFF);    // white
    // Center: yellow cross
    draw_rect(38, 25, 4, 10, 0xFC);     // vertical
    draw_rect(30, 28, 20, 4, 0xFC);     // horizontal

    while (1);
    return 0;
}
