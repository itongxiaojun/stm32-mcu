// ========================================================================
// RCC - Reset and Clock Control
// ========================================================================
// STM32F103-compatible RCC peripheral.
// Controls system clock sources, HSE/LSI/LSE oscillators,
// PLL configuration, and peripheral clock enables.
// ========================================================================

module rcc (
    input  wire                     clk,
    input  wire                     resetn,

    // APB Slave Interface
    input  wire                     Psel,
    input  wire                     Penable,
    input  wire                     Pwrite,
    input  wire [31:0]              Paddr,
    input  wire [31:0]              Pwdata,
    output wire [31:0]              Prdata,
    input  wire                     Pready,

    // Clock outputs
    output wire                     sysclk,
    output wire                     hse_osc_en,
    output wire                     hsi_osc_en,
    output wire                     pll_en,
    output wire [31:0]              cfgr
);

    // =================================================================
    // Register Map (base address 0x40021000)
    // =================================================================
    // 0x00: CR        - Clock control register
    // 0x04: CFGR      - Clock configuration register
    // 0x08: CIR       - Clock interrupt register
    // 0x0C: APB2RSTR  - APB2 peripheral reset register
    // 0x10: APB1RSTR  - APB1 peripheral reset register
    // 0x14: AHBENR    - AHB peripheral clock enable register
    // 0x18: APB2ENR   - APB2 peripheral clock enable register
    // 0x1C: APB1ENR   - APB1 peripheral clock enable register
    // 0x20: BDCR      - Backup domain control register
    // 0x24: CSR       - Control/status register
    // 0x28: AHBRSTR   - AHB peripheral reset register

    reg [31:0] regs [0:27];

    // Internal clock sources
    reg         hse_osc     = 1'b0;   // High-speed external oscillator
    reg         hsi_osc     = 1'b1;   // High-speed internal RC (8MHz default)
    reg         lse_osc     = 1'b0;   // Low-speed external oscillator
    reg         lsi_osc     = 1'b0;   // Low-speed internal oscillator
    reg [24:0]  hse_count   = 0;     // HSE startup counter

    // PLL configuration
    reg [31:0]  pll_cfg     = 32'd0;
    reg         pll_locked  = 1'b0;
    reg [31:0]  pll_freq    = 32'd0;

    // System clock mux
    reg [2:0]   sw          = 3'd0;  // Switch counter
    reg [2:0]   sws         = 3'd0;  // Switch status
    reg         sysclk_src    = 1'b0; // 0=HSI, 1=HSE, 2=PLL

    // Clock frequencies (approximate)
    reg [31:0]  hclk_freq   = 32'd8_000_000;
    reg [31:0]  pclk1_freq  = 32'd8_000_000;
    reg [31:0]  pclk2_freq  = 32'd8_000_000;

    // Clock enable registers
    reg [31:0]  ahbenr    = 32'h0000_0000;
    reg [31:0]  apb2enr   = 32'h0000_0000;
    reg [31:0]  apb1enr   = 32'h0000_0000;

    // Reset registers
    reg [31:0]  apb2rst   = 32'h0000_0000;
    reg [31:0]  apb1rst   = 32'h0000_0000;
    reg [31:0]  ahbrst    = 32'h0000_0000;

    // =================================================================
    // Register Read/Write
    // =================================================================
    reg [31:0] rdata_reg;
    reg [4:0]  addr_idx;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            // Default: HSI as system clock
            hsi_osc     <= 1'b1;
            regs[0]     <= 32'h0000_0000; // CR
            regs[1]     <= 32'h0000_0000; // CFGR
            regs[2]     <= 32'h0000_0000; // CIR
            regs[3]     <= 32'h0000_0000; // APB2RSTR
            regs[4]     <= 32'h0000_0000; // APB1RSTR
            regs[5]     <= 32'h0000_0000; // AHBENR
            regs[6]     <= 32'h0000_0000; // APB2ENR
            regs[7]     <= 32'h0000_0000; // APB1ENR
            regs[8]     <= 32'h0000_0000; // BDCR
            regs[9]     <= 32'h0000_0000; // CSR
            regs[10]    <= 32'h0000_0000; // AHBRSTR
            sysclk_src  <= 1'b0;
        end else if (Psel && Penable && Pwrite) begin
            case (Paddr[8:2]) // 32-byte aligned register index
                5'd0:  regs[0] <= Pwdata;   // CR
                5'd1:  regs[1] <= Pwdata;   // CFGR
                5'd2:  regs[2] <= Pwdata;   // CIR
                5'd3:  regs[3] <= Pwdata;   // APB2RSTR
                5'd4:  regs[4] <= Pwdata;   // APB1RSTR
                5'd5:  regs[5] <= Pwdata;   // AHBENR
                5'd6:  regs[6] <= Pwdata;   // APB2ENR
                5'd7:  regs[7] <= Pwdata;   // APB1ENR
                5'd8:  regs[8] <= Pwdata;   // BDCR
                5'd9:  regs[9] <= Pwdata;   // CSR
                5'd10: regs[10] <= Pwdata;  // AHBRSTR
                default: begin end
            endcase
            // Handle clock source switching
            if (Paddr[8:2] == 5'd1) begin
                if (Pwdata[0] == 0) begin
                    sysclk_src <= 1'b0; // HSI
                end else if (Pwdata[0] == 1) begin
                    sysclk_src <= 1'b1; // HSE
                end else if (Pwdata[0] == 2) begin
                    sysclk_src <= 1'b0; // PLL (simplified)
                end
            end
        end
    end

    // Clock source assignment
    assign sysclk = sysclk_src ? (hsi_osc ? 32'd8_000_000 : 32'd8_000_000) : 32'd8_000_000;
    assign hse_osc_en = hse_osc;
    assign hsi_osc_en = hsi_osc;
    assign pll_en = pll_locked;
    assign cfgr = regs[1];

    // =================================================================
    // Register Read
    // =================================================================
    always @(*) begin
        case (Paddr[8:2])
            5'd0:  rdata_reg = regs[0];   // CR
            5'd1:  rdata_reg = regs[1];   // CFGR
            5'd2:  rdata_reg = regs[2];   // CIR
            5'd3:  rdata_reg = regs[3];   // APB2RSTR
            5'd4:  rdata_reg = regs[4];   // APB1RSTR
            5'd5:  rdata_reg = regs[5];   // AHBENR
            5'd6:  rdata_reg = regs[6];   // APB2ENR
            5'd7:  rdata_reg = regs[7];   // APB1ENR
            5'd8:  rdata_reg = regs[8];   // BDCR
            5'd9:  rdata_reg = regs[9];   // CSR
            5'd10: rdata_reg = regs[10];  // AHBRSTR
            default: rdata_reg = 32'h0000_0000;
        endcase
    end

    assign Prdata = rdata_reg;

endmodule
