// ========================================================================
// Timer - Basic Timer (TIM2 compatible)
// ========================================================================
// STM32F103-compatible basic timer.
// Implements a 16-bit auto-reload counter with prescaler,
// update interrupt, and input capture (simplified).
// ========================================================================

module timer (
    input  wire                     clk,
    input  wire                     resetn,

    // APB Slave Interface
    input  wire                     Psel,
    input  wire                     Penable,
    input  wire                     Pwrite,
    input  wire [31:0]              Paddr,
    input  wire [31:0]              Pwdata,
    output wire [31:0]              Prdata,

    // Timer output
    output wire                     cnt_overflow, // Update event

    // Interrupt output
    output wire                     irq
);

    // =================================================================
    // Register Map (base address 0x40000000)
    // =================================================================
    // 0x00: CR1  - Control register 1
    // 0x04: CR2  - Control register 2
    // 0x08: SMCR - Slave mode control register
    // 0x0C: DIER - DMA/interrupt enable register
    // 0x10: SR   - Status register
    // 0x14: EGR  - Event generation register
    // 0x18: CCMR1- Capture/compare mode register 1
    // 0x1C: CCMR2- Capture/compare mode register 2
    // 0x20: CCER - Capture/compare enable register
    // 0x24: CNT  - Counter register
    // 0x28: PSC  - Prescaler register
    // 0x2C: ARR  - Auto-reload register

    reg [31:0] regs [0:13];

    // Counter and prescaler
    reg [15:0] cnt_reg;
    reg [15:0] psc_reg;
    reg [15:0] arr_reg;
    reg [15:0] psc_counter;

    // =================================================================
    // Register Write
    // =================================================================
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (integer i = 0; i < 14; i = i + 1)
                regs[i] <= 32'h0000_0000;
            cnt_reg <= 16'd0;
            psc_reg <= 16'd0;
            arr_reg <= 16'd0;
            psc_counter <= 16'd0;
        end else if (Psel && Penable && Pwrite) begin
            case (Paddr[8:2])
                5'd0: regs[0] <= Pwdata;   // CR1
                5'd1: regs[1] <= Pwdata;   // CR2
                5'd2: regs[2] <= Pwdata;   // SMCR
                5'd3: regs[3] <= Pwdata;   // DIER
                5'd4: regs[4] <= Pwdata;   // SR
                5'd5: regs[5] <= Pwdata;   // EGR
                5'd6: regs[6] <= Pwdata;   // CCMR1
                5'd7: regs[7] <= Pwdata;   // CCMR2
                5'd8: regs[8] <= Pwdata;   // CCER
                5'd9: regs[9] <= Pwdata;   // CNT (write to load counter)
                5'd10: regs[10] <= Pwdata; // PSC
                5'd11: regs[11] <= Pwdata; // ARR
            endcase

            // Handle shadow registers
            if (Paddr[8:2] == 5'd9) begin // CNT
                cnt_reg <= Pwdata[15:0];
            end else if (Paddr[8:2] == 5'd10) begin // PSC
                psc_reg <= Pwdata[15:0];
                psc_counter <= 16'd0;
            end else if (Paddr[8:2] == 5'd11) begin // ARR
                arr_reg <= Pwdata[15:0];
            end

            // Clear flags on write to SR
            if (Paddr[8:2] == 5'd4) begin
                regs[4][0] <= 1'b0; // UIF = 0
            end
        end
    end

    // =================================================================
    // Counter Logic
    // =================================================================
    wire [15:0] psc_reset = (psc_counter == 16'd0) ? 16'd0 : psc_counter - 16'd1;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            cnt_reg <= 16'd0;
            psc_counter <= 16'd0;
        end else begin
            // Prescaler counter
            if (regs[0][0]) begin // CEN = 1 (counter enable)
                if (psc_counter == 16'd0) begin
                    psc_counter <= psc_reg;
                end else begin
                    psc_counter <= psc_reset;
                end

                // Counter increment on each PSC reload
                if (psc_counter == 16'd0 && arr_reg != 16'd0) begin
                    if (cnt_reg == arr_reg) begin
                        cnt_reg <= 16'd0; // Wrap around
                        regs[4][0] <= 1'b1; // UIF = 1 (update interrupt flag)
                    end else begin
                        cnt_reg <= cnt_reg + 16'd1;
                    end
                end
            end
        end
    end

    // =================================================================
    // Register Read
    // =================================================================
    reg [31:0] rdata_reg;
    always @(*) begin
        case (Paddr[8:2])
            5'd0: rdata_reg = {24'd0, regs[0]}; // CR1
            5'd1: rdata_reg = {24'd0, regs[1]}; // CR2
            5'd2: rdata_reg = {24'd0, regs[2]}; // SMCR
            5'd3: rdata_reg = {24'd0, regs[3]}; // DIER
            5'd4: rdata_reg = {30'd0, regs[4][1:0]}; // SR
            5'd5: rdata_reg = {32'd0}; // EGR
            5'd6: rdata_reg = {16'd0, regs[6]}; // CCMR1
            5'd7: rdata_reg = {16'd0, regs[7]}; // CCMR2
            5'd8: rdata_reg = {16'd0, regs[8]}; // CCER
            5'd9: rdata_reg = {16'd0, cnt_reg}; // CNT
            5'd10: rdata_reg = {16'd0, psc_reg}; // PSC
            5'd11: rdata_reg = {16'd0, arr_reg}; // ARR
            default: rdata_reg = 32'h0000_0000;
        endcase
    end

    assign Prdata = rdata_reg;
    assign cnt_overflow = regs[4][0]; // UIF flag
    assign irq = regs[3][0] && regs[4][0]; // UDE and UIF

endmodule
