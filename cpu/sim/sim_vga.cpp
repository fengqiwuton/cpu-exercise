// Verilator VGA Snake — SDL2 graphical display (640×480 window)
#include "Vcpu_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <SDL2/SDL.h>

static const int BAUD     = 20;
static const int HW_W     = 80;   // hardware framebuffer stride
static const int GAME_W   = 80;   // full 80-wide framebuffer
static const int GAME_H   = 60;   // full 60-tall framebuffer
static const int SCALE    = 8;    // 80×8=640, 60×8=480
static const int WIN_W    = GAME_W * SCALE;
static const int WIN_H    = GAME_H * SCALE;
static const int BOOT_CYCLES    = 0;      // no separate boot, render from cycle 0
static const int BATCH_CYCLES   = 20000;  // large batch to blast through init

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

// ── Helper: run N CPU cycles ────────────────────────────────
inline void run_cycles(Vcpu_top *top, KeyInj &inj, int n,
                       int &prev_strobe, int check_uart=0) {
    for (int i = 0; i < n; i++) {
        top->uart_rx_pin = inj.next();
        top->clk = 1; top->eval();
        if (check_uart && top->uart_tx_strobe && !prev_strobe) {
            printf("%c", (char)top->uart_tx_byte); fflush(stdout);
        }
        prev_strobe = top->uart_tx_strobe;
        top->clk = 0; top->eval();
    }
}

// ── Helper: read framebuffer into pixel buffer ──────────────
void read_fb(Vcpu_top *top, uint32_t *buf) {
    for (int y = 0; y < GAME_H; y++) {
        for (int x = 0; x < GAME_W; x++) {
            top->vga_dbg_addr = y * HW_W + x; top->eval();
            uint8_t c = top->vga_dbg_data;
            uint32_t r = ((c >> 5) & 7) * 36;
            uint32_t g = ((c >> 2) & 7) * 36;
            uint32_t b = (c & 3) * 85;
            buf[y*GAME_W + x] = 0xFF000000 | (r << 16) | (g << 8) | b;
        }
    }
}

// ── Helper: save framebuffer as BMP for debugging ───────────
void dump_bmp(Vcpu_top *top, const char *fn) {
    int w = GAME_W * 8, h = GAME_H * 8;
    int rp = (w * 3 + 3) & ~3;
    FILE *f = fopen(fn, "wb");
    if (!f) return;
    int fs = 54 + rp * h;
    uint8_t hdr[54]={0};
    hdr[0]='B';hdr[1]='M';*(int*)(hdr+2)=fs;*(int*)(hdr+10)=54;
    *(int*)(hdr+14)=40;*(int*)(hdr+18)=w;*(int*)(hdr+22)=h;
    *(short*)(hdr+26)=1;*(short*)(hdr+28)=24;
    fwrite(hdr,1,54,f);
    uint8_t *row = new uint8_t[rp];
    for(int y=h-1;y>=0;y--){memset(row,0,rp);
        for(int x=0;x<w;x++){
            top->vga_dbg_addr=((h-1-y)/8)*HW_W+(x/8);top->eval();
            uint8_t c=top->vga_dbg_data;
            row[x*3+2]=((c>>5)&7)*36;row[x*3+1]=((c>>2)&7)*36;row[x*3+0]=(c&3)*85;
        }
        fwrite(row,1,rp,f);}
    delete[] row;fclose(f);
    printf("  [debug: %s]\n", fn);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vcpu_top *top = new Vcpu_top;
    KeyInj inj;

    // SDL2 init
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL_Init: %s\n", SDL_GetError()); return 1;
    }
    SDL_Window *win = SDL_CreateWindow("MineCPU VGA Snake",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        WIN_W, WIN_H, SDL_WINDOW_SHOWN);
    SDL_Renderer *ren = SDL_CreateRenderer(win, -1,
        SDL_RENDERER_ACCELERATED);
    SDL_Texture *tex = SDL_CreateTexture(ren,
        SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING,
        GAME_W, GAME_H);

    // Reset CPU
    top->clk=0; top->rst_n=0; top->uart_rx_pin=1; top->vga_dbg_addr=0;
    top->eval(); top->clk=1; top->eval(); top->clk=0; top->eval();
    top->rst_n=1;

    uint32_t fb_pixels[GAME_W * GAME_H];
    int prev_strobe = 0;

    // Boot phase: render as we go so user sees screen appear instantly
    printf("Booting...\n");
    int boot_remain = BOOT_CYCLES;
    while (boot_remain > 0) {
        int n = (boot_remain > 200) ? 200 : boot_remain;
        run_cycles(top, inj, n, prev_strobe, 0);
        read_fb(top, fb_pixels);
        // Debug: print key pixels using 2D index (y*40+x)
        static int dbg_cnt = 0;
        if (dbg_cnt < 3) {
            printf("boot %d: (0,0)=0x%08X (5,5)=0x%08X (15,14)=0x%08X (15,15)=0x%08X\n",
                   dbg_cnt,
                   fb_pixels[0*GAME_W+0],    // (0,0) top-left
                   fb_pixels[5*GAME_W+5],    // (5,5)
                   fb_pixels[15*GAME_W+14],   // (15,14) RED debug
                   fb_pixels[15*GAME_W+15]);  // (15,15) GREEN debug
            dbg_cnt++;
        }
        SDL_UpdateTexture(tex, NULL, fb_pixels, GAME_W * 4);
        SDL_RenderCopy(ren, tex, NULL, NULL);
        SDL_RenderPresent(ren);
        boot_remain -= n;
    }
    printf("Running. WASD=move, Q/Esc=quit\n");

    int running = 1;

    while (running) {
        // ── SDL events + keyboard ──────────────────────────────
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) running = 0;
            if (ev.type == SDL_KEYDOWN && !inj.busy()) {
                switch (ev.key.keysym.sym) {
                    case SDLK_w: inj.send('w'); break;
                    case SDLK_a: inj.send('a'); break;
                    case SDLK_s: inj.send('s'); break;
                    case SDLK_d: inj.send('d'); break;
                    case SDLK_q:     running = 0; break;
                    case SDLK_ESCAPE: running = 0; break;
                }
            }
        }

        // ── Run a batch and render ──────────────────────────────
        run_cycles(top, inj, BATCH_CYCLES, prev_strobe, 1);
        read_fb(top, fb_pixels);
        static int dbg2 = 0;
        if (dbg2 < 5) {
            printf("run %d: (0,0)=0x%08X (15,14)=0x%08X (15,15)=0x%08X (15,17)=0x%08X\n",
                   dbg2,
                   fb_pixels[0*GAME_W+0],
                   fb_pixels[15*GAME_W+14],
                   fb_pixels[15*GAME_W+15],
                   fb_pixels[15*GAME_W+17]);
            dbg2++;
        }

        SDL_UpdateTexture(tex, NULL, fb_pixels, GAME_W * 4);
        SDL_RenderCopy(ren, tex, NULL, NULL);
        SDL_RenderPresent(ren);
        SDL_Delay(150);  // throttle: ~6 fps, playable snake speed
    }

    SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    top->final(); delete top;
    return 0;
}
