// snake.c — Snake game for MineCPU (UART TX for display, RX for input)
// ANSI terminal: \e[2J clear, \e[H home, \e[?25l hide cursor

volatile unsigned int * const UART_TX     = (unsigned int*)0x40000000;
volatile unsigned int * const UART_RX     = (unsigned int*)0x40000004;
volatile unsigned int * const UART_STATUS = (unsigned int*)0x40000008;
volatile unsigned int * const UART_BAUD   = (unsigned int*)0x4000000C;

#define W 16
#define H 8
#define MAX_LEN 200

char grid[H][W];       // screen buffer
int sx[MAX_LEN];       // snake body X
int sy[MAX_LEN];       // snake body Y
int len;               // current length
int dx, dy;            // direction
int fx, fy;            // food position
int score;
int game_over;

void uart_putc(char c) {
    while (*UART_STATUS & 1);
    *UART_TX = c;
}

void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

void uart_print_num(int n) {
    if (n < 0) { uart_putc('-'); n = -n; }
    if (n >= 10) uart_print_num(n / 10);
    uart_putc('0' + n % 10);
}

// Simple PRNG (LCG)
unsigned int rng_state = 12345;
int my_rand(void) {
    rng_state = rng_state * 1103515245 + 12345;
    return (rng_state >> 16) & 0x7FFF;
}

int abs(int x) { return x < 0 ? -x : x; }

void delay(int n) {
    // busy-wait: ~n iterations
    volatile int i;
    for (i = 0; i < n * 200; i++);
}

char uart_getc(void) {
    // Wait for RX data
    while (!(*UART_STATUS & 2));
    return (char)(*UART_RX & 0xFF);
}

int uart_kbhit(void) {
    return (*UART_STATUS & 2) != 0;
}

void init_game(void) {
    int i, j;
    // Clear grid
    for (i = 0; i < H; i++)
        for (j = 0; j < W; j++)
            grid[i][j] = ' ';

    // Draw border
    for (j = 0; j < W; j++) { grid[0][j] = '#'; grid[H-1][j] = '#'; }
    for (i = 0; i < H; i++) { grid[i][0] = '#'; grid[i][W-1] = '#'; }

    // Snake starts at center, moving right
    len = 3;
    for (i = 0; i < len; i++) { sx[i] = 3 - i; sy[i] = H/2; }
    // Snake starts at left side (x=3), moving right
    dx = 1; dy = 0;
    score = 0;
    game_over = 0;

    // Place first food
    fx = 3 + (my_rand() % (W - 6));
    fy = 3 + (my_rand() % (H - 6));
}

void place_food(void) {
    do {
        fx = 3 + (my_rand() % (W - 6));
        fy = 3 + (my_rand() % (H - 6));
    } while (grid[fy][fx] != ' ');
}

void draw(void) {
    int i, j;
    // Place snake body on grid
    for (i = 0; i < len; i++)
        grid[sy[i]][sx[i]] = (i == 0) ? 'O' : 'o';

    // Place food
    if (!game_over) grid[fy][fx] = '@';

    // Clear grid after drawing (for next frame)
    // Actually we need to clear old positions first
    // This is handled by redrawing each frame

    // ANSI: move cursor to home
    uart_puts("\e[H");

    // Draw score
    uart_puts("Score: ");
    uart_print_num(score);
    uart_puts("  WASD: move  Q: quit\n");

    // Draw grid
    for (i = 0; i < H; i++) {
        for (j = 0; j < W; j++)
            uart_putc(grid[i][j]);
        uart_putc('\n');
    }
    uart_puts("\e[?25l");  // hide cursor
}

void game_loop(void) {
    char key;

    while (!game_over) {
        draw();

        // Check for keyboard input (non-blocking)
        int moved = 0;
        while (uart_kbhit()) {
            key = uart_getc();
            moved = 1;

            if (key == 'w' && dy != 1)  { dx = 0; dy = -1; }
            if (key == 's' && dy != -1) { dx = 0; dy = 1; }
            if (key == 'a' && dx != 1)  { dx = -1; dy = 0; }
            if (key == 'd' && dx != -1) { dx = 1; dy = 0; }
            if (key == 'q') { game_over = 1; return; }
        }

        // Clear old snake from grid
        int i;
        for (i = 0; i < len; i++)
            grid[sy[i]][sx[i]] = ' ';

        // Move snake
        int nx = sx[0] + dx;
        int ny = sy[0] + dy;

        // Collision detection
        if (grid[ny][nx] == '#' || grid[ny][nx] == 'o') {
            game_over = 1;
            grid[ny][nx] = 'X';
            draw();
            uart_puts("\nGame Over! Final Score: ");
            uart_print_num(score);
            uart_puts("\n");
            return;
        }

        // Check food
        int ate = (nx == fx && ny == fy);

        // Move body
        for (i = len; i > 0; i--) {
            sx[i] = sx[i-1];
            sy[i] = sy[i-1];
        }
        sx[0] = nx;
        sy[0] = ny;

        if (ate) {
            len++;
            score += 10;
            place_food();
        }

        // Small delay (adjust for game speed)
        delay(1);
        if (!moved) delay(3);  // faster with input
    }
}

int main(void) {
    *UART_BAUD = 20;  // more margin for RX sampling

    // Hide cursor, clear screen
    uart_puts("\e[?25l\e[2J");

    init_game();

    uart_puts("\n*** Snake for MineCPU ***\n");
    uart_puts("WASD to move, Q to quit\n");
    uart_puts("Press any key to start...\n");

    // Auto-start (skip waiting for first key)

    game_loop();

    // Show cursor again
    uart_puts("\e[?25h\n");
    return 0;
}
