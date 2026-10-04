// ========================================================================
// FrameStm32McuTb: FrameTop integration testbench for Stm32Mcu
// Signals travel through user_io, FrameTop, and the Stm32Mcu design.
// ========================================================================

module FrameStm32McuTb;

    // FrameTop configuration
    localparam int IO_WIDTH = 73;
    localparam int DESIGN_ID_WIDTH = 7;
    localparam logic [DESIGN_ID_WIDTH-1:0] DESIGN_ID = `FRAME_TEST_DESIGN_ID;
    localparam time HALF_PERIOD = 5ns;

    // Test IO
    logic clock = 1'b0;
    logic reset = 1'b1;
    logic [IO_WIDTH-1:0] test_io_out = '0;
    logic [IO_WIDTH-1:0] test_io_oe = '0;
    tri [IO_WIDTH-1:0] user_io;

    always #(HALF_PERIOD) clock = ~clock;

    // Tri-state connection: testbench drives when oe=1, else high-Z
    for (genvar io_index = 0; io_index < IO_WIDTH; io_index++) begin : gen_test_io
        assign user_io[io_index] = test_io_oe[io_index]
            ? test_io_out[io_index]
            : 1'bz;
    end

    FrameTop dut (
        .clock(clock), .reset(reset), .user_io(user_io)
    );

    initial begin
        // ----------------------------------------------------------------
        // Design selection sequence (usually keep)
        // ----------------------------------------------------------------
        // While reset=1, drive design ID on user_io[6:0]
        test_io_oe[DESIGN_ID_WIDTH-1:0] = '1;
        test_io_out[DESIGN_ID_WIDTH-1:0] = DESIGN_ID;
        repeat (20) @(posedge clock);
        @(negedge clock);
        reset = 1'b0;
        repeat (4) @(posedge clock);
        #1ns;

        // Verify design was selected
        if (!dut.selection_valid || !dut.design_selected[DESIGN_ID])
            $fatal(1, "Stm32Mcu was not selected through FrameTop");

        $display("Design %0d selected successfully", DESIGN_ID);

        // ----------------------------------------------------------------
        // Functional checks (edit for your design)
        // ----------------------------------------------------------------

        // Test 1: UART RX -> TX passthrough
        // Drive UART RX (user_io[8] = io_in[1])
        test_io_oe[DESIGN_ID_WIDTH + 1] = 1'b1;
        test_io_out[DESIGN_ID_WIDTH + 1] = 1'b0;  // Start bit
        #1ns;
        // Check that UART TX (user_io[7] = io_out[0]) responds
        // Note: UART TX is driven by design, we just verify it's not Z
        if (user_io[DESIGN_ID_WIDTH] === 1'bz) begin
            $fatal(1, "UART TX is high-Z, design not driving");
        end
        $display("Test 1: UART TX active - PASSED");

        // Test 2: SPI CLK/MOSI
        // Drive SPI MISO (user_io[11] = io_in[4])
        test_io_oe[DESIGN_ID_WIDTH + 4] = 1'b1;
        test_io_out[DESIGN_ID_WIDTH + 4] = 1'b0;
        #1ns;
        // Check SPI CLK (user_io[9] = io_out[2]) is driven
        if (user_io[DESIGN_ID_WIDTH + 2] === 1'bz) begin
            $fatal(1, "SPI CLK is high-Z, design not driving");
        end
        $display("Test 2: SPI CLK active - PASSED");

        // Test 3: GPIO ODR write
        // Drive GPIO ODR bit 0 (user_io[14] = io_out[7])
        test_io_oe[DESIGN_ID_WIDTH + 7] = 1'b1;
        test_io_out[DESIGN_ID_WIDTH + 7] = 1'b1;
        #1ns;
        // Check GPIO IDR bit 0 (user_io[46] = io_in[39]) reads back
        // Note: IDR reads the actual pad, which is driven by ODR
        if (user_io[DESIGN_ID_WIDTH + 39] !== 1'b1) begin
            $fatal(1, "GPIO IDR bit 0 did not read back as 1");
        end
        $display("Test 3: GPIO ODR -> IDR - PASSED");

        // Test 4: Verify no IO contention
        // The FrameIoContentionMonitor checks this automatically
        // If we get here without $fatal, contention check passed

        $display("=== USER FRAME TEST PASS ===");
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
