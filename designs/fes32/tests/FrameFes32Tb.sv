// ========================================================================
// FrameFes32Tb: FrameTop integration testbench for FES32
//
// 中文：信号经过外部 user_io、FrameTop 与 Fes32 设计。
//       检查 design 编号能否被选中、设计是否驱动了它该驱动的引脚、
//       以及设计释放的引脚是否真正高阻并可被外部驱动。
// English: Signals travel through user_io, FrameTop and the Fes32 design.
//          Checks selection, that the design drives the pins it owns, and
//          that released pins are high-Z and externally drivable.
// ========================================================================

module FrameFes32Tb;

  // 由构建工具注入 ID（+define+FRAME_TEST_DESIGN_ID=<n>）。
  // The build tool injects the ID via +define+FRAME_TEST_DESIGN_ID=<n>.
`ifndef FRAME_TEST_DESIGN_ID
  initial $error("FRAME_TEST_DESIGN_ID must be provided by the build tool");
`endif

  // 通常保留 / Usually keep:
  // FrameTop 有 73 根 user_io：低 7 位选设计，其余 66 位连接设计 IO。
  // FrameTop has 73 user_io pins: low 7 select a design, the other 66 carry IO.
  localparam int IO_WIDTH = 73;
  localparam int DESIGN_ID_WIDTH = 7;
  localparam logic [DESIGN_ID_WIDTH-1:0] DESIGN_ID = `FRAME_TEST_DESIGN_ID;
  localparam time HALF_PERIOD = 5ns;

  // 构建工具生成的争用监测器通过 reset / test_io_oe / dut 连接，勿改名。
  // The generated contention monitor connects through reset, test_io_oe and
  // dut, so keep these infrastructure names.
  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [IO_WIDTH-1:0] test_io_out = '0;
  logic [IO_WIDTH-1:0] test_io_oe = '0;
  tri [IO_WIDTH-1:0] user_io;

  always #(HALF_PERIOD) clock = ~clock;

  // 三态连接：oe=0 时释放引脚，允许设计驱动。
  // Tri-state connection: with oe=0 the test releases the pin.
  for (genvar io_index = 0; io_index < IO_WIDTH; io_index++) begin : gen_test_io
    assign user_io[io_index] = test_io_oe[io_index]
      ? test_io_out[io_index]
      : 1'bz;
  end

  FrameTop dut (
    .clock(clock), .reset(reset), .user_io(user_io)
  );

  // FES32 拥有（io_oe=1）的 payload 位：0,2,3,5 以及 GPIO 组 8..39。
  // 其余位必须由设计释放为高阻。
  // Payload bits owned by FES32 (io_oe=1): 0,2,3,5 and the GPIO banks 8..39.
  // Every other bit must be released high-Z by the design.
  function automatic bit owned(int n);
    return (n == 0) || (n == 2) || (n == 3) || (n == 5) ||
           (n >= 8 && n <= 39);
  endfunction

  initial begin
    // ----------------------------------------------------------------
    // 通常保留 / Usually keep: 用 user_io[6:0] 驱动本设计编号
    // ----------------------------------------------------------------
    test_io_oe[DESIGN_ID_WIDTH-1:0] = '1;
    test_io_out[DESIGN_ID_WIDTH-1:0] = DESIGN_ID;
    repeat (20) @(posedge clock);
    @(negedge clock);
    reset = 1'b0;
    repeat (4) @(posedge clock);
    #1ns;

    if (!dut.selection_valid || !dut.design_selected[DESIGN_ID])
      $fatal(1, "FES32 was not selected through FrameTop");
    $display("Frame check 1: design %0d selected through FrameTop  OK", DESIGN_ID);

    // ----------------------------------------------------------------
    // 按设计修改 / Edit for your design:
    // payload 位换算 设计 io_*[n] <-> 外部 user_io[n+7]，逐位核对租约。
    // Payload mapping design io_*[n] <-> external user_io[n+7]; verify the
    // ownership contract bit by bit.
    // ----------------------------------------------------------------
    for (int n = 0; n <= 65; n++) begin
      if (owned(n)) begin
        if (user_io[DESIGN_ID_WIDTH + n] === 1'bz)
          $fatal(1, "owned payload bit %0d is high-Z: io_oe/output path inactive", n);
      end else begin
        if (user_io[DESIGN_ID_WIDTH + n] !== 1'bz)
          $fatal(1, "released payload bit %0d is not high-Z", n);
      end
    end
    $display("Frame check 2: all 66 owned/released bits honour the io_oe contract  OK");

    // ----------------------------------------------------------------
    // 输入通路：外部驱动一个设计释放的引脚（io_in[1] = UART RX）
    // Input path: drive a released pin externally (io_in[1] = UART RX).
    // 该引脚若被设计驱动，上面的检查已会失败；这里验证外部驱动能上总线。
    // ----------------------------------------------------------------
    test_io_oe[DESIGN_ID_WIDTH + 1] = 1'b1;
    test_io_out[DESIGN_ID_WIDTH + 1] = 1'b1;
    #1ns;
    if (user_io[DESIGN_ID_WIDTH + 1] !== 1'b1)
      $fatal(1, "external drive on UART RX did not reach the bus");
    $display("Frame check 3: external drive on released pin reaches the bus  OK");

    // 走到这里说明：选中、输出通路、io_oe 租约、高阻与外部驱动通路全部通过。
    // Reaching here means selection, output path, io_oe ownership, high-Z and
    // the external drive path all passed.
    $display("=== FES32 FRAME TEST PASS ===");
    $finish;
  end

  initial begin
    #(100000);
    $fatal(1, "TIMEOUT");
  end

endmodule
