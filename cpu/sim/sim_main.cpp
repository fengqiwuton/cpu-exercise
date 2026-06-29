// Verilator harness for MineCPU — direct byte output (no UART bit decode)
// Keyboard → UART RX pin → CPU → UART TX byte → printf
#include "Vcpu_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>

static const int BAUD = 20;

// ── Terminal: non-blocking input ────────────────────────────
static struct termios orig;
void term_raw() {
    tcgetattr(STDIN_FILENO, &orig);
    struct termios r = orig;
    r.c_lflag &= ~((unsigned)(ICANON | ECHO));
    tcsetattr(STDIN_FILENO, TCSANOW, &r);
    fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
}
void term_restore() { tcsetattr(STDIN_FILENO, TCSANOW, &orig); }

// ── Key injector: serializes byte to UART rx_pin ────────────
struct KeyInj {
    uint8_t b; int bit, cyc; bool act;
    KeyInj() : b(0),bit(0),cyc(0),act(false) {}
    void send(uint8_t c) { b=c; bit=0; cyc=0; act=true; }
    bool busy() { return act; }
    int next() {
        if (!act) return 1;
        cyc++;
        if (cyc >= BAUD) { cyc=0; bit++; }
        if (bit==0) return 0;
        if (bit<=8) return (b>>(bit-1))&1;
        act=false; return 1;
    }
};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vcpu_top *top = new Vcpu_top;
    KeyInj inj;

    // Reset
    top->clk=0; top->rst_n=0; top->uart_rx_pin=1;
    top->eval(); top->clk=1; top->eval(); top->clk=0; top->eval();
    top->rst_n=1;

    term_raw();
    printf("\033[2J\033[H");  // clear terminal
    printf("=== MineCPU Snake ===\nWASD move, Q quit\n\n");

    int idle = 0, prev_strobe = 0;
    for (int cyc = 0; cyc < 8000000; cyc++) {
        // Keyboard → UART RX (with spacing)
        if (!inj.busy() && idle <= 0) {
            char c;
            if (read(STDIN_FILENO, &c, 1) > 0) {
                inj.send((uint8_t)c);
                idle = 4000;
            }
        }
        if (idle > 0) idle--;

        top->uart_rx_pin = inj.next();
        top->clk = 1; top->eval();

        // Direct byte output from UART (no bit decode needed!)
        if (top->uart_tx_strobe && !prev_strobe) {
            printf("%c", (char)top->uart_tx_byte);
            fflush(stdout);
        }
        prev_strobe = top->uart_tx_strobe;

        top->clk = 0; top->eval();
    }

    term_restore();
    printf("\nDone.\n");
    top->final(); delete top;
    return 0;
}
