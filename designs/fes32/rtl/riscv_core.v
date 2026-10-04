// ========================================================================
// RISC-V Core Wrapper - picorv32 Integration
// ========================================================================
// Wraps the picorv32 RISC-V core and connects its native memory interface
// to the SoC bus fabric.
// ========================================================================

module riscv_core #(
    parameter RESET_ADDR = 32'h00000000,
    parameter IRQ_ADDR   = 32'h00000010,
    parameter STACK_ADDR = 32'h2000FFFF
)(
    input  wire                     clk,
    input  wire                     resetn,

    // picorv32 Native Memory Interface
    output wire                     mem_valid,
    output wire                     mem_instr,
    input  wire                     mem_ready,
    output wire [31:0]              mem_addr,
    output wire [31:0]              mem_wdata,
    output wire [3:0]               mem_wstrb,
    input  wire [31:0]              mem_rdata,

    // Interrupt inputs (from NVIC)
    input  wire [31:0]              irq,

    // Trap output (for debug)
    output wire                     trap
);

    // =================================================================
    // picorv32 Instance - RV32IMC with IRQ support
    // =================================================================
    picorv32 #(
        .ENABLE_COUNTERS     (1),
        .ENABLE_COUNTERS64   (1),
        .ENABLE_REGS_16_31   (1),
        .ENABLE_REGS_DUALPORT (1),
        .LATCHED_MEM_RDATA   (0),
        .TWO_STAGE_SHIFT     (1),
        .BARREL_SHIFTER      (0),
        .TWO_CYCLE_COMPARE   (0),
        .TWO_CYCLE_ALU       (0),
        .COMPRESSED_ISA      (1),
        .CATCH_MISALIGN      (1),
        .CATCH_ILLINSN       (1),
        .ENABLE_MUL          (1),
        .ENABLE_FAST_MUL     (0),
        .ENABLE_DIV          (1),
        .ENABLE_IRQ          (1),
        .ENABLE_IRQ_QREGS    (1),
        .ENABLE_IRQ_TIMER    (1),
        .ENABLE_TRACE        (0),
        .REGS_INIT_ZERO      (0),
        .MASKED_IRQ          (32'hffffffff),
        .LATCHED_IRQ         (32'hffffffff),
        .PROGADDR_RESET      (RESET_ADDR),
        .PROGADDR_IRQ        (IRQ_ADDR),
        .STACKADDR           (STACK_ADDR)
    ) picorv32_inst (
        .clk          (clk),
        .resetn       (resetn),
        .trap         (trap),
        .mem_valid    (mem_valid),
        .mem_instr    (mem_instr),
        .mem_ready    (mem_ready),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .mem_wstrb    (mem_wstrb),
        .mem_rdata    (mem_rdata),
        .irq          (irq),
        .eoi          ()
    );

endmodule
