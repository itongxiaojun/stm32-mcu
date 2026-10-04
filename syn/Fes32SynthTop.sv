// ========================================================================
// Fes32SynthTop: ASIC synthesis wrapper for FES32
//
// The synthesis configuration
// ---------------------------
// Memories are implemented with the ICS55 SRAM macro
// `ics55_ecos_sram_1024x80_m4` (1024 rows x 80 bits). The wrapper
// syn/Fes32Sram2048x32.v packs two 32-bit words per row, so one macro gives
// 2048 x 32 bits (8 KB). Both memories are sized to exactly one macro:
//
//     flash 2048 x 32   (8 KB)  -> 1 macro
//     SRAM  2048 x 32   (8 KB)  -> 1 macro
//
// Selecting the macro implementation
// ----------------------------------
// The filelist adds `+define+FES32_SRAM_MACRO`, which switches the memory
// section of Fes32.sv from inferred arrays to the macro instances. Without
// that define nothing changes: simulation still uses the inferred arrays, so
// the unit tests, the FrameTop test and the boot-vector preload are untouched.
//
// Sizing constraint
// -----------------
// With FES32_SRAM_MACRO the wrapper supports at most 2048 words per memory.
// The design's own defaults (65536 flash / 16384 SRAM words) exceed that, so
// this top must be used for synthesis rather than instantiating Fes32 bare.
// ========================================================================

module Fes32SynthTop (
    input  logic        clock,
    input  logic        reset,
    input  logic [65:0] io_in,
    output wire  [65:0] io_out,
    output wire  [65:0] io_oe
);

    // Sized to exactly one ics55_ecos_sram_1024x80_m4 per memory:
    // the wrapper packs two 32-bit words per 80-bit row, so each macro
    // provides 2048 x 32 bits (8 KB).
    Fes32 #(
        .IO_WIDTH    (66),
        .FLASH_WORDS (2048),
        .SRAM_WORDS  (2048)
    ) u_fes32 (
        .clock  (clock),
        .reset  (reset),
        .io_in  (io_in),
        .io_out (io_out),
        .io_oe  (io_oe)
    );

endmodule
