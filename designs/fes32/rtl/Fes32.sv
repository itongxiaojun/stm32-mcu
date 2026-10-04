// ========================================================================
// FES32 Frame Design Wrapper
// Adapts the FES32 STM32-compatible MCU to the mpc-frame user design
// contract:  clock / reset / io_in[65:0] / io_out[65:0] / io_oe[65:0]
// ========================================================================

module Fes32 #(
    parameter int IO_WIDTH = 66,
    // Memory sizes. The ASIC flow has no SRAM macro library available, so the
    // memories are inferred as flip-flops: every word costs 32 flops. The
    // defaults below are the full STM32F103 sizes (256KB flash / 64KB SRAM)
    // used for simulation; a synthesis build must override them to stay within
    // a realisable cell count (see syn/Fes32SynthTop.sv).
    parameter int FLASH_WORDS = 65536,   // 256KB @ 32-bit words
    parameter int SRAM_WORDS  = 16384    // 64KB  @ 32-bit words
)(
    input  logic        clock,
    input  logic        reset,
    input  logic [65:0] io_in,
    output wire [65:0] io_out,
    output wire [65:0] io_oe
);

    // Word-address widths derived from the sizes above.
    localparam int FLASH_AW = $clog2(FLASH_WORDS);
    localparam int SRAM_AW  = $clog2(SRAM_WORDS);

    // ----------------------------------------------------------------
    // Internal signals
    // ----------------------------------------------------------------
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;
    wire        trap;

    wire        tim2_irq;
    wire        usart1_irq;
    wire        spi1_irq;
    wire        gpio_irq;
    wire        flash_irq;

    logic resetn;
    assign resetn = !reset;

    // ----------------------------------------------------------------
    // GPIOA internal registers
    // ----------------------------------------------------------------
    reg [31:0] gpio_crl;
    reg [31:0] gpio_crh;
    reg [31:0] gpio_odr;
    reg [31:0] gpio_bsrr;
    reg [31:0] gpio_brr;

    logic [15:0] gpio_pad_o;
    logic [15:0] gpio_pad_oe;
    reg   [15:0] gpio_idr_reg;

    // ----------------------------------------------------------------
    // IO bindings
    // ----------------------------------------------------------------
    reg [65:0] io_out_reg;
    assign io_out = io_out_reg;

    always @(posedge clock) begin
        io_out_reg[0]   <= 1'b0;     // UART TX (driven by usart module)
        io_out_reg[2]   <= 1'b0;     // SPI CLK (driven by spi module)
        io_out_reg[3]   <= 1'b0;     // SPI MOSI (driven by spi module)
        io_out_reg[5]   <= 1'b1;     // SPI CS (active low, default)
        io_out_reg[23:8]   <= gpio_odr;
        io_out_reg[39:24]  <= gpio_pad_oe;
    end

    // ----------------------------------------------------------------
    // IO output enable
    // ----------------------------------------------------------------
    reg [65:0] io_oe_reg;
    assign io_oe = io_oe_reg;

    always @(posedge clock) begin
        io_oe_reg <= '0;
        io_oe_reg[0]   <= 1'b1;   // UART TX driven
        io_oe_reg[2]   <= 1'b1;   // SPI CLK driven
        io_oe_reg[3]   <= 1'b1;   // SPI MOSI driven
        io_oe_reg[5]   <= 1'b1;   // SPI CS driven
        // NOTE: the full 16-bit banks must be set. Assigning a 1-bit value to a
        // 16-bit part-select zero-extends it, which would enable only bit 8 and
        // bit 24 respectively.
        io_oe_reg[23:8]  <= 16'hFFFF;  // GPIO ODR bank driven (excludes SWD bits 6-7)
        io_oe_reg[39:24] <= 16'hFFFF;  // GPIO OE bank driven (excludes SWD bits 6-7)
        // io_oe[1] = 0 (UART RX input)
        // io_oe[4] = 0 (SPI MISO input)
        // io_oe[6] = 0 (SWD CLK input, tri-state)
        // io_oe[7] = 0 (SWD DATA input, tri-state)
    end

    assign uart_tx = io_out_reg[0];
    assign uart_rx = io_in[1];
    assign spi_sclk = io_out_reg[2];
    assign spi_mosi = io_out_reg[3];
    assign spi_miso = io_in[4];
    assign spi_cs_n = io_out_reg[5];

    // ----------------------------------------------------------------
    // RISC-V Core (picorv32 wrapper)
    // ----------------------------------------------------------------
    riscv_core #(
        .RESET_ADDR(32'h00000000),
        .IRQ_ADDR  (32'h00000010),
        .STACK_ADDR(32'h2000FFFF)
    ) riscv_core_inst (
        .clk      (clock),
        .resetn   (resetn),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr (mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .irq      ({26'd0, flash_irq, gpio_irq, spi1_irq, usart1_irq, tim2_irq}),
        .trap     (trap)
    );

    // ----------------------------------------------------------------
    // Address Decoders
    // ----------------------------------------------------------------
    wire sel_flash  = mem_valid && (mem_addr >= 32'h0000_0000) && (mem_addr < 32'h0004_0000);
    wire sel_sram   = mem_valid && (mem_addr >= 32'h2000_0000) && (mem_addr < 32'h2001_0000);
    wire sel_gpio   = mem_valid && (mem_addr >= 32'h4002_0000) && (mem_addr < 32'h4002_1000);
    wire sel_rcc    = mem_valid && (mem_addr >= 32'h4002_1000) && (mem_addr < 32'h4002_2000);
    wire sel_tim2   = mem_valid && (mem_addr >= 32'h4000_0000) && (mem_addr < 32'h4000_1000);
    wire sel_spi1   = mem_valid && (mem_addr >= 32'h4001_3000) && (mem_addr < 32'h4001_4000);
    wire sel_usart1 = mem_valid && (mem_addr >= 32'h4001_3800) && (mem_addr < 32'h4001_4000);

    // ----------------------------------------------------------------
    // Flash Memory (FLASH_WORDS x 32 bits, default 256KB)
    // ----------------------------------------------------------------
    reg [31:0] flash_mem [0:FLASH_WORDS-1];
    reg [31:0] flash_rdata;
    reg        flash_ready;

    initial begin
        flash_mem[0] = 32'hDEADBEEF;  // Boot vector
    end

    always @(posedge clock) begin
        flash_ready <= 1'b1;
        if (sel_flash) begin
            if (!mem_wstrb)
                flash_rdata <= flash_mem[mem_addr[FLASH_AW+1:2]];
            if (mem_wstrb != 4'd0)
                flash_mem[mem_addr[FLASH_AW+1:2]] <= mem_wdata;
        end
    end

    // ----------------------------------------------------------------
    // SRAM Memory (SRAM_WORDS x 32 bits, default 64KB)
    // ----------------------------------------------------------------
    reg [31:0] sram_mem [0:SRAM_WORDS-1];
    reg [31:0] sram_rdata;
    reg        sram_ready;

    always @(posedge clock) begin
        sram_ready <= 1'b1;
        if (sel_sram) begin
            if (!mem_wstrb)
                sram_rdata <= sram_mem[mem_addr[SRAM_AW+1:2]];
            if (mem_wstrb != 4'd0) begin
                if (mem_wstrb[0]) sram_mem[mem_addr[SRAM_AW+1:2]][7:0]   <= mem_wdata[7:0];
                if (mem_wstrb[1]) sram_mem[mem_addr[SRAM_AW+1:2]][15:8]  <= mem_wdata[15:8];
                if (mem_wstrb[2]) sram_mem[mem_addr[SRAM_AW+1:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) sram_mem[mem_addr[SRAM_AW+1:2]][31:24] <= mem_wdata[31:24];
            end
            sram_rdata <= sram_mem[mem_addr[SRAM_AW+1:2]];
        end
    end

    // ----------------------------------------------------------------
    // GPIOA Controller
    // ----------------------------------------------------------------
    reg gpio_reset;
    always @(posedge clock) begin
        if (!gpio_reset) begin
            gpio_crl   <= 32'h4444_4444;
            gpio_crh   <= 32'h4444_4444;
            gpio_odr   <= 32'h0000_0000;
            gpio_bsrr  <= 32'h0000_0000;
            gpio_brr   <= 32'h0000_0000;
            gpio_idr_reg <= 16'd0;
            gpio_reset <= 1'b1;
        end else begin
            gpio_idr_reg <= io_in[54:39];

            if (sel_gpio && mem_wstrb != 4'd0) begin
                case (mem_addr[8:2])
                    5'd0: gpio_crl <= mem_wdata;
                    5'd1: gpio_crh <= mem_wdata;
                    5'd3: gpio_odr <= mem_wdata;
                    5'd4: begin
                        if (mem_wdata[15:0] != 0)
                            gpio_odr <= gpio_odr | mem_wdata[15:0];
                        if (mem_wdata[31:16] != 0)
                            gpio_odr <= gpio_odr & ~mem_wdata[31:16];
                        gpio_bsrr <= mem_wdata;
                    end
                    5'd5: begin
                        gpio_odr <= gpio_odr & ~mem_wdata[15:0];
                        gpio_brr <= mem_wdata;
                    end
                endcase
            end
        end
    end

    // Pad output data and enable are pure functions of the configuration
    // registers (CRL/CRH select the mode, ODR supplies the data), so they are
    // derived combinationally rather than registered. Keeping them out of the
    // clocked block also avoids mixing blocking and non-blocking assignments,
    // which a strict SystemVerilog front-end (slang) rejects.
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            case (gpio_crl[i*4 +: 4])
                4'd1, 4'd2, 4'd3: begin
                    gpio_pad_oe[i] = 1'b1;
                    gpio_pad_o[i]  = gpio_odr[i];
                end
                default: begin
                    gpio_pad_oe[i] = 1'b0;
                    gpio_pad_o[i]  = 1'b0;
                end
            endcase
        end
        for (int i = 8; i < 16; i++) begin
            case (gpio_crh[(i-8)*4 +: 4])
                4'd1, 4'd2, 4'd3: begin
                    gpio_pad_oe[i] = 1'b1;
                    gpio_pad_o[i]  = gpio_odr[i];
                end
                default: begin
                    gpio_pad_oe[i] = 1'b0;
                    gpio_pad_o[i]  = 1'b0;
                end
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Bus Multiplexer
    // ----------------------------------------------------------------
    assign mem_rdata = sel_flash ? flash_rdata :
                          sel_sram  ? sram_rdata :
                          sel_gpio  ? {16'd0, gpio_idr_reg} : 32'h0;
    assign mem_ready = sel_flash ? flash_ready :
                          sel_sram  ? sram_ready :
                          sel_gpio  ? 1'b1 : 1'b0;

    // NOTE: `trap` is driven by riscv_core's trap output and is currently
    // unused here. It must NOT also be assigned a constant - doing so created
    // a second driver on the wire, which Yosys reported as
    // "Output port ... trap ... is connected to constants: 1'0".

endmodule
