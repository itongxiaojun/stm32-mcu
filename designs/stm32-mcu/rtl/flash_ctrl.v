// ========================================================================
// Flash Memory Controller
// ========================================================================
// Memory-mapped flash controller for the STM32-compatible MCU.
// Provides read access to the boot flash memory (0x00000000-0x0003FFFF).
// Supports 256KB of flash memory.
// ========================================================================

module flash_ctrl (
    input  wire                     clk,
    input  wire                     resetn,

    // AHB Slave Interface
    input  wire                     Hsel,
    input  wire                     Hready,
    input  wire [1:0]               Htrans,
    input  wire                     Hwrite,
    input  wire [31:0]              Haddr,
    input  wire [31:0]              Hwdata,

    output wire                     Hready_out,
    output wire [31:0]              Hrdata,
    output wire                     Hresp,

    // Flash memory interface (to actual flash chip)
    output wire                     flash_ce,    // Chip enable
    output wire                     flash_oe,    // Output enable
    output wire                     flash_we,    // Write enable
    output wire [20:0]              flash_addr,  // Address (21-bit for 2MB)
    output wire [31:0]              flash_dout,  // Data output
    input  wire [31:0]              flash_din,   // Data input
    input  wire                     flash_rdy    // Flash ready
);

    // =================================================================
    // Register Map (base address 0x40022000)
    // =================================================================
    // 0x00: ACR  - Flash access control register
    // 0x04: KEYR - Flash key register
    // 0x08: OPTKEYR - Flash option key register
    // 0x0C: SR   - Flash status register
    // 0x10: CR   - Flash control register
    // 0x14: AR   - Flash address register

    reg [31:0] regs [0:5];

    // Flash memory array (256KB = 64K x 32 bits)
    // In a real chip, this would be actual flash cells
    reg [31:0] flash_mem [0:65535];

    // Write state machine
    reg [31:0] write_data;
    reg [20:0] write_addr;
    reg        write_active;
    reg [31:0] prog_data;

    // =================================================================
    // Initialization
    // =================================================================
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1)
            flash_mem[i] = 32'h0000_0000;
    end

    // =================================================================
    // Register Write
    // =================================================================
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (i = 0; i < 6; i = i + 1)
                regs[i] <= 32'h0000_0000;
            write_active <= 1'b0;
            regs[0] <= 32'h0000_0000; // ACR
            regs[1] <= 32'h0000_0000; // KEYR
            regs[2] <= 32'h0000_0000; // OPTKEYR
            regs[3] <= 32'h0000_0000; // SR
            regs[4] <= 32'h0000_0000; // CR
            regs[5] <= 32'h0000_0000; // AR
        end else if (Hsel && Htrans[1] && Hready && Hwrite) begin
            case (Haddr[8:2])
                5'd0: regs[0] <= Hwdata;   // ACR
                5'd1: regs[1] <= Hwdata;   // KEYR
                5'd2: regs[2] <= Hwdata;   // OPTKEYR
                5'd3: regs[3] <= Hwdata;   // SR
                5'd4: regs[4] <= Hwdata;   // CR
                5'd5: regs[5] <= Hwdata;   // AR
            endcase

            // Handle flash programming
            if (Haddr[8:2] == 5'd4) begin // CR write
                // Check if programming sequence is correct
                if (regs[4][0] && regs[4][1] && !regs[4][2]) begin
                    // Page program
                    write_addr <= Haddr[20:2];
                    write_data <= Hwdata;
                    write_active <= 1'b1;
                end
            end
        end
    end

    // Flash programming
    always @(posedge clk) begin
        if (write_active) begin
            flash_mem[write_addr] <= write_data;
            write_active <= 1'b0;
            regs[3][0] <= 1'b1; // BSY = 0 (ready)
        end
    end

    // =================================================================
    // AHB Read Interface
    // =================================================================
    reg [31:0] rdata_reg;
    reg        ready_reg;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rdata_reg <= 32'd0;
            ready_reg <= 1'b0;
        end else begin
            ready_reg <= 1'b1;
            if (Hsel && !Hwrite && Htrans[1]) begin
                // Read from flash memory
                if (Haddr[22:2] < 65536) begin
                    rdata_reg <= flash_mem[Haddr[22:2]];
                end else begin
                    rdata_reg <= 32'h0000_0000;
                end
            end
        end
    end

    assign Hready_out = ready_reg;
    assign Hrdata = rdata_reg;
    assign Hresp = 2'b00;

    // =================================================================
    // Flash chip interface
    // =================================================================
    assign flash_ce = ~Hsel; // Active low
    assign flash_oe = ~Hsel & ~Hwrite;
    assign flash_we = Hsel & Hwrite;
    assign flash_addr = Haddr[20:0];
    assign flash_dout = Hwdata;
    // flash_din is from the actual flash chip
    // flash_rdy is asserted by the flash chip

endmodule
