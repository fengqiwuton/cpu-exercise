// snake_vga.c — Snake game with VGA framebuffer output
// Display: 80×60 pixel VGA (each pixel = 1 byte color)
// Input: UART RX (simulation) or PS/2 keyboard (hardware)
// Framebuffer: 0x40002000, UART: 0x40000000

volatile unsigned char * const FB = (unsigned char*)0x40002000;
volatile unsigned int  * const UART_RX     = (unsigned int*)0x40000004;
volatile unsigned int  * const UART_STATUS = (unsigned int*)0x40000008;
volatile unsigned int  * const UART_BAUD   = (unsigned int*)0x4000000C;

#define W 40
#define H 30
#define MAX_LEN 200

// Colors (RRRGGGBB)
#define BLACK   0x00
#define WHITE   0xFF
#define RED     0xE0
#define GREEN   0x1C
#define BLUE    0x03
#define YELLOW  0xFC
#define GRAY    0x92

int sx[MAX_LEN], sy[MAX_LEN];
int len, dx, dy, fx, fy, score, game_over;
unsigned int rng_state = 12345;

int my_rand(void) {
    rng_state = rng_state * 1103515245 + 12345;
    return (rng_state >> 16) & 0x7FFF;
}

void draw_pixel(int x, int y, unsigned char color) {
    if (x >= 0 && x < W && y >= 0 && y < H)
        FB[y * W + x] = color;
}

void draw_rect(int x, int y, int w, int h, unsigned char color) {
    for (int i = 0; i < h; i++)
        for (int j = 0; j < w; j++)
            draw_pixel(x + j, y + i, color);
}

void clear_screen(void) {
    for (int i = 0; i < W * H; i++) FB[i] = BLACK;
}

void draw_border(void) {
    draw_rect(0, 0, W, 1, WHITE);      // top
    draw_rect(0, H-1, W, 1, WHITE);    // bottom
    draw_rect(0, 0, 1, H, WHITE);      // left
    draw_rect(W-1, 0, 1, H, WHITE);    // right
}

void draw_snake(void) {
    for (int i = 0; i < len; i++) {
        unsigned char c = (i == 0) ? YELLOW : GREEN;
        draw_pixel(sx[i], sy[i], c);
    }
}

void draw_food(void) { draw_pixel(fx, fy, RED); }

void draw_score(void) {
    // Draw score as binary dots on the border
    int s = score;
    for (int i = 0; i < 8 && i + 2 < W; i++) {
        if (s & (1 << i))
            draw_pixel(2 + i, 0, YELLOW);
    }
}

unsigned char uart_getc(void) {
    while (!(*UART_STATUS & 2));
    return (unsigned char)(*UART_RX & 0xFF);
}

int uart_kbhit(void) { return (*UART_STATUS & 2) != 0; }

void init_game(void) {
    clear_screen();
    draw_border();
    len = 5;
    for (int i = 0; i < len; i++) { sx[i] = W/2 - i; sy[i] = H/2; }
    dx = 1; dy = 0;
    score = 0;
    game_over = 0;
    fx = 3 + (my_rand() % (W - 6));
    fy = 3 + (my_rand() % (H - 6));
}

void place_food(void) {
    int ok;
    do {
        fx = 3 + (my_rand() % (W - 6));
        fy = 3 + (my_rand() % (H - 6));
        ok = 1;
        for (int i = 0; i < len; i++)
            if (sx[i] == fx && sy[i] == fy) ok = 0;
    } while (!ok);
}

void game_over_screen(void) {
    clear_screen();
    draw_border();
    // Flash red
    for (int i = 0; i < 3; i++) {
        draw_rect(1, 1, W-2, H-2, RED);
        for (volatile int d = 0; d < 2000; d++);
        draw_rect(1, 1, W-2, H-2, BLACK);
        for (volatile int d = 0; d < 2000; d++);
    }
    draw_rect(1, 1, W-2, H-2, RED);
}

void game_loop(void) {
    unsigned char key;

    while (!game_over) {
        // Clear snake trail
        for (int i = 0; i < len; i++)
            draw_pixel(sx[i], sy[i], BLACK);

        // Redraw border (snake may have touched it)
        draw_border();

        // Check input
        while (uart_kbhit()) {
            key = uart_getc();
            if (key == 'w' && dy != 1)  { dx = 0; dy = -1; }
            if (key == 's' && dy != -1) { dx = 0; dy = 1; }
            if (key == 'a' && dx != 1)  { dx = -1; dy = 0; }
            if (key == 'd' && dx != -1) { dx = 1; dy = 0; }
            if (key == 'q') { game_over = 1; }
        }

        // Move head
        int nx = sx[0] + dx;
        int ny = sy[0] + dy;

        // Collision: wall
        if (nx <= 0 || nx >= W-1 || ny <= 0 || ny >= H-1) {
            game_over = 1; break;
        }

        // Collision: self
        for (int i = 1; i < len; i++)
            if (sx[i] == nx && sy[i] == ny) { game_over = 1; break; }
        if (game_over) break;

        // Check food
        int ate = (nx == fx && ny == fy);

        // Shift body
        for (int i = len; i > 0; i--) {
            sx[i] = sx[i-1]; sy[i] = sy[i-1];
        }
        sx[0] = nx; sy[0] = ny;

        if (ate) {
            len++;
            score += 10;
            place_food();
            draw_score();
        }

        // Redraw snake and food
        draw_snake();
        draw_food();

        // Game speed delay (fast for sim)
        for (volatile int d = 0; d < 200; d++);
    }
}

int main(void) {
    *UART_BAUD = 5;  // fast for simulation

    init_game();
    game_loop();
    game_over_screen();

    while (1);
    return 0;
}
