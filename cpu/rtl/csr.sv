// CSR (Control and Status Register) module — Machine Mode only
// Supported CSRs: mtvec(0x305), mepc(0x341), mcause(0x342), mstatus(0x300)
module csr (
    input  logic        clk,
    input  logic        rst_n,

    // CSR access
    input  logic [11:0] addr,
    input  logic [31:0] write_data,
    input  logic        csr_write,
    input  logic [1:0]  csr_op,      // 00=rw, 01=rs(set), 10=rc(clear)
    output logic [31:0] read_data,

    // Exception interface
    input  logic        exception,     // exception occurred
    input  logic [31:0] except_pc,     // PC of excepting instruction
    input  logic [3:0]  except_cause,  // exception cause code
    output logic [31:0] mtvec,
    output logic [31:0] mepc,
    output logic        mret_taken     // mret executed this cycle
);
    logic [31:0] mtvec_reg;
    logic [31:0] mepc_reg;
    logic [31:0] mcause_reg;
    logic [31:0] mstatus_reg;

    assign mtvec = mtvec_reg;
    assign mepc  = mepc_reg;

    // CSR read
    always_comb begin
        read_data = 32'h0;
        case (addr)
            12'h300: read_data = mstatus_reg;
            12'h305: read_data = mtvec_reg;
            12'h341: read_data = mepc_reg;
            12'h342: read_data = mcause_reg;
            default: read_data = 32'h0;
        endcase
    end

    // CSR write / exception capture
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtvec_reg   <= 32'h00000000;
            mepc_reg    <= 32'h00000000;
            mcause_reg  <= 32'h00000000;
            mstatus_reg <= 32'h00001800;   // MPP=M-mode, MIE=0
            mret_taken  <= 1'b0;
        end else begin
            mret_taken <= 1'b0;

            if (exception) begin
                mepc_reg   <= except_pc;
                mcause_reg <= {28'h0, except_cause};
                // Set MPP to current mode, disable interrupts
                mstatus_reg[12:11] <= 2'b11;  // MPP = M-mode
                mstatus_reg[7]     <= mstatus_reg[3]; // MPIE = MIE
                mstatus_reg[3]     <= 1'b0;   // MIE = 0
            end else if (csr_write) begin
                case (addr)
                    12'h300: mstatus_reg <= write_data;
                    12'h305: mtvec_reg   <= write_data;
                    12'h341: mepc_reg    <= write_data;
                    12'h342: mcause_reg  <= write_data;
                endcase
            end
        end
    end

    // mret detection (external, handled in cpu_top)
endmodule
