`ifndef CPU_PKG_SVH
`define CPU_PKG_SVH

// Opcodes
`define OP_RTYPE  7'b0110011
`define OP_LOAD   7'b0000011
`define OP_STORE  7'b0100011
`define OP_BRANCH 7'b1100011

// funct3
`define F3_ADD_SUB 3'b000
`define F3_AND     3'b111
`define F3_OR      3'b110
`define F3_LW      3'b010
`define F3_SW      3'b010
`define F3_BEQ     3'b000
`define F3_BLT     3'b100
`define F3_BGE     3'b101
`define F3_BLTU    3'b110
`define F3_BGEU    3'b111

// funct7
`define F7_ADD 7'b0000000
`define F7_SUB 7'b0100000

// ALU control
`define ALU_ADD  4'b0000
`define ALU_SUB  4'b0001
`define ALU_AND  4'b0010
`define ALU_OR   4'b0011
`define ALU_SLT  4'b0100
`define ALU_SLTU 4'b0101

`endif
