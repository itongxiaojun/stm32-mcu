// ========================================================================
// NVIC - Nested Vectored Interrupt Controller
// ========================================================================
// Simplified NVIC implementation for the STM32-compatible MCU.
// Manages interrupt sources, priority grouping, and interrupt
// routing to the picorv32 core.
// ========================================================================

module nvic (
    input  wire                     clk,
    input  wire                     resetn,

    // Interrupt inputs from peripherals
    input  wire [31:0]              irq_src, // External interrupt sources
    input  wire [31:0]              irq_en,  // Interrupt enable

    // CPU interface (to picorv32)
    output wire [31:0]              cpu_irq, // Interrupt to CPU
    input  wire                     cpu_irq_ack,
    output wire [4:0]               cpu_irq_id,

    // System handler control
    input  wire                     sys_reset, // System reset
    output wire                     nmi_irq   // Non-maskable interrupt
);

    // =================================================================
    // Interrupt Enable and Pending Registers
    // =================================================================
    reg [31:0] iser   = 32'h0000_0000; // Interrupt Set-Enable Register
    reg [31:0] icepr  = 32'h0000_0000; // Interrupt Clear-Enable Pending Register
    reg [31:0] ispr   = 32'h0000_0000; // Interrupt Set-Pending Register
    reg [31:0] icpr   = 32'h0000_0000; // Interrupt Clear-Pending Register
    reg [31:0] ip     = 32'h0000_0000; // Interrupt Priority Register

    // Interrupt status
    reg [31:0] pending_irqs = 32'd0;
    reg [31:0] enabled_irqs = 32'd0;

    // =================================================================
    // Interrupt Routing
    // =================================================================
    // Map peripheral interrupts to NVIC IRQ lines
    // IRQ[0]: WWDG (Window Watchdog)
    // IRQ[1]: PVD (Power Voltage Detection)
    // IRQ[2]: TAMPER (Tamper)
    // IRQ[3]: RTC (RTC)
    // IRQ[4]: FLASH (Flash)
    // IRQ[5]: RCC (RCC)
    // IRQ[6]: EXTI0 (External Interrupt 0)
    // IRQ[7]: EXTI1
    // IRQ[8]: EXTI2
    // IRQ[9]: EXTI3
    // IRQ[10]: EXTI4
    // IRQ[11]: DMA1_Channel1
    // IRQ[12]: DMA1_Channel2
    // IRQ[13]: DMA1_Channel3
    // IRQ[14]: DMA1_Channel4
    // IRQ[15]: DMA1_Channel5
    // IRQ[16]: DMA1_Channel6
    // IRQ[17]: DMA1_Channel7
    // IRQ[18]: ADC1_2
    // IRQ[19]: USB_HP_CAN1_TX
    // IRQ[20]: USB_LP_CAN1_RX1
    // IRQ[21]: CAN1_RX0
    // IRQ[22]: CAN1_RX1
    // IRQ[23]: CAN1_SCE
    // IRQ[24]: EXTI9_5
    // IRQ[25]: TIM1_BRK
    // IRQ[26]: TIM1_UP
    // IRQ[27]: TIM1_TRG_COM
    // IRQ[28]: TIM1_CC
    // IRQ[29]: TIM2
    // IRQ[30]: TIM3
    // IRQ[31]: I2C1_EV

    // Peripheral interrupt sources
    wire usart1_irq = irq_src[0];   // USART1
    wire usart2_irq = irq_src[1];   // USART2
    wire spi1_irq   = irq_src[2];   // SPI1
    wire i2c1_irq   = irq_src[3];   // I2C1
    wire tim2_irq   = irq_src[4];   // TIM2
    wire tim1_irq   = irq_src[5];   // TIM1
    wire gpio_irq   = irq_src[6];   // GPIO
    wire flash_irq  = irq_src[7];   // FLASH

    // =================================================================
    // Interrupt Enable Register
    // =================================================================
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            iser <= 32'h0000_0000;
            icepr <= 32'h0000_0000;
            ispr <= 32'h0000_0000;
            icpr <= 32'h0000_0000;
            pending_irqs <= 32'd0;
            enabled_irqs <= 32'd0;
        end else begin
            // Set/clear enable
            if (irq_en[0] && irq_src[0]) iser[0] <= 1'b1;
            if (irq_en[1] && irq_src[1]) iser[1] <= 1'b1;
            if (irq_en[2] && irq_src[2]) iser[2] <= 1'b1;
            if (irq_en[3] && irq_src[3]) iser[3] <= 1'b1;
            if (irq_en[4] && irq_src[4]) iser[4] <= 1'b1;
            if (irq_en[5] && irq_src[5]) iser[5] <= 1'b1;
            if (irq_en[6] && irq_src[6]) iser[6] <= 1'b1;
            if (irq_en[7] && irq_src[7]) iser[7] <= 1'b1;

            // Set pending
            if (usart1_irq && iser[0]) pending_irqs[0] <= 1'b1;
            if (usart2_irq && iser[1]) pending_irqs[1] <= 1'b1;
            if (spi1_irq && iser[2]) pending_irqs[2] <= 1'b1;
            if (i2c1_irq && iser[3]) pending_irqs[3] <= 1'b1;
            if (tim2_irq && iser[4]) pending_irqs[4] <= 1'b1;
            if (tim1_irq && iser[5]) pending_irqs[5] <= 1'b1;
            if (gpio_irq && iser[6]) pending_irqs[6] <= 1'b1;
            if (flash_irq && iser[7]) pending_irqs[7] <= 1'b1;

            // Clear pending (software)
            if (icpr[0]) pending_irqs[0] <= 1'b0;
            if (icpr[1]) pending_irqs[1] <= 1'b0;
            if (icpr[2]) pending_irqs[2] <= 1'b0;
            if (icpr[3]) pending_irqs[3] <= 1'b0;
            if (icpr[4]) pending_irqs[4] <= 1'b0;
            if (icpr[5]) pending_irqs[5] <= 1'b0;
            if (icpr[6]) pending_irqs[6] <= 1'b0;
            if (icpr[7]) pending_irqs[7] <= 1'b0;
        end
    end

    // =================================================================
    // Highest Priority Pending Interrupt
    // =================================================================
    wire [4:0] highest_irq;
    reg [4:0] irq_id_reg;

    always @(*) begin
        if (pending_irqs[7]) highest_irq = 5'd7;
        else if (pending_irqs[6]) highest_irq = 5'd6;
        else if (pending_irqs[5]) highest_irq = 5'd5;
        else if (pending_irqs[4]) highest_irq = 5'd4;
        else if (pending_irqs[3]) highest_irq = 5'd3;
        else if (pending_irqs[2]) highest_irq = 5'd2;
        else if (pending_irqs[1]) highest_irq = 5'd1;
        else if (pending_irqs[0]) highest_irq = 5'd0;
        else highest_irq = 5'd0;
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            irq_id_reg <= 5'd0;
        else if (cpu_irq_ack)
            irq_id_reg <= highest_irq;
    end

    // =================================================================
    // CPU Interrupt Output
    // =================================================================
    wire any_pending = |(pending_irqs & iser);
    reg cpu_irq_reg;

    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            cpu_irq_reg <= 1'b0;
        else if (sys_reset)
            cpu_irq_reg <= 1'b0;
        else if (cpu_irq_ack)
            cpu_irq_reg <= 1'b0;
        else if (any_pending && ~cpu_irq_ack)
            cpu_irq_reg <= 1'b1;
    end

    assign cpu_irq = cpu_irq_reg ? {31'd0, 1'b1} : 32'd0;
    assign cpu_irq_id = irq_id_reg;
    assign nmi_irq = 1'b0; // No NMI in this simplified version

endmodule
