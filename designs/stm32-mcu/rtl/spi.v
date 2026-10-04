// ========================================================================
// SPI - Serial Peripheral Interface
// ========================================================================
// STM32F103-compatible SPI1 peripheral.
// Supports SPI master mode with configurable baud rate,
// CPOL/CPHA phases, and interrupt generation.
// ========================================================================

module spi (
    input  wire                     clk,
    input  wire                     resetn,

    // APB Slave Interface
    input  wire                     Psel,
    input  wire                     Penable,
    input  wire                     Pwrite,
    input  wire [31:0]              Paddr,
    input  wire [31:0]              Pwdata,
    output wire [31:0]              Prdata,

    // SPI pins
    output wire                     sclk,       // Serial clock
    output wire                     mosi,       // Master out slave in
    input  wire                     miso,       // Master in slave out
    output wire                     cs_n,       // Chip select (active low)

    // Interrupt output
    output wire                     irq
);

    // =================================================================
    // Register Map (base address 0x40013000)
    // =================================================================
    // 0x00: CR1  - Control register 1
    // 0x04: CR2  - Control register 2
    // 0x08: SR   - Status register
    // 0x0C: DR   - Data register
    // 0x10: CRCPR - CRC polynomial register
    // 0x14: RXCRCR - Receive CRC register
    // 0x18: TXCRCR - Transmit CRC register

    reg [31:0] regs [0:6];

    // SPI state machine
    reg [7:0]    shift_reg;
    reg [7:0]    rx_shift_reg;
    reg [3:0]    bit_count;
    reg          spi_active;
    reg          sclk_reg;
    reg [15:0]   sclk_div;
    reg [15:0]   sclk_counter;

    // =================================================================
    // Control Register Bits
    // CR1[6]: CPHA - Clock phase (0=1st edge, 1=2nd edge)
    // CR1[5]: CPOL - Clock polarity (0=idle low, 1=idle high)
    // CR1[2]: MSTR - Master selection
    // CR1[1]: SPE  - SPI enable
    // CR1[5:3]: BR - Baud rate divisor
    // =================================================================
    wire cpha = regs[0][6];
    wire cpol = regs[0][5];
    wire mstr = regs[0][2];
    wire spe  = regs[0][1];
    wire [2:0] br = regs[0][5:3];

    wire baud_div_val = (br == 3'd0) ? 2 :
                        (br == 3'd1) ? 4 :
                        (br == 3'd2) ? 8 :
                        (br == 3'd3) ? 16 :
                        (br == 3'd4) ? 32 :
                        (br == 3'd5) ? 64 :
                        (br == 3'd6) ? 128 : 256;

    // =================================================================
    // Register Write
    // =================================================================
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (integer i = 0; i < 7; i = i + 1)
                regs[i] <= 32'h0000_0000;
            sclk_reg <= 1'b0;
            sclk_counter <= 16'd0;
            spi_active <= 1'b0;
            bit_count <= 4'd0;
            cs_n <= 1'b1;
        end else if (Psel && Penable && Pwrite) begin
            case (Paddr[8:2])
                5'd0: regs[0] <= Pwdata;   // CR1
                5'd1: regs[1] <= Pwdata;   // CR2
                5'd2: regs[2] <= regs[2];  // SR (RO)
                5'd3: begin // DR write
                    regs[1] <= Pwdata;     // Actually DR
                    // Start transmission
                    if (spe && mstr) begin
                        shift_reg <= Pwdata[7:0];
                        bit_count <= 4'd0;
                        spi_active <= 1'b1;
                        cs_n <= 1'b0;
                        sclk_counter <= 16'd0;
                    end
                end
                default: begin end
            endcase

            // Clear TXE flag on DR write
            if (Paddr[8:2] == 5'd3) begin
                regs[2][1] <= 1'b1; // TXE = 1
            end
        end
    end

    // =================================================================
    // SPI Clock Generation and Shift Register
    // =================================================================
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            sclk_reg <= ~cpol;
            sclk_counter <= 16'd0;
        end else if (spi_active && spe) begin
            if (sclk_counter < baud_div_val / 2 - 1) begin
                sclk_counter <= sclk_counter + 1;
            end else begin
                sclk_counter <= 16'd0;
                sclk_reg <= ~sclk_reg;
            end
        end
    end

    // Shift register on clock edge
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            bit_count <= 4'd0;
            rx_shift_reg <= 8'd0;
        end else if (spi_active && spe) begin
            if (sclk_counter == 0) begin
                // Sample MISO on rising edge (CPHA=0) or falling edge (CPHA=1)
                if ((!cpha && cpol) || (cpha && !cpol)) begin
                    rx_shift_reg <= {miso, rx_shift_reg[7:1]};
                end
                // Shift MOSI on falling edge (CPHA=0) or rising edge (CPHA=1)
                if ((!cpha && !cpol) || (cpha && cpol)) begin
                    if (bit_count < 4'd8) begin
                        {shift_reg, shift_reg[0]} = {shift_reg[7:0], 1'b0};
                        bit_count <= bit_count + 1;
                    end
                end
            end

            // Transfer complete
            if (bit_count == 4'd8) begin
                spi_active <= 1'b0;
                cs_n <= 1'b1;
                regs[2][0] <= 1'b1; // RXNE = 1
                regs[2][1] <= 1'b1; // TXE = 1
                regs[1][7:0] <= rx_shift_reg; // DR = received data
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
            5'd2: rdata_reg = {30'd0, regs[2][1:0]}; // SR
            5'd3: rdata_reg = {31'd0, regs[1][7:0]}; // DR
            5'd4: rdata_reg = {16'd0, regs[2]}; // CRCPR (simplified)
            5'd5: rdata_reg = {32'd0}; // RXCRCR
            5'd6: rdata_reg = {32'd0}; // TXCRCR
            default: rdata_reg = 32'h0000_0000;
        endcase
    end

    assign Prdata = rdata_reg;
    assign sclk = spi_active ? sclk_reg : (cpol ? 1'b1 : 1'b0);
    assign mosi = shift_reg[7]; // MSB first for output
    assign cs_n = cs_n;

    // Interrupt generation
    assign irq = (regs[1][1] && regs[2][0]) || // RXNE and RXNEIE
                 (regs[1][0] && regs[2][1]);   // TXE and TXEIE

endmodule
