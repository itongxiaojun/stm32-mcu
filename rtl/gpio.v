// ========================================================================
// GPIO - General Purpose Input/Output
// ========================================================================
// STM32F103-compatible GPIO port (Port A).
// Implements CRL (low 8 pins) and CRH (high 8 pins) configuration,
// IDR (input data), ODR (output data), BSRR (bit set/reset),
// BRR (bit reset), and LCKR (lock) registers.
// ========================================================================

module gpio (
    input  wire                     clk,
    input  wire                     resetn,

    // APB Slave Interface
    input  wire                     Psel,
    input  wire                     Penable,
    input  wire                     Pwrite,
    input  wire [31:0]              Paddr,
    input  wire [31:0]              Pwdata,
    output wire [31:0]              Prdata,

    // GPIO Pins
    // Port A: PA0-PA15
    input  wire [15:0]              pad_i,      // Pin analog input
    output wire [15:0]              pad_o,      // Pin output
    output wire [15:0]              pad_oe      // Output enable
);

    // =================================================================
    // Register Map (base address 0x40020000)
    // =================================================================
    // 0x00: CRL - Port x configuration register low (PA0-PA7)
    // 0x04: CRH - Port x configuration register high (PA8-PA15)
    // 0x08: IDR - Port x input data register
    // 0x0C: ODR - Port x output data register
    // 0x10: BSRR - Port x bit set/reset register
    // 0x14: BRR - Port x bit reset register
    // 0x18: LCKR - Port x configuration lock register

    reg [31:0] regs [0:6];

    // Pin configuration (mode and CNF for each pin)
    reg [3:0] pin_mode [0:15];    // Mode: 00=input, 01=output10MHz, 10=output2MHz, 11=output50MHz
    reg [3:0] pin_cnf [0:15];     // Configuration: 00=push-pull, 01=open-drain, 10=alternate, 11=analog

    // Output data register
    reg [15:0] odr_reg;

    // Read data register
    reg [15:0] idr_reg;

    // =================================================================
    // Register Write
    // =================================================================
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            regs[0] <= 32'h4444_4444; // Default: PA0-PA7 input floating
            regs[1] <= 32'h4444_4444; // Default: PA8-PA15 input floating
            regs[2] <= 32'h0000_0000; // IDR
            regs[3] <= 32'h0000_0000; // ODR
            regs[4] <= 32'h0000_0000; // BSRR
            regs[5] <= 32'h0000_0000; // BRR
            regs[6] <= 32'h0000_0000; // LCKR
            odr_reg <= 16'd0;
        end else if (Psel && Penable && Pwrite) begin
            case (Paddr[8:2])
                5'd0: regs[0] <= Pwdata;   // CRL
                5'd1: regs[1] <= Pwdata;   // CRH
                5'd2: regs[2] <= Pwdata;   // IDR (RO, but write for test)
                5'd3: regs[3] <= Pwdata;   // ODR
                5'd4: regs[4] <= Pwdata;   // BSRR
                5'd5: regs[5] <= Pwdata;   // BRR
                5'd6: regs[6] <= Pwdata;   // LCKR
            endcase

            // Handle BSRR (bit set/reset)
            if (Paddr[8:2] == 5'd4) begin
                if (Pwdata[15:0] != 0) begin
                    odr_reg <= odr_reg | Pwdata[15:0];    // Set bits
                end
                if (Pwdata[31:16] != 0) begin
                    odr_reg <= odr_reg & ~Pwdata[31:16];  // Reset bits
                end
            end

            // Handle BRR (bit reset)
            if (Paddr[8:2] == 5'd5) begin
                odr_reg <= odr_reg & ~Pwdata[15:0];
            end
        end
    end

    // Parse configuration registers
    integer i;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (i = 0; i < 16; i = i + 1) begin
                pin_mode[i] <= 4'd0;
                pin_cnf[i]  <= 4'd0;
            end
        end else begin
            for (i = 0; i < 8; i = i + 1) begin
                pin_mode[i]   <= regs[0][i*4 +: 4];
                pin_cnf[i]    <= regs[0][i*4 + 8 +: 4];
            end
            for (i = 0; i < 8; i = i + 1) begin
                pin_mode[i+8] <= regs[1][i*4 +: 4];
                pin_cnf[i+8]  <= regs[1][i*4 + 8 +: 4];
            end
        end
    end

    // =================================================================
    // Pin Output Drive
    // =================================================================
    reg [15:0] pad_o_next;
    reg [15:0] pad_oe_next;

    always @(*) begin
        for (i = 0; i < 16; i = i + 1) begin
            case (pin_mode[i])
                2'd0: begin // Input mode
                    pad_o_next[i] = 1'b0;
                    pad_oe_next[i] = 1'b0;
                end
                2'd1: begin // Output 10MHz push-pull/open-drain
                    if (pin_cnf[i][1]) // Open-drain
                        begin pad_o_next[i] = 1'b0; pad_oe_next[i] = odr_reg[i]; end
                    else // Push-pull
                        begin pad_o_next[i] = odr_reg[i]; pad_oe_next[i] = 1'b1; end
                end
                2'd2, 2'd3: begin // Output 2MHz/50MHz
                    if (pin_cnf[i][1])
                        begin pad_o_next[i] = 1'b0; pad_oe_next[i] = odr_reg[i]; end
                    else
                        begin pad_o_next[i] = odr_reg[i]; pad_oe_next[i] = 1'b1; end
                end
                default: begin // Analog
                    pad_o_next[i] = 1'b0;
                    pad_oe_next[i] = 1'b0;
                end
            endcase
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            pad_o  <= 16'd0;
            pad_oe <= 16'd0;
        end else begin
            pad_o  <= pad_o_next;
            pad_oe <= pad_oe_next;
        end
    end

    // =================================================================
    // Register Read
    // =================================================================
    reg [31:0] rdata_reg;

    always @(*) begin
        // Read pin inputs
        idr_reg = pad_i;

        case (Paddr[8:2])
            5'd0: rdata_reg = {16'd0, regs[0]}; // CRL (RO in upper 16 bits)
            5'd1: rdata_reg = {16'd0, regs[1]}; // CRH
            5'd2: rdata_reg = {16'd0, idr_reg}; // IDR
            5'd3: rdata_reg = {16'd0, odr_reg}; // ODR
            5'd4: rdata_reg = regs[4];          // BSRR
            5'd5: rdata_reg = regs[5];          // BRR
            5'd6: rdata_reg = regs[6];          // LCKR
            default: rdata_reg = 32'h0000_0000;
        endcase
    end

    assign Prdata = rdata_reg;

endmodule
