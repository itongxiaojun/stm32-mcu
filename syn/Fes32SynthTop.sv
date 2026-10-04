// ========================================================================
// Fes32SynthTop: ASIC synthesis wrapper for FES32
//
// Why this wrapper exists
// -----------------------
// The ICS55 flow available on the build host ships standard cells only
// (lib_ics55 contains just the two H7CL/H7CR .lib files) - there is no SRAM
// macro library. Yosys therefore maps every inferred memory to flip-flops via
// `memory_map`, at a cost of 32 flops per word.
//
// FES32's simulation defaults are the full STM32F103 sizes:
//     65536 flash words + 16384 SRAM words = 81920 words = 2,621,440 flops
// which is not a realisable cell count for this flow (and not for a real
// 55nm die either - a real implementation would use SRAM macros).
//
// This wrapper instantiates the exact same RTL with a reduced memory
// configuration so the resulting netlist is a realisable size. Nothing else
// differs: identical ports, identical logic, only the memory depth changes,
// which means high addresses alias instead of decoding.
//
// Simulation and the unit / FrameTop tests use the Fes32 defaults and are
// unaffected by this file.
// ========================================================================

module Fes32SynthTop (
    input  logic        clock,
    input  logic        reset,
    input  logic [65:0] io_in,
    output wire  [65:0] io_out,
    output wire  [65:0] io_oe
);

    // 2048 x 32 flash (8KB) + 1024 x 32 SRAM (4KB) = 98304 flops
    Fes32 #(
        .IO_WIDTH    (66),
        .FLASH_WORDS (2048),
        .SRAM_WORDS  (1024)
    ) u_fes32 (
        .clock  (clock),
        .reset  (reset),
        .io_in  (io_in),
        .io_out (io_out),
        .io_oe  (io_oe)
    );

endmodule
