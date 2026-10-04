# stm32-mcu 测试文档

## 1. 测试环境

### 1.1 工具

| 工具 | 版本 | 用途 |
|---|---|---|
| Icarus Verilog | 11.0+ | RTL 仿真 |
| Verilator | 5.050 | FrameTop 仿真 |
| Python | 3.x | cocotb 测试 |
| pytest | 7.0+ | 测试框架 |

### 1.2 仿真命令

```sh
# 独立单元测试
iverilog -g2012 -o Stm32McuTb.vvp \
  rtl/stm32_mcu_frame.sv \
  rtl/riscv_core.v \
  rtl/gpio.v \
  rtl/usart.v \
  rtl/spi.v \
  rtl/timer.v \
  rtl/nvic.v \
  tb/Stm32McuTb.v \
  && vvp Stm32McuTb.vvp

# FrameTop 集成测试
python3 ../mpc-frame/scripts/design_registry.py design-build \
  --design designs/stm32-mcu/design.json \
  --output-dir build/stm32-mcu \
  --kind frame \
  --registry designs/registry.json

# 波形查看
verilator --cc --trace -f build/stm32-mcu/sources.f \
  --top-module FrameStm32McuTb \
  && make -C obj_dir -f VFrameStm32McuTb.mk VFrameStm32McuTb
```

## 2. 独立单元测试

### 2.1 测试模块

```systemverilog
module Stm32McuTb;
  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [65:0] io_in = '0;
  wire [65:0] io_out;
  wire [65:0] io_oe;

  always #5 clock = ~clock;  // 100MHz

  Stm32Mcu #(
    .IO_WIDTH(66)
  ) dut (
    .clock(clock),
    .reset(reset),
    .io_in(io_in),
    .io_out(io_out),
    .io_oe(io_oe)
  );

  initial begin
    // 复位
    #20; reset = 1'b0;

    // 测试 1: GPIO 输出
    dut.io_out[22:7] = 16'hFFFF;
    dut.io_oe[22:7] = 1'b1;
    #10;
    assert(dut.gpio_odr == 16'hFFFF) else $fatal(1, "GPIO ODR write failed");

    // 测试 2: GPIO 方向
    dut.io_out[22:7] = 16'hAAAA;  // CRL: 1010 = output 2MHz
    #10;
    assert(dut.gpio_pad_oe == 16'hFFFF) else $fatal(1, "GPIO direction failed");

    // 测试 3: UART TX
    // 写 DR 寄存器触发发送
    // 检查 uart_tx 波形

    // 测试 4: SPI 发送
    // 写 DR 寄存器触发发送
    // 检查 mosi 波形

    // 测试 5: Timer
    // 写 CNT = 0, ARR = 100, CEN = 1
    // 等待 100 个时钟后检查 UIF

    // 测试 6: Flash 读写
    // 写 Flash[0] = 0xDEADBEEF
    // 读回验证

    // 测试 7: SRAM 读写
    // 写 SRAM[0] = 0xCAFE
    // 读回验证

    $display("All unit tests PASSED");
    $finish;
  end
endmodule
```

### 2.2 测试用例

| # | 测试项 | 输入 | 期望输出 | 通过条件 |
|---|---|---|---|---|
| 1 | GPIO 输出 | ODR = 0xFFFF | pad_o = 0xFFFF | ODR == 0xFFFF |
| 2 | GPIO 方向 | CRL = 0x33333333 | pad_oe = 0xFFFF | pad_oe == 0xFFFF |
| 3 | UART TX | DR = 0x41 | uart_tx 发送 0x41 | 波形检查 |
| 4 | SPI 发送 | DR = 0x55 | mosi 移位 0x55 | 波形检查 |
| 5 | Timer | CNT=0, ARR=100, CEN=1 | 100 个时钟后 UIF=1 | UIF == 1 |
| 6 | Flash 读 | Flash[0] = 0xDEADBEEF | 读回 0xDEADBEEF | mem_rdata == 0xDEADBEEF |
| 7 | SRAM 读写 | SRAM[0] = 0xCAFE | 读回 0xCAFE | sram_rdata == 0xCAFE |
| 8 | 中断路由 | GPIO 中断触发 | cpu_irq 置位 | cpu_irq == 1 |

## 3. FrameTop 集成测试

### 3.1 测试模块

基于 `FrameUserDesignTb.sv.in` 模板：

