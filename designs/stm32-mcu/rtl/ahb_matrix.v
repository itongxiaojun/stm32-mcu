// ========================================================================
// AHB Matrix - Simple Single-Master Crossbar
// ========================================================================
// Routes AHB master requests to one of multiple slaves based on address.
// ========================================================================

module ahb_matrix #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,

    // Slave 1: Flash
    parameter FLASH_BASE = 32'h00000000,
    parameter FLASH_END  = 32'h0003FFFF,

    // Slave 2: SRAM
    parameter SRAM_BASE  = 32'h20000000,
    parameter SRAM_END   = 32'h2000FFFF,

    // Slave 3: AHB Peripherals (RCC, GPIO)
    parameter AHBP_BASE  = 32'h40020000,
    parameter AHBP_END   = 32'h4002FFFF,

    // Slave 4: APB Bridge
    parameter APBP_BASE  = 32'h40000000,
    parameter APBP_END   = 32'h4001FFFF
)(
    input  wire                     Hclk,
    input  wire                     Hresetn,

    // AHB Master Interface
    input  wire                     Hsel,
    input  wire                     Hready,
    input  wire [1:0]               Htrans,
    input  wire                     Hwrite,
    input  wire [ADDR_WIDTH-1:0]    Haddr,
    input  wire [DATA_WIDTH-1:0]    Hwdata,
    input  wire [2:0]               Hsize,
    input  wire [1:0]               Hburst,
    input  wire                     Hlock,

    output wire                     Hready_out,
    output wire [DATA_WIDTH-1:0]    Hrdata,
    output wire                     Hresp,

    // Flash Slave
    output wire                     Hsel_flash,
    output wire [ADDR_WIDTH-1:0]    Haddr_flash,
    output wire                     Hwrite_flash,
    output wire [DATA_WIDTH-1:0]    Hwdata_flash,
    input  wire [DATA_WIDTH-1:0]    Hrdata_flash,
    input  wire                     Hready_flash,
    input  wire                     Hresp_flash,

    // SRAM Slave
    output wire                     Hsel_sram,
    output wire [ADDR_WIDTH-1:0]    Haddr_sram,
    output wire                     Hwrite_sram,
    output wire [DATA_WIDTH-1:0]    Hwdata_sram,
    input  wire [DATA_WIDTH-1:0]    Hrdata_sram,
    input  wire                     Hready_sram,
    input  wire                     Hresp_sram,

    // AHB Peripherals Slave
    output wire                     Hsel_ahbp,
    output wire [ADDR_WIDTH-1:0]    Haddr_ahbp,
    output wire                     Hwrite_ahbp,
    output wire [DATA_WIDTH-1:0]    Hwdata_ahbp,
    input  wire [DATA_WIDTH-1:0]    Hrdata_ahbp,
    input  wire                     Hready_ahbp,
    input  wire                     Hresp_ahbp,

    // APB Bridge Slave
    output wire                     Hsel_apbp,
    output wire [ADDR_WIDTH-1:0]    Haddr_apbp,
    output wire                     Hwrite_apbp,
    output wire [DATA_WIDTH-1:0]    Hwdata_apbp,
    input  wire [DATA_WIDTH-1:0]    Hrdata_apbp,
    input  wire                     Hready_apbp,
    input  wire                     Hresp_apbp
);

    // Decode which slave is selected
    wire sel_flash = Hsel && (Haddr >= FLASH_BASE) && (Haddr < FLASH_END);
    wire sel_sram  = Hsel && (Haddr >= SRAM_BASE)  && (Haddr < SRAM_END);
    wire sel_ahbp  = Hsel && (Haddr >= AHBP_BASE)  && (Haddr < AHBP_END);
    wire sel_apbp  = Hsel && (Haddr >= APBP_BASE)  && (Haddr < APBP_END);

    // Default to Flash if no match (includes boot vector region)
    wire [DATA_WIDTH-1:0] rdata_mux = sel_sram  ? Hrdata_sram  :
                                      sel_ahbp  ? Hrdata_ahbp  :
                                      sel_apbp  ? Hrdata_apbp  :
                                                  Hrdata_flash;

    wire ready_mux = sel_sram  ? Hready_sram  :
                     sel_ahbp  ? Hready_ahbp  :
                     sel_apbp  ? Hready_apbp  :
                                 Hready_flash;

    wire resp_mux = sel_sram  ? Hresp_sram  :
                    sel_ahbp  ? Hresp_ahbp  :
                    sel_apbp  ? Hresp_apbp  :
                                Hresp_flash;

    assign Hready_out = ready_mux;
    assign Hrdata     = rdata_mux;
    assign Hresp      = resp_mux;

    // Assign slave interfaces
    assign Hsel_flash  = sel_flash;
    assign Haddr_flash = Haddr;
    assign Hwrite_flash = Hwrite;
    assign Hwdata_flash = Hwdata;

    assign Hsel_sram  = sel_sram;
    assign Haddr_sram = Haddr;
    assign Hwrite_sram = Hwrite;
    assign Hwdata_sram = Hwdata;

    assign Hsel_ahbp  = sel_ahbp;
    assign Haddr_ahbp = Haddr;
    assign Hwrite_ahbp = Hwrite;
    assign Hwdata_ahbp = Hwdata;

    assign Hsel_apbp  = sel_apbp;
    assign Haddr_apbp = Haddr;
    assign Hwrite_apbp = Hwrite;
    assign Hwdata_apbp = Hwdata;

endmodule
