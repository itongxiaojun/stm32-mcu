// ========================================================================
// AHB to APB Bridge
// ========================================================================
// Bridges AHB master requests to APB slave registers.
// Implements the standard APB transfer protocol with pipelining.
// ========================================================================

module ahb_apb_bridge #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter APB_BASE   = 32'h40000000,
    parameter APB_END    = 32'h4000FFFF
)(
    input  wire                     Hclk,
    input  wire                     Hresetn,

    // AHB Master Interface (simplified)
    input  wire                     Hsel,
    input  wire                     Hready_in,
    input  wire [1:0]               Htrans,
    input  wire                     Hwrite,
    input  wire [ADDR_WIDTH-1:0]    Haddr,
    input  wire [DATA_WIDTH-1:0]    Hwdata,

    output wire                     Hready_out,
    output wire [DATA_WIDTH-1:0]    Hrdata,
    output wire                     Hresp,

    // APB Slave Interface
    output wire                     Pclk,
    output wire                     Presetn,
    output wire [ADDR_WIDTH-1:0]    Paddr,
    output wire                     Psel,
    output wire                     Penable,
    output wire                     Pwrite,
    output wire [DATA_WIDTH-1:0]    Pwdata,
    input  wire [DATA_WIDTH-1:0]    Prdata,
    input  wire                     Pready,
    input  wire                     Pslverr
);

    // Pipe registers
    reg [ADDR_WIDTH-1:0]    addr_pipe;
    reg                     write_pipe;
    reg [DATA_WIDTH-1:0]    wdata_pipe;
    reg                     sel_pipe;
    reg                     enable_pipe;

    // HREADY output (always ready for this simple bridge)
    assign Hready_out = 1'b1;
    assign Hresp      = 2'b00;

    // Read data from APB slave (registered)
    reg [DATA_WIDTH-1:0] Hrdata_pipe;
    always @(posedge Hclk or negedge Hresetn) begin
        if (!Hresetn)
            Hrdata_pipe <= {DATA_WIDTH{1'b0}};
        else if (sel_pipe && enable_pipe)
            Hrdata_pipe <= Prdata;
    end
    assign Hrdata = Hrdata_pipe;

    // APB transfer generation
    // Stage 1: Latch address/control on HSEL+HREADY+HTRANS[1]
    always @(posedge Hclk or negedge Hresetn) begin
        if (!Hresetn) begin
            addr_pipe  <= 0;
            write_pipe <= 0;
            wdata_pipe <= 0;
            sel_pipe   <= 0;
            enable_pipe <= 0;
        end else begin
            if (Hsel && Hready_in && Htrans[1]) begin
                addr_pipe  <= Haddr;
                write_pipe <= Hwrite;
                wdata_pipe <= Hwdata;
                sel_pipe   <= 1;
            end else
                sel_pipe <= 1'b0;

            // PENABLE asserted one cycle after PSEL
            if (sel_pipe && !enable_pipe)
                enable_pipe <= 1'b1;
            else if (Pready)
                enable_pipe <= 1'b0;
        end
    end

    // APB interface signals
    assign Pclk     = Hclk;
    assign Presetn  = Hresetn;
    assign Paddr    = addr_pipe;
    assign Psel     = sel_pipe;
    assign Penable  = enable_pipe;
    assign Pwrite   = write_pipe;
    assign Pwdata   = wdata_pipe;

endmodule
