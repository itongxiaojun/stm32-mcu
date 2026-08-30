// ========================================================================
// STM32-Compatible MCU Top-Level Module
// ========================================================================
// Built on IIC-OSIC-TOOLS with picorv32 RISC-V core.
// Memory-mapped bus: Flash, SRAM, GPIO, RCC, UART, SPI, Timer.
// ========================================================================
// Memory Map:
//   0x00000000-0x0003FFFF: Flash (256KB)
//   0x20000000-0x2000FFFF: SRAM (64KB)
//   0x40020000-0x40020FFF: GPIOA
//   0x40021000-0x40021FFF: RCC
// ========================================================================

module stm32_top (
    input  wire                     clk,
    input  wire                     resetn,

    // GPIO pins (Port A)
    input  wire [15:0]              gpio_in,
    output wire [15:0]              gpio_out,
    output wire [15:0]              gpio_oe,

    // UART
    input  wire                     uart_rx,
    output wire                     uart_tx,

    // SPI
    output wire                     spi_sclk,
    output wire                     spi_mosi,
    input  wire                     spi_miso,
    output wire                     spi_cs_n,

    // SWD debug
    input  wire                     swd_clk,
    input  wire                     swd_data
);

    // =================================================================
    // picorv32 Memory Interface
    // =================================================================
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;
    wire        trap;

    // =================================================================
    // Interrupt signals from peripherals
    // =================================================================
    wire        tim2_irq;
    wire        usart1_irq;
    wire        spi1_irq;
    wire        gpio_irq;
    wire        flash_irq;

    // Combine all interrupt sources into a single vector
    // picorv32 irq input: 32 bits, each bit is an interrupt source
    wire [31:0] cpu_irq = {
        27'd0,            // bits 27-31: reserved
        flash_irq,        // bit 26
        gpio_irq,         // bit 25
        spi1_irq,         // bit 24
        usart1_irq,       // bit 23
        tim2_irq,         // bit 22
        6'd0              // bits 0-5: reserved
    };

    // =================================================================
    // 1. RISC-V Core (picorv32) - RV32IMC with IRQ
    // =================================================================
    riscv_core #(
        .RESET_ADDR(32'h00000000),
        .IRQ_ADDR  (32'h00000010),
        .STACK_ADDR(32'h2000FFFF)
    ) riscv_core_inst (
        .clk      (clk),
        .resetn   (resetn),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr (mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .irq      (cpu_irq),
        .trap     (trap)
    );

    // =================================================================
    // 2. Address Decoders
    // =================================================================
    wire sel_flash  = mem_valid && (mem_addr >= 32'h0000_0000) && (mem_addr < 32'h0004_0000);
    wire sel_sram   = mem_valid && (mem_addr >= 32'h2000_0000) && (mem_addr < 32'h2001_0000);
    wire sel_gpio   = mem_valid && (mem_addr >= 32'h4002_0000) && (mem_addr < 32'h4002_1000);
    wire sel_rcc    = mem_valid && (mem_addr >= 32'h4002_1000) && (mem_addr < 32'h4002_2000);
    wire sel_tim2   = mem_valid && (mem_addr >= 32'h4000_0000) && (mem_addr < 32'h4000_1000);
    wire sel_spi1   = mem_valid && (mem_addr >= 32'h4001_3000) && (mem_addr < 32'h4001_4000);
    wire sel_usart1 = mem_valid && (mem_addr >= 32'h4001_3800) && (mem_addr < 32'h4001_4000);

    // =================================================================
    // 3. Flash Memory (256KB = 65536 x 32 bits)
    // =================================================================
    reg [31:0] flash_mem [0:65535];
    reg [31:0] flash_rdata;
    reg        flash_ready;

    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1)
            flash_mem[i] = 32'h0000_0000;
    end

    always @(posedge clk) begin
        flash_ready <= 1'b1;
        if (sel_flash) begin
            if (!mem_wstrb && mem_addr[22:2] < 65536) begin
                // Read (instruction fetch or data read)
                flash_rdata <= flash_mem[mem_addr[22:2]];
            end
            if (mem_wstrb != 4'd0 && mem_addr[22:2] < 65536) begin
                // Write (flash programming)
                flash_mem[mem_addr[22:2]] <= mem_wdata;
                flash_rdata <= mem_wdata;
            end
        end
    end

    // =================================================================
    // 4. SRAM Memory (64KB = 16384 x 32 bits)
    // =================================================================
    reg [31:0] sram_mem [0:16383];
    reg [31:0] sram_rdata;
    reg        sram_ready;

    always @(posedge clk) begin
        sram_ready <= 1'b1;
        if (sel_sram) begin
            if (!mem_wstrb && mem_addr[21:2] < 16384) begin
                // Read
                sram_rdata <= sram_mem[mem_addr[21:2]];
            end
            if (mem_wstrb != 4'd0 && mem_addr[21:2] < 16384) begin
                // Write with byte enables
                if (mem_wstrb[0]) sram_mem[mem_addr[21:2]][7:0]   <= mem_wdata[7:0];
                if (mem_wstrb[1]) sram_mem[mem_addr[21:2]][15:8]  <= mem_wdata[15:8];
                if (mem_wstrb[2]) sram_mem[mem_addr[21:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) sram_mem[mem_addr[21:2]][31:24] <= mem_wdata[31:24];
            end
            sram_rdata <= sram_mem[mem_addr[21:2]];
        end
    end

    // =================================================================
    // 5. GPIOA Controller
    // =================================================================
    reg [31:0] gpio_crl;
    reg [31:0] gpio_crh;
    reg [31:0] gpio_odr;
    reg [31:0] gpio_bsrr;
    reg [31:0] gpio_brr;

    reg [15:0] gpio_pad_o;
    reg [15:0] gpio_pad_oe;
    reg [15:0] gpio_idr_reg;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            gpio_crl  <= 32'h4444_4444;  // Default: input floating
            gpio_crh  <= 32'h4444_4444;
            gpio_odr  <= 32'h0000_0000;
            gpio_bsrr <= 32'h0000_0000;
            gpio_brr  <= 32'h0000_0000;
            gpio_pad_o <= 16'd0;
            gpio_pad_oe <= 16'd0;
            gpio_idr_reg <= 16'd0;
        end else begin
            // Read inputs
            gpio_idr_reg <= gpio_in;

            // Write operations
            if (sel_gpio && mem_wstrb != 4'd0) begin
                case (mem_addr[8:2])
                    5'd0: gpio_crl <= mem_wdata;
                    5'd1: gpio_crh <= mem_wdata;
                    5'd3: gpio_odr <= mem_wdata;
                    5'd4: begin // BSRR
                        if (mem_wdata[15:0] != 0)
                            gpio_odr <= gpio_odr | mem_wdata[15:0];
                        if (mem_wdata[31:16] != 0)
                            gpio_odr <= gpio_odr & ~mem_wdata[31:16];
                        gpio_bsrr <= mem_wdata;
                    end
                    5'd5: begin // BRR
                        gpio_odr <= gpio_odr & ~mem_wdata[15:0];
                        gpio_brr <= mem_wdata;
                    end
                endcase
            end

            // Generate GPIO outputs from ODR and configuration (8 pins)
            for (i = 0; i < 8; i = i + 1) begin
                case (gpio_crl[i*4 +: 4])
                    4'd1, 4'd2, 4'd3: begin // Output mode
                        gpio_pad_oe[i] = 1'b1;
                        gpio_pad_o[i]  = gpio_odr[i];
                    end
                    default: begin // Input/Analog
                        gpio_pad_oe[i] = 1'b0;
                        gpio_pad_o[i]  = 1'b0;
                    end
                endcase
            end
            // Default: remaining pins as inputs
            for (i = 8; i < 16; i = i + 1) begin
                gpio_pad_oe[i] = 1'b0;
                gpio_pad_o[i]  = 1'b0;
            end
        end
    end

    assign gpio_out = gpio_pad_o;
    assign gpio_oe  = gpio_pad_oe;

    // =================================================================
    // 6. RCC (Reset and Clock Control) - simplified
    // =================================================================
    reg [31:0] rcc_cr;
    reg [31:0] rcc_cfgr;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rcc_cr   <= 32'h0000_0000;
            rcc_cfgr <= 32'h0000_0000;
        end else if (sel_rcc && mem_wstrb != 4'd0) begin
            case (mem_addr[8:2])
                5'd0: rcc_cr   <= mem_wdata;
                5'd1: rcc_cfgr <= mem_wdata;
            endcase
        end
    end

    // =================================================================
    // 7. Bus Multiplexer - route memory reads to appropriate slave
    // =================================================================
    reg [31:0] mem_rdata_mux;
    reg        mem_ready_mux;

    always @(posedge clk) begin
        // Default
        mem_rdata_mux <= 32'h0000_0000;
        mem_ready_mux <= 1'b0;

        if (sel_flash) begin
            mem_rdata_mux <= flash_rdata;
            mem_ready_mux <= flash_ready;
        end
        if (sel_sram) begin
            mem_rdata_mux <= sram_rdata;
            mem_ready_mux <= sram_ready;
        end
        if (sel_gpio) begin
            mem_rdata_mux <= {16'd0, gpio_idr_reg}; // IDR read
            mem_ready_mux <= 1'b1;
        end
        if (sel_rcc) begin
            mem_ready_mux <= 1'b1;
        end
    end

    assign mem_rdata = mem_rdata_mux;
    assign mem_ready = mem_ready_mux;

endmodule
