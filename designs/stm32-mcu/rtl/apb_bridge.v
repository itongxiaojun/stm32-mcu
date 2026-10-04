// ========================================================================
// APB Bridge - picorv32 Memory Interface to APB Protocol
// ========================================================================
// Bridges picorv32's native memory interface to the APB slave protocol
// used by peripheral modules. Generates Psel, Penable, Pwrite, Paddr,
// Pwdata, and Pready signals from the picorv32 memory interface.
// ========================================================================

module apb_bridge #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter APB_BASE   = 32'h40000000,
    parameter APB_END    = 32'h4001FFFF
)(
    input  wire                     clk,
    input  wire                     resetn,

    // picorv32 Memory Interface
    input  wire                     mem_valid,
    input  wire                     mem_instr,
    input  wire [ADDR_WIDTH-1:0]    mem_addr,
    input  wire [DATA_WIDTH-1:0]    mem_wdata,
    input  wire [3:0]               mem_wstrb,
    input  wire                     mem_ready,
    output wire [DATA_WIDTH-1:0]    mem_rdata,

    // APB Slave Interface (to peripherals)
    output wire                     Psel,
    output wire                     Penable,
    output wire                     Pwrite,
    output wire [ADDR_WIDTH-1:0]    Paddr,
    output wire [DATA_WIDTH-1:0]    Pwdata,
    input  wire [DATA_WIDTH-1:0]    Prdata,
    output wire                     Pready,

    // APB peripheral selection
    output wire                     sel_tim2,
    output wire                     sel_spi1,
    output wire                     sel_usart1,
    output wire                     sel_rcc,
    output wire                     sel_gpio
);

    // Address decoders
    assign sel_tim2   = mem_valid && (mem_addr >= 32'h40000000) && (mem_addr < 32'h40001000);
    assign sel_spi1   = mem_valid && (mem_addr >= 32'h40013000) && (mem_addr < 32'h40014000);
    assign sel_usart1 = mem_valid && (mem_addr >= 32'h40013800) && (mem_addr < 32'h40014000);
    assign sel_rcc    = mem_valid && (mem_addr >= 32'h40021000) && (mem_addr < 32'h40022000);
    assign sel_gpio   = mem_valid && (mem_addr >= 32'h40020000) && (mem_addr < 32'h40021000);

    // APB transfer state machine
    reg        psel_reg;
    reg        penable_reg;
    reg        write_reg;
    reg [ADDR_WIDTH-1:0] addr_pipe;
    reg [DATA_WIDTH-1:0] wdata_pipe;
    reg [DATA_WIDTH-1:0] rdata_pipe;

    // Psel: asserted when a peripheral is selected
    assign Psel = psel_reg;
    // Penable: asserted for setup and hold of the transfer
    assign Penable = penable_reg;
    assign Pwrite = write_reg;
    assign Paddr = addr_pipe;
    assign Pwdata = wdata_pipe;
    assign Pready = 1'b1; // Always ready for simple peripherals

    // Read data from peripherals
    assign mem_rdata = rdata_pipe;

    // APB transfer generation
    // Stage 1: Latch address/control on mem_valid
    // Stage 2: Assert Penable for one cycle
    // Stage 3: Latch Prdata from peripheral
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            psel_reg <= 1'b0;
            penable_reg <= 1'b0;
            write_reg <= 1'b0;
            addr_pipe <= 0;
            wdata_pipe <= 0;
            rdata_pipe <= 32'd0;
        end else begin
            if (mem_valid && (sel_tim2 || sel_spi1 || sel_usart1 || sel_rcc || sel_gpio)) begin
                // Stage 1: Latch address and control
                psel_reg <= 1'b1;
                penable_reg <= 1'b0;
                write_reg <= !(mem_wstrb == 4'd0); // Write if any byte enable
                addr_pipe <= mem_addr;
                wdata_pipe <= mem_wdata;
            end else if (psel_reg && !penable_reg) begin
                // Stage 2: Assert Penable
                penable_reg <= 1'b1;
            end else if (penable_reg) begin
                // Stage 3: Latch response and deassert
                rdata_pipe <= Prdata;
                psel_reg <= 1'b0;
                penable_reg <= 1'b0;
            end else begin
                psel_reg <= 1'b0;
                penable_reg <= 1'b0;
            end
        end
    end

endmodule