```systemverilog
module FrameStm32McuTb;
  // 通常保留
  localparam int IO_WIDTH = 73;
  localparam int DESIGN_ID_WIDTH = 7;
  localparam logic [DESIGN_ID_WIDTH-1:0] DESIGN_ID = `FRAME_TEST_DESIGN_ID;
  localparam time HALF_PERIOD = 5ns;

  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [IO_WIDTH-1:0] test_io_out = '0;
  logic [IO_WIDTH-1:0] test_io_oe = '0;
  tri [IO_WIDTH-1:0] user_io;

  always #(HALF_PERIOD) clock = ~clock;

  // 三态连接
  for (genvar io_index = 0; io_index < IO_WIDTH; io_index++) begin : gen_test_io
    assign user_io[io_index] = test_io_oe[io_index]
      ? test_io_out[io_index]
      : 1'bz;
  end

  FrameTop dut (
    .clock(clock), .reset(reset), .user_io(user_io)
  );

  initial begin
    // 设计选择
    test_io_oe[DESIGN_ID_WIDTH-1:0] = '1;
    test_io_out[DESIGN_ID_WIDTH-1:0] = DESIGN_ID;
    repeat (20) @(posedge clock);
    @(negedge clock);
    reset = 1'b0;
    repeat (4) @(posedge clock);
    #1ns;

    if (!dut.selection_valid || !dut.design_selected[DESIGN_ID])
      $fatal(1, "generated design was not selected through FrameTop");

    // 按设计修改
    // 测试 UART RX → TX 回环
    test_io_oe[DESIGN_ID_WIDTH + 1] = 1'b1;  // io_in[1] = UART RX
    test_io_out[DESIGN_ID_WIDTH + 1] = 1'b0;  // 发送起始位
    #1ns;
    // 检查 uart_tx 是否响应

    // 测试 GPIO 读写
    test_io_oe[DESIGN_ID_WIDTH + 22] = 1'b1;  // io_out[22] = GPIO ODR[0]
    test_io_out[DESIGN_ID_WIDTH + 22] = 1'b1;
    #1ns;
    // 检查 gpio_odr[0] 是否被设置

    // 检查 contention
    // test_io_oe 不应驱动设计正在输出的位

    $display("USER FRAME TEST PASS");
    $finish;
  end
endmodule
```

### 3.2 集成测试用例

| # | 测试项 | 描述 | 通过条件 |
|---|---|---|---|
| 1 | 设计选择 | 验证 design ID 选择时序 | `selection_valid` = 1 |
| 2 | UART 回环 | 驱动 RX，检查 TX | uart_tx 发送相同数据 |
| 3 | SPI 通信 | 驱动 MISO，检查 CLK/MOSI | mosi 移位正确 |
| 4 | GPIO 读写 | 写 ODR，检查 IDR 读回 | IDR == ODR |
| 5 | IO 冲突检测 | test_io_oe 与 design_io_oe 重叠 | 触发 contention 错误 |
| 6 | 复位隔离 | 重新复位后切换 design ID | 未选设计保持高阻 |
| 7 | 时钟门控 | 未选设计时钟关闭 | 时钟信号为 0 |
| 8 | 双向 IO | SWD 三态 | io_oe = 0 时为高阻 |

## 4. 回归测试

### 4.1 运行命令

```sh
# 用户检查
make check DESIGN=designs/stm32-mcu

# FrameTop 集成测试
make -f ../mpc-frame/Makefile.dev frame-test DESIGN=designs/stm32-mcu TEST=frame

# 波形查看
make -f ../mpc-frame/Makefile.dev wave DESIGN=designs/stm32-mcu

# 全量回归
make -f ../mpc-frame/Makefile.dev regression
```

### 4.2 失败诊断

| 错误信息 | 原因 | 解决方法 |
|---|---|---|
| `no unregistered user design found` | 没有未注册设计 | 运行 `make create NAME=stm32-mcu` |
| `multiple unregistered user designs found` | 多个未注册设计 | 使用 `DESIGN=designs/stm32-mcu` 指定 |
| `payload IO contention` | IO 冲突 | 检查 `test_io_oe` 与 `io_oe` 重叠 |
| `generated design was not selected` | design ID 未选中 | 检查 `FRAME_TEST_DESIGN_ID` |
| `generated file is stale` | 生成文件过期 | 运行 `make registry-generate` |
| `$fatal` | 测试断言失败 | 检查错误位置信息 |

### 4.3 波形分析

使用 GTKWave 查看 FST 波形：

```sh
gtkwave /tmp/stm32_top_tb.vcd
```

关键信号：
- `FrameTop.u_design_control.design_selected[1]`：设计 1 是否选中
- `FrameTop.payload_in` / `FrameTop.payload_out`：payload IO
- `u_design_registry.u_design_1.u_design.io_in` / `io_out` / `io_oe`：设计 IO
- `u_design.u_design.core.cpu_irq`：中断信号
