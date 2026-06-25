// snake_vga.c — Snake for 80×60 VGA framebuffer
volatile unsigned char * const FB = (unsigned char*)0x40002000;
volatile unsigned int  * const UART_RX     = (unsigned int*)0x40000004;
volatile unsigned int  * const UART_STATUS = (unsigned int*)0x40000008;
volatile unsigned int  * const UART_BAUD   = (unsigned int*)0x4000000C;

#define W 40
#define H 30
#define FW 80    // actual framebuffer stride
#define MAX_LEN 200

#define BLACK   0x00
#define WHITE   0xFF
#define RED     0xE0
#define GREEN   0x1C
#define YELLOW  0xFC

int sx[MAX_LEN], sy[MAX_LEN];
int len, dx, dy, fx, fy, score, over;
unsigned int rng = 12345;
int my_rand(void) { rng = rng * 1103515245 + 12345; return (rng >> 16) & 0x7FFF; }

void draw_pixel(int x, int y, unsigned char c) {
    if ((unsigned)x < W && (unsigned)y < H) FB[y * FW + x] = c;
}
unsigned char uart_getc(void) { while (!(*UART_STATUS & 2)); return *UART_RX & 0xFF; }
int uart_kbhit(void) { return (*UART_STATUS & 2) != 0; }

void draw_border(void) {
    volatile unsigned char *top = FB, *bot = FB + (H-1)*FW;
    for (int x = 0; x < W; x++) { top[x] = WHITE; bot[x] = WHITE; }
    for (int y = 1; y < H-1; y++) { FB[y*FW+0] = WHITE; FB[y*FW+W-1] = WHITE; }
}
void init_game(void) {
    draw_border();
    len = 5; dx = 1; dy = 0; score = 0; over = 0;
    for (int i = 0; i < len; i++) { sx[i] = 10 - i; sy[i] = H/2; }
    fx = 20; fy = 20;
}

int main(void) {
    *UART_BAUD = 20;
    init_game();

    while (!over) {
        // Clear snake trail
        for (int i = 0; i < len; i++) FB[sy[i]*FW + sx[i]] = BLACK;

        // Input
        while (uart_kbhit()) {
            char k = uart_getc();
            if (k == 'w' && dy != 1)  { dx = 0; dy = -1; }
            if (k == 's' && dy != -1) { dx = 0; dy = 1; }
            if (k == 'a' && dx != 1)  { dx = -1; dy = 0; }
            if (k == 'd' && dx != -1) { dx = 1; dy = 0; }
            if (k == 'q') over = 1;
        }

        int nx = sx[0] + dx, ny = sy[0] + dy;

        // Collision: wall or self
        if ((unsigned)nx >= W || (unsigned)ny >= H) { over = 1; break; }
        for (int i = 1; i < len; i++)
            if (sx[i] == nx && sy[i] == ny) { over = 1; break; }
        if (over) break;

        int ate = (nx == fx && ny == fy);

        // Shift body (from tail to head)
        for (int i = len - 1; i > 0; i--) { sx[i] = sx[i-1]; sy[i] = sy[i-1]; }
        sx[0] = nx; sy[0] = ny;

        if (ate) {
            if (len < MAX_LEN) len++;
            score += 10;
            fx = 5 + (my_rand() % (W-10));
            fy = 5 + (my_rand() % (H-10));
        }

        // Draw food, snake
        FB[fy*FW + fx] = RED;
        for (int i = 0; i < len; i++)
            FB[sy[i]*FW + sx[i]] = (i == 0) ? YELLOW : GREEN;

        // Delay
        for (volatile int d = 0; d < 1500; d++);
    }

    // Game over: flash RED-BLACK-RED
    for (int f = 0; f < 2; f++) {
        for (int y = 1; y < H-1; y++)
            for (int x = 1; x < W-1; x++)
                FB[y*FW + x] = RED;
        for (volatile int d = 0; d < 5000; d++);
        for (int y = 1; y < H-1; y++)
            for (int x = 1; x < W-1; x++)
                FB[y*FW + x] = BLACK;
        for (volatile int d = 0; d < 3000; d++);
    }
    for (int y = 1; y < H-1; y++)
        for (int x = 1; x < W-1; x++)
            FB[y*FW + x] = RED;

    while (1);
    return 0;
}
