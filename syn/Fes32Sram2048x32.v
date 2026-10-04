// ========================================================================
// Fes32Sram2048x32: 2048 x 32-bit single-port SRAM built from one
// ics55_ecos_sram_1024x80_m4 macro.
//
// The macro is 1024 rows x 80 bits. Two 32-bit words are packed into each
// row so that one macro provides the full 2048-word depth:
//
//   row  = word_addr[10:1]
//   half = word_addr[0]      -> 0 selects Q[31:0], 1 selects Q[63:32]
//   Q[79:64] are unused
//
// Write masking uses the macro's per-bit active-low WEB. Only the selected
// half is unmasked, so a write never disturbs the other word in the row; the
// byte granularity comes from wstrb.
//
// Timing: the macro registers its read data, so rdata is valid one clock after
// the address is presented - the same latency as the inferred-array
// implementation it replaces. half_r is registered alongside Q so the output
// mux lines up with the row the macro actually sampled.
//
// This file is synthesis-only. It is not part of the mpc-frame design sources
// (designs/fes32/design.json), so simulation keeps using the inferred arrays.
// ========================================================================

module Fes32Sram2048x32 (
    input  wire        clock,
    input  wire [10:0] word_addr,
    input  wire        en,        // access enable
    input  wire        we,        // write enable
    input  wire [3:0]  wstrb,     // byte write enables, active high
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);

    wire        half = word_addr[0];
    wire [9:0]  row  = word_addr[10:1];

    // Per-bit active-low write mask for one 32-bit half.
    wire [31:0] web32 = ~{ {8{wstrb[3]}}, {8{wstrb[2]}},
                           {8{wstrb[1]}}, {8{wstrb[0]}} };

    // Unmask only the selected half; the upper 16 bits are always masked.
    wire [79:0] web = half ? { 16'hFFFF, web32,          32'hFFFF_FFFF }
                           : { 16'hFFFF, 32'hFFFF_FFFF,  web32 };

    // Both halves carry the write data; WEB decides which one is written.
    wire [79:0] d = { wdata, wdata };

    wire [79:0] q;

    ics55_ecos_sram_1024x80_m4 u_sram (
        .A    (row),
        .D    (d),
        .Q    (q),
        .CEB  (~en),
        .GWEB (~we),
        .WEB  (web),
        .CLK  (clock),
        .MAR  (4'd0),
        .MARE (1'b0)
    );

    reg half_r;

    always @(posedge clock)
        if (en)
            half_r <= half;

    assign rdata = half_r ? q[63:32] : q[31:0];

endmodule
