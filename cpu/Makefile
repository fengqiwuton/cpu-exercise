IVERILOG = /e/iverilog/bin
export PATH := $(IVERILOG):$(PATH)
RTL = rtl/pc.sv rtl/insn_mem.sv rtl/regfile.sv rtl/alu.sv \
      rtl/data_mem.sv rtl/imm_gen.sv rtl/control.sv rtl/cpu_top.sv
TB  = testbench/cpu_tb.sv
SIM = simv
VCD = dump.vcd
DATA_HEX = programs/data.hex
IVFLAGS = -g2012 -DDATA_INIT_FILE=\"$(DATA_HEX)\"

.PHONY: sim wave clean asm_all sim1 sim2 sim3 sim4

sim: sim4

sim1: programs/test1_alu.hex
	iverilog $(IVFLAGS) -DPROG_FILE=\"programs/test1_alu.hex\" -o $(SIM) $(RTL) $(TB)
	vvp $(SIM)

sim2: programs/test2_mem.hex
	iverilog $(IVFLAGS) -DPROG_FILE=\"programs/test2_mem.hex\" -o $(SIM) $(RTL) $(TB)
	vvp $(SIM)

sim3: programs/test3_branch.hex
	iverilog $(IVFLAGS) -DPROG_FILE=\"programs/test3_branch.hex\" -o $(SIM) $(RTL) $(TB)
	vvp $(SIM)

sim4: programs/test4_integration.hex
	iverilog $(IVFLAGS) -DPROG_FILE=\"programs/test4_integration.hex\" -o $(SIM) $(RTL) $(TB)
	vvp $(SIM)

wave: sim
	gtkwave $(VCD) &

asm_all: tools/assembler.py
	python3 tools/assembler.py programs/test1_alu.asm -o programs/test1_alu.hex
	python3 tools/assembler.py programs/test2_mem.asm -o programs/test2_mem.hex
	python3 tools/assembler.py programs/test3_branch.asm -o programs/test3_branch.hex
	python3 tools/assembler.py programs/test4_integration.asm -o programs/test4_integration.hex

clean:
	rm -f $(SIM) $(VCD)
