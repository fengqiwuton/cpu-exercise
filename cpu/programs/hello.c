// hello.c — Bare-metal C for MineCPU
// UART at 0x40000000: TX=0x00, STATUS=0x08 (bit0=tx_busy)

volatile unsigned int * const UART_TX      = (unsigned int*)0x40000000;
volatile unsigned int * const UART_RX      = (unsigned int*)0x40000004;
volatile unsigned int * const UART_STATUS  = (unsigned int*)0x40000008;
volatile unsigned int * const UART_BAUD    = (unsigned int*)0x4000000C;

void uart_putc(char c) {
    while (*UART_STATUS & 1);   // wait for TX not busy
    *UART_TX = c;
}

void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

int main(void) {
    *UART_BAUD = 2;  // fast baud for simulation
    uart_puts("Hello from C on MineCPU!\n");
    return 0;
}
