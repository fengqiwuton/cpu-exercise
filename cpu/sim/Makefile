# Verilator Makefile for MineCPU
TOP     = cpu_top
RTL_DIR = ../rtl
SRCS    = $(RTL_DIR)/pc.sv \
          $(RTL_DIR)/insn_mem.sv \
          $(RTL_DIR)/regfile.sv \
          $(RTL_DIR)/alu.sv \
          $(RTL_DIR)/data_mem.sv \
          $(RTL_DIR)/imm_gen.sv \
          $(RTL_DIR)/control.sv \
          $(RTL_DIR)/baud_gen.sv \
          $(RTL_DIR)/uart.sv \
          $(RTL_DIR)/vga_fb.sv \
          $(RTL_DIR)/ps2_kbd.sv \
          $(RTL_DIR)/csr.sv \
          $(RTL_DIR)/boot_rom.sv \
          $(RTL_DIR)/cpu_top.sv

VFLAGS  = -Wall -Wno-fatal -Wno-UNOPTFLAT \
          -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
          -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL \
          -Wno-UNDRIVEN -Wno-UNUSEDPARAM -Wno-CASEINCOMPLETE \
          -DSIMULATION -CFLAGS "-O3" --top-module $(TOP)

.PHONY: sim vga clean

# ── Terminal Snake ────────────────────────────────────────
obj_dir/V$(TOP): $(SRCS) sim_main.cpp
	verilator --cc --exe $(VFLAGS) $(SRCS) sim_main.cpp -o V$(TOP)
	cd obj_dir && $(MAKE) -f V$(TOP).mk -j$$(nproc)

sim: obj_dir/V$(TOP)
	./obj_dir/V$(TOP)

# ── VGA Snake (SDL2) ───────────────────────────────────────
obj_dir/V$(TOP)_vga: $(SRCS) sim_vga.cpp
	verilator --cc --exe $(VFLAGS) \
		-CFLAGS "-I/usr/include/SDL2 -D_REENTRANT -O3" \
		$(SRCS) sim_vga.cpp -o V$(TOP)_vga
	cd obj_dir && $(MAKE) -f V$(TOP).mk -j$$(nproc) LDLIBS="-lSDL2 -lpthread -latomic"

vga: obj_dir/V$(TOP)_vga
	./obj_dir/V$(TOP)_vga

# ── VGA PPM dump (framebuffer → image file) ─────────────────
obj_dir/V$(TOP)_dump: $(SRCS) sim_vga_dump.cpp
	verilator --cc --exe $(VFLAGS) $(SRCS) sim_vga_dump.cpp -o V$(TOP)_dump
	cd obj_dir && $(MAKE) -f V$(TOP).mk -j$$(nproc) LDLIBS="-lpthread -latomic"

dump: obj_dir/V$(TOP)_dump
	./obj_dir/V$(TOP)_dump
	@echo "Open snake_final.ppm with any image viewer"

clean:
	rm -rf obj_dir *.ppm
