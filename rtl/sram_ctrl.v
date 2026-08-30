// ========================================================================
// SRAM Memory Controller
// ========================================================================
// Memory-mapped SRAM controller for the STM32-compatible MCU.
// Provides read/write access to the system SRAM (0x20000000-0x2000FFFF).
// 64KB of SRAM memory.
// ========================================================================

module sram_ctrl (
    input  wire                     clk,
    input  wire                     resetn,

    // AHB Slave Interface
    input  wire                     Hsel,
    input  wire                     Hready,
    input  wire [1:0]               Htrans,
    input  wire                     Hwrite,
    input  wire [31:0]              Haddr,
    input  wire [31:0]              Hwdata,
    input  wire [2:0]               Hsize,
    input  wire                     Hlock,

    output wire                     Hready_out,
    output wire [31:0]              Hrdata,
    output wire                     Hresp
);

    // =================================================================
    // SRAM Memory Array (64KB = 16384 x 32 bits)
    // =================================================================
    reg [31:0] sram_mem [0:16383];

    // =================================================================
    // Write Logic
    // =================================================================
    always @(posedge clk) begin
        if (Hsel && Hwrite && Htrans[1] && Hready) begin
            // Byte-write enables based on Hsize and Hwstrb
            case (Hsize)
                3'd0: // 8-bit (byte)
                    if (Haddr[2] == 0 && Hwrite)
                        sram_mem[Haddr[31:2]][7:0] <= Hwdata[7:0];
                3'd1: // 16-bit (halfword)
                    if (Haddr[2] == 0 && Hwrite)
                        sram_mem[Haddr[31:2]][15:0] <= Hwdata[15:0];
                3'd2: // 32-bit (word)
                    if (Haddr[2] == 0 && Hwrite)
                        sram_mem[Haddr[31:2]] <= Hwdata;
                default:
                    if (Hwrite)
                        sram_mem[Haddr[31:2]] <= Hwdata;
            endcase
        end
    end

    // =================================================================
    // Read Logic
    // =================================================================
    reg [31:0] rdata_reg;
    reg        ready_reg;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rdata_reg <= 32'd0;
            ready_reg <= 1'b0;
        end else begin
            ready_reg <= 1'b1;
            if (Hsel && !Hwrite && Htrans[1] && Hready) begin
                rdata_reg <= sram_mem[Haddr[31:2]];
            end
        end
    end

    assign Hready_out = ready_reg;
    assign Hrdata = rdata_reg;
    assign Hresp = 2'b00;

endmodule
