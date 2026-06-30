// VGA framebuffer dump — save every Nth frame as BMP
#include "Vcpu_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>

static const int BAUD  = 20;
static const int HW_W  = 80, GAME_W = 40, GAME_H = 30, SCALE = 8;
static const char *keys = "";  // no auto keys — snake reads from terminal or SDL2
static int ki = 0;

static struct termios orig;
void term_raw(){tcgetattr(0,&orig);struct termios r=orig;r.c_lflag&=~((unsigned)(ICANON|ECHO));tcsetattr(0,0,&r);fcntl(0,F_SETFL,fcntl(0,F_GETFL)|O_NONBLOCK);}
void term_restore(){tcsetattr(0,0,&orig);}

struct KeyInj{uint8_t b;int bit,cyc;bool act;KeyInj():b(0),bit(0),cyc(0),act(0){}void send(uint8_t c){b=c;bit=cyc=0;act=1;}bool busy(){return act;}int next(){if(!act)return 1;cyc++;if(cyc>=BAUD){cyc=0;bit++;}if(bit==0)return 0;if(bit<=8)return(b>>(bit-1))&1;act=0;return 1;}};

void dump_bmp(Vcpu_top *top, const char *fn) {
    int w = GAME_W * SCALE, h = GAME_H * SCALE;
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
        for(int x=0;x<w;x++){top->vga_dbg_addr=((h-1-y)/SCALE)*HW_W+(x/SCALE);top->eval();
            uint8_t c=top->vga_dbg_data;
            row[x*3+2]=((c>>5)&7)*36;row[x*3+1]=((c>>2)&7)*36;row[x*3+0]=(c&3)*85;}
        fwrite(row,1,rp,f);}
    delete[] row;fclose(f);
    printf(" -> %s\n", fn);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vcpu_top *top = new Vcpu_top;
    KeyInj inj;

    top->clk=0;top->rst_n=0;top->uart_rx_pin=1;top->vga_dbg_addr=0;
    top->eval();top->clk=1;top->eval();top->clk=0;top->eval();top->rst_n=1;

    term_raw();
    printf("=== Snake VGA (frame dump) ===\n");

    int run=1, prev_s=0, frame=0, cyc=0, key_timer=0, dumped_last=0, dbg_done=0;
    int KCYC = 200;

    while(run){
        // Inject keys
        if (!inj.busy() && ki < (int)strlen(keys) && key_timer > 80) {
            char c = keys[ki++];
            if (c=='q') run=0; else inj.send((uint8_t)c);
            key_timer = 0;
            printf("  [key:%c]", c); fflush(stdout);
        }
        key_timer++;

        // Check terminal
        char tc; if(!inj.busy()&&read(0,&tc,1)>0){if(tc=='q')run=0;else inj.send((uint8_t)tc);}

        // Run CPU
        for(int i=0;i<KCYC;i++){
            top->uart_rx_pin=inj.next();
            top->clk=1;top->eval();
            if(top->uart_tx_strobe&&!prev_s){printf("%c",(char)top->uart_tx_byte);fflush(stdout);}
            prev_s=top->uart_tx_strobe;
            top->clk=0;top->eval();
        }
        cyc++;

        // Dump frame every 50 iterations (faster: see scheduler activity)
        if (cyc - dumped_last >= 50 && frame < 20) {
            char fn[32]; sprintf(fn,"snake_%04d.bmp",frame++);
            printf("Frame %d", frame); fflush(stdout);
            dump_bmp(top, fn);
            dumped_last = cyc;
            if (!dbg_done) {
                // Check: counter digit at (row=1, col=2) → fb[82]
                // Check: dot at starting position (10,20) → fb[820]
                // Check: task debug pixels at columns inside border
                top->vga_dbg_addr = 405; top->eval();   // (5,5) for green debug
                printf(" [fb[405]=0x%02X]", top->vga_dbg_data);
                top->vga_dbg_addr = 0; top->eval();
                printf(" [fb[0]=0x%02X]", top->vga_dbg_data);
                top->vga_dbg_addr = 80; top->eval();
                printf(" [fb[80]=0x%02X]\n", top->vga_dbg_data);
                dbg_done = 1;
            }
        }
        if (frame >= 20) run = 0;  // stop after 20 frames
    }

    dump_bmp(top, "snake_final.bmp");
    term_restore();printf("\n%dframes dumped.\n",frame);
    top->final();delete top;return 0;
}
